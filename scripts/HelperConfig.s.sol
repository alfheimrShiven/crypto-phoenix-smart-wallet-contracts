// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { Script } from "forge-std/Script.sol";
import { EntryPoint } from "contracts/prebuilts/account/utils/EntryPoint.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address networkAccount;
        address payable entryPoint;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111 || block.chainid == 80001)
            activeNetworkConfig = NetworkConfig({
                networkAccount: vm.envAddress("MUMBAI_PUBLIC_KEY"),
                entryPoint: payable(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789)
            });
        else if (block.chainid == 462)
            activeNetworkConfig = NetworkConfig({
                networkAccount: vm.envAddress("AREON_PUBLIC_KEY"),
                entryPoint: payable(0x62e6700c57A69FD6477e12744C6A486AF4F2bd2A)
            });
        else {
            vm.broadcast();
            EntryPoint entryPoint = new EntryPoint();

            activeNetworkConfig = NetworkConfig({
                networkAccount: vm.envAddress("ANVIL_PUBLIC_KEY"),
                entryPoint: payable(address(entryPoint))
            });
        }
    }
}
