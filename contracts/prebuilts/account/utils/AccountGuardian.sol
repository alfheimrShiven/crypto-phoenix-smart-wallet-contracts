// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { IAccountGuardian } from "../interface/IAccountGuardian.sol";
import { Guardian } from "./Guardian.sol";
import { AccountLock } from "./AccountLock.sol";
import { AccountRecovery } from "./AccountRecovery.sol";

contract AccountGuardian is IAccountGuardian {
    event AccountRecoveryContractDeployed(address indexed);

    Guardian public guardianContract;
    AccountLock public accountLock;
    AccountRecovery public accountRecovery;
    address payable account;
    address[] private accountGuardians;
    address public owner;
    uint256 public constant MAX_GUARDIANS = 10;

    error NotAuthorized(address sender);

    constructor(
        Guardian _guardianContract,
        AccountLock _accountLock,
        address payable _account,
        address _emailService,
        string memory _recoveryEmail
    ) {
        guardianContract = _guardianContract;
        accountLock = _accountLock;
        account = _account;
        owner = account;
        accountRecovery = new AccountRecovery(account, _emailService, _recoveryEmail, address(this));
        guardianContract.linkAccountToAccountRecovery(account, address(accountRecovery));

        emit AccountRecoveryContractDeployed(address(accountRecovery));
    }

    modifier onlyOwnerAccountLockAccountRecovery() {
        if (msg.sender != owner && msg.sender != address(accountLock) && msg.sender != address(accountRecovery)) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    ////////////////////////////
    ///// External Functions////
    ////////////////////////////

    function addGuardian(address guardian) external onlyOwnerAccountLockAccountRecovery {
        (bool duplicateGuardian, ) = _checkIfGuardianExists(guardian);

        if (
            guardianContract.isVerifiedGuardian(guardian) &&
            accountGuardians.length <= MAX_GUARDIANS &&
            !duplicateGuardian
        ) {
            accountGuardians.push(guardian);
            guardianContract.addGuardianToAccount(guardian, owner);
            emit GuardianAdded(guardian);
        } else {
            revert GuardianCouldNotBeAdded(guardian);
        }
    }

    function removeGuardian(address guardian) external onlyOwnerAccountLockAccountRecovery {
        require(guardian != address(0), "guardian address being removed cannot be a zero address");

        (bool guardianFound, uint256 g) = _checkIfGuardianExists(guardian);

        if (guardianFound) {
            // replacing the guardian at index `g` with the last element of accountGuardians followed by poping one element out
            uint256 length = accountGuardians.length;

            if (g != length - 1) {
                accountGuardians[g] = accountGuardians[length - 1];
            }
            accountGuardians.pop();

            emit GuardianRemoved(guardian);
        } else {
            revert NotAGuardian(guardian);
        }
    }

    function getAllGuardians() external view onlyOwnerAccountLockAccountRecovery returns (address[] memory) {
        return accountGuardians;
    }

    function isAccountGuardian(address guardian) external view onlyOwnerAccountLockAccountRecovery returns (bool) {
        for (uint256 g = 0; g < accountGuardians.length; g++) {
            if (accountGuardians[g] == guardian) {
                return true;
            }
        }
        return false;
    }

    function getTotalGuardians() external view override returns (uint256) {}

    // internal functions //
    function _checkIfGuardianExists(address guardian) internal returns (bool, uint256) {
        for (uint256 g = 0; g < accountGuardians.length; g++) {
            if (accountGuardians[g] == guardian) return (true, g);
        }
        return (false, MAX_GUARDIANS); //
    }
}
