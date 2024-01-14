// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { Script } from "forge-std/Script.sol";
import { EntryPoint } from "contracts/prebuilts/account/utils/EntryPoint.sol";

contract DeployEntryPointContract is Script {
    EntryPoint _entryPoint;

    // This deploy script should only be used for testing purposes as it deploys a smart account as well.
    function run() external returns (address) {
        // Areon
        vm.startBroadcast();
        _entryPoint = new EntryPoint();
        vm.stopBroadcast();

        return address(_entryPoint);
    }
}
