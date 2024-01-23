// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { CrossChainSender } from "contracts/prebuilts/account/utils/CrossChainSender.sol";

/// @dev This test should only run on Sepolia because the Chainlink's CCIP infra (Router, DON) is hosted on Sepolia and is required for these tests.
contract CrossChainSenderTest is Test {
    address public user = vm.envAddress("SEPOLIA_PUBLIC_KEY");
    uint64 constant SEPOLIA_CHAINID = 11155111;
    uint64 constant MUMBAI_CHAINID = 12532609583862916517;
    address payable constant CROSS_CHAIN_CONTRACT_SEPOLIA = payable(0xF9FD23DEe4549ffD17f088A5E08820B165f71665);
    address constant CCIP_BnM_TOKEN_SEPOLIA = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
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
        uint256 estimateNativeFee = crossChainSender.estimateNative(MUMBAI_CHAINID, user, CCIP_BnM_TOKEN_SEPOLIA, 1e12);

        assert(estimateNativeFee > 0);
    }
}
