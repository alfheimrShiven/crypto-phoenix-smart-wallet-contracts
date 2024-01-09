// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { Script } from "forge-std/Script.sol";
import { EntryPoint } from "contracts/prebuilts/account/utils/EntryPoint.sol";
import { AccountLock } from "contracts/prebuilts/account/utils/AccountLock.sol";
import { AccountFactory } from "contracts/prebuilts/account/non-upgradeable/AccountFactory.sol";
import { Account } from "contracts/prebuilts/account/non-upgradeable/Account.sol";
import { Guardian } from "contracts/prebuilts/account/utils/Guardian.sol";
import { AccountGuardian } from "contracts/prebuilts/account/utils/AccountGuardian.sol";
import { AccountRecovery } from "contracts/prebuilts/account/utils/AccountRecovery.sol";

contract DeploySmartAccountUtilContracts is Script {
    address public admin = makeAddr("admin");
    address smartWalletAccount;

    // This deploy script should only be used for testing purposes as it deploys a smart account as well.
    function run() external returns (address, AccountFactory, Guardian, AccountLock, AccountGuardian, AccountRecovery) {
        EntryPoint _entryPoint;
        AccountFactory accountFactory;

        if (block.chainid == 11155111) {
            // Sepolia

            vm.startBroadcast(vm.envUint("SEPOLIA_PRIVATE_KEY"));
            _entryPoint = new EntryPoint();
            accountFactory = new AccountFactory(_entryPoint);

            ///@dev accountGuardian is deployed when new smart account is created using the AccountFactory::createAccount(...)
            smartWalletAccount = accountFactory.createAccount(admin, abi.encode("shiven@gmail.com"));
            vm.stopBroadcast();
        } else {
            // Anvil
            vm.startBroadcast();
            _entryPoint = new EntryPoint();
            accountFactory = new AccountFactory(_entryPoint);

            ///@dev accountGuardian is deployed when new smart account is created using the AccountFactory::createAccount(...)
            smartWalletAccount = accountFactory.createAccount(admin, abi.encode("shiven@gmail.com"));
            vm.stopBroadcast();
        }

        Guardian guardianContract = accountFactory.guardian();
        AccountLock accountLock = accountFactory.accountLock();

        AccountGuardian accountGuardian = AccountGuardian(guardianContract.getAccountGuardian(smartWalletAccount));

        AccountRecovery accountRecovery = AccountRecovery(guardianContract.getAccountRecovery(smartWalletAccount));

        return (smartWalletAccount, accountFactory, guardianContract, accountLock, accountGuardian, accountRecovery);
    }
}
