// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Utils
import "../utils/BaseAccountFactory.sol";
import "../utils/BaseAccount.sol";
import "../../../external-deps/openzeppelin/proxy/Clones.sol";
import { DeployGuardianInfra } from "./DeployGuardianInfra.sol";
import { AccountGuardian } from "../utils/AccountGuardian.sol";
// Extensions
import "../../../extension/upgradeable//PermissionsEnumerable.sol";

// Interface
import "../interface/IEntrypoint.sol";

// Smart wallet implementation
import { GuardianAccount } from "./GuardianAccount.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

contract GuardianAccountFactory is BaseAccountFactory, DeployGuardianInfra {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Events //
    event GuardianAccountFactoryContractDeployed(address indexed accountFactory);
    event AccountGuardianContractDeployed(address indexed accountGuardianContract);

    // states
    address private constant emailService = address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720); // TODO: To be updated with the wallet address of the actual email service
    AccountGuardian public accountGuardian;

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entrypoint
    )
        BaseAccountFactory(address(new GuardianAccount(_entrypoint, address(this))), address(_entrypoint))
        DeployGuardianInfra()
    {
        emit GuardianAccountFactoryContractDeployed(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                        External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Account for admin.
    function createAccount(address _admin, bytes calldata _email) external virtual override returns (address) {
        address impl = BaseAccountFactory.accountImplementation;
        string memory recoveryEmail = abi.decode(_email, (string));

        bytes32 salt = _generateSalt(_email);

        address account = Clones.predictDeterministicAddress(impl, salt);

        if (account.code.length > 0) {
            revert("AccountFactory: account already registered");
            return account;
        }

        account = Clones.cloneDeterministic(impl, salt);

        if (msg.sender != entrypoint) {
            if (!BaseAccountFactory.allAccounts.add(account)) {
                revert("AccountFactory: account already registered");
            }
        }

        _initializeGuardianAccount(account, _admin, address(_guardian), _email);
        emit AccountCreated(account, _admin);

        accountGuardian = new AccountGuardian(_guardian, _accountLock, payable(account), emailService, recoveryEmail);

        _guardian.linkAccountToAccountGuardian(account, address(accountGuardian));

        emit AccountGuardianContractDeployed(address(accountGuardian));

        return account;
    }

    function onSignerAdded(address _signer, address _defaultAdmin, bytes memory _data) external {
        address account = msg.sender;
        require(_isAccountOfFactory(account, _data), "AccountFactory: not an account.");

        bool isNewSigner = accountsOfSigner[_signer].add(account);

        if (isNewSigner) {
            emit SignerAdded(account, _signer);
        }
    }

    /// @notice Callback function for an Account to un-register its signers.
    function onSignerRemoved(address _signer, address _defaultAdmin, bytes memory _data) external {
        address account = msg.sender;
        require(_isAccountOfFactory(account, _data), "AccountFactory: not an account.");

        bool isAccount = accountsOfSigner[_signer].remove(account);

        if (isAccount) {
            emit SignerRemoved(account, _signer);
        }
    }

    ///@dev  returns Account lock contract details
    function getAccountLock() external view returns (address) {
        return (address(_accountLock));
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/
    /// @dev Returns whether the caller is an account deployed by this factory.
    function _isAccountOfFactory(address _account, bytes memory _data) internal view virtual returns (bool) {
        bytes32 salt = _generateSalt(_data);
        address predicted = Clones.predictDeterministicAddress(BaseAccountFactory.accountImplementation, salt);
        return _account == predicted;
    }

    /// @dev Called in `createAccount`. Initializes the account contract created in `createAccount`.
    function _initializeGuardianAccount(
        address _account,
        address _admin,
        address commonGuardian,
        bytes calldata _email
    ) internal {
        GuardianAccount(payable(_account)).initialize(_admin, commonGuardian, address(_accountLock), _email);
    }

    /// @dev Returns the salt used when deploying an Account.
    function _generateSalt(bytes memory _data) internal view virtual returns (bytes32) {
        return keccak256(_data);
    }

    function _initializeAccount(address _account, address _admin, bytes calldata _data) internal virtual override {}
}
