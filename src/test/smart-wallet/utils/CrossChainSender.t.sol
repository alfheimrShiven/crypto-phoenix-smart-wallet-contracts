// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { CrossChainSender } from "contracts/prebuilts/account/utils/CrossChainSender.sol";
import { IERC20 } from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";

/// @dev This test should only run on Sepolia because the Chainlink's CCIP infra (Router, DON) is hosted on Sepolia and is required for these tests.
contract CrossChainSenderTest is Test {
    address public user = vm.envAddress("SEPOLIA_PUBLIC_KEY");
    uint64 constant SEPOLIA_CHAINID = 11155111;
    uint64 constant MUMBAI_CHAINID = 12532609583862916517;
    address payable constant CROSS_CHAIN_CONTRACT_SEPOLIA = payable(0xF2C512872d3bc22e6abee79f43cF0a2CE2b76d45);
    address constant CCIP_BnM_TOKEN_SEPOLIA = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
    uint256 public TRANSFER_AMOUNT = 1e15;
    CrossChainSender public crossChainSender;

    /// @dev will be called before all the tests and skip if the testing is not happening on Sepolia
    modifier onlyRunOnSepolia() {
        if (block.chainid != SEPOLIA_CHAINID) {
            vm.skip(true);
        } else {
            vm.prank(user);
            // adding Mumbai as a valid destination chain
            crossChainSender.allowlistDestinationChain(MUMBAI_CHAINID, true);
            _;
        }
    }

    function setUp() external {
        crossChainSender = CrossChainSender(CROSS_CHAIN_CONTRACT_SEPOLIA);
    }

    function testEstimateNative() external onlyRunOnSepolia {
        vm.prank(user);
        uint256 estimateNativeFee = crossChainSender.estimateNative(
            MUMBAI_CHAINID,
            user,
            CCIP_BnM_TOKEN_SEPOLIA,
            TRANSFER_AMOUNT
        );

        assert(estimateNativeFee > 0);
    }

    function testTransferTokensPayNative() external onlyRunOnSepolia {
        vm.startPrank(user);
        // Allowance (will be pulled by the cross chain contract) CCIP_BnM tokens to the Cross chain transaction contract to send to MUMBAI
        IERC20(CCIP_BnM_TOKEN_SEPOLIA).approve(address(crossChainSender), TRANSFER_AMOUNT);

        bytes32 messageId = crossChainSender.transferTokensPayNative{ value: 0.01 ether }(
            MUMBAI_CHAINID,
            user,
            CCIP_BnM_TOKEN_SEPOLIA,
            TRANSFER_AMOUNT
        );
        vm.stopPrank();

        assert(messageId != bytes32(0));
    }
}
