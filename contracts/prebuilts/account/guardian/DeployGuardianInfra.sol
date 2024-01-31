// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import { Guardian } from "../utils/Guardian.sol";
import { AccountLock } from "../utils/AccountLock.sol";

contract DeployGuardianInfra {
    event GuardianContractDeployed(address indexed guardianContract);
    event AccountLockContractDeployed(address indexed accountLockContract);

    Guardian internal _guardian;
    AccountLock internal _accountLock;

    constructor() {
        _guardian = new Guardian();
        _accountLock = new AccountLock(_guardian);

        // emit the contract addresses
        emit GuardianContractDeployed(address(_guardian));
        emit AccountLockContractDeployed(address(_accountLock));
    }

    /////////////////////////////////////
    ///////// Getter Functions //////////
    /////////////////////////////////////
    function getGuardianContract() external view returns (Guardian) {
        return _guardian;
    }

    function getAccountLockContract() external view returns (AccountLock) {
        return _accountLock;
    }
}
