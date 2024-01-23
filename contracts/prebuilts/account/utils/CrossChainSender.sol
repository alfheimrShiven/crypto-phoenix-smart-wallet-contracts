// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { OwnerIsCreator } from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { IERC20 } from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";
import "./SafeMath.sol";

/// @title - A simple contract for transferring tokens across chains and paying fees in native token.
contract CrossChainSender is OwnerIsCreator {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error NotEnoughBalanceSent(uint256 currentBalance, uint256 calculatedFees);
    error TransferTokenUserBalInsufficient(uint256 tokensToTransfer, uint256 transferTokenBalanceOfUser);
    error ApprovedLinkAmountInsufficient(uint256 approvedAmount, uint256 expectedAmount);
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    // Event emitted when the tokens are transferred to an account on another chain.
    event TokensTransferred(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );

    //Following standard for calculation
    using SafeMath for uint256;

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedChains;
    mapping(address sender => mapping(address token => uint256 tokenAmount)) private senderToTokenToTokenAmount;
    IRouterClient private s_router;

    struct TokenParams {
        address _token;
        address _receiver;
        uint _tokenAmount;
    }

    address public nativeToken;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    constructor(address _router) {
        s_router = IRouterClient(_router);
        nativeToken = address(0); // acccording to CCIP docs, address(0) means native token.
    }

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        if (!allowlistedChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedChains[_destinationChainSelector] = allowed;
    }

    /// @dev Estimates amount of token required for the trnsaction
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return  estimate estimated  amount
    function estimateNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external view returns (uint) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(0) means fees are paid in native gas
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _token, _amount, nativeToken);

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);

        //Get 10% of the fee
        uint256 tenPercent = fees.mul(10).div(100);

        //Add 10% to the fees as slippage
        uint256 estimate = fees.add(tenPercent);
        return estimate;
    }

    /// @notice Transfer tokens to receiver on the destination chain.
    /// @notice Pay in native gas such as ETH on Ethereum or MATIC on Polgon.
    /// @notice the token must be in the list of supported tokens.
    /// @notice This function can only be called by the owner.
    /// @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @return messageId The ID of the message that was sent.
    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _sender,
        TokenParams memory _tokenParams
    ) external payable onlyAllowlistedChain(_destinationChainSelector) returns (bytes32 messageId) {
        // (address receiver, address transferToken, uint256 transferAmount) = _tokenParams(); // @ques IDK why this destructuring isnt valid

        address receiver = _tokenParams._receiver;
        address transferToken = _tokenParams._token;
        uint256 transferAmount = _tokenParams._tokenAmount;

        // CHECKS
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            receiver,
            transferToken,
            transferAmount,
            nativeToken
        );

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);
        // Get the sender's balance of the token they want to transfer
        uint256 senderBalanceOfTransferToken = IERC20(transferToken).balanceOf(msg.sender);

        //verify enough transfer token is there with the sender
        if (senderBalanceOfTransferToken < transferAmount)
            revert TransferTokenUserBalInsufficient(transferAmount, senderBalanceOfTransferToken);

        //verify native amount sent is enough
        if (fees > msg.value) revert NotEnoughBalanceSent(msg.value, fees);

        // EFFECTS
        //transfer token from user to contract
        IERC20(transferToken).transferFrom(_sender, address(this), transferAmount);
        senderToTokenToTokenAmount[_sender][transferToken] = transferAmount; // recording token deposit amount

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(transferToken).approve(address(s_router), transferAmount);

        // Send the message through the router and store the returned message ID
        messageId = s_router.ccipSend{ value: fees }(_destinationChainSelector, evm2AnyMessage);

        senderToTokenToTokenAmount[_sender][transferToken] = 0; // updating mapping after transfer
        // Emit an event with message details
        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _tokenParams._receiver,
            _tokenParams._token,
            _tokenParams._tokenAmount,
            address(0),
            fees
        );

        //refund user the balance
        if (msg.value > fees) {
            uint extraFee = msg.value - fees;
            //send the balance to user
            (bool sent, ) = _sender.call{ value: extraFee }("");
            require(sent, "Failed to refund user");
        }

        // Return the message ID
        return messageId;
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _transferToken The token to be transferred.
    /// @param _transferAmount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        address _transferToken,
        uint256 _transferAmount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({ token: _transferToken, amount: _transferAmount });

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: "", // No data
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit to 0 as we are not sending any data
                    Client.EVMExtraArgsV1({ gasLimit: 0 })
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is transferred to the contract without any data.
    receive() external payable {}

    /// @notice Allows any sender to withdraw all tokens of a specific ERC20 token if any balance is remaining.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(address _beneficiary, address _token) public {
        // Retrieve the balance of this contract
        uint256 amount = senderToTokenToTokenAmount[msg.sender][_token];

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }
}
