// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Utils
import "../utils/BaseAccountFactory.sol";
import "../utils/BaseAccount.sol";
import "../../../external-deps/openzeppelin/proxy/Clones.sol";
import { Guardian } from "../utils/Guardian.sol";
import { AccountLock } from "../utils/AccountLock.sol";
import { AccountGuardian } from "../utils/AccountGuardian.sol";

// Extensions
import "../../../extension/upgradeable//PermissionsEnumerable.sol";
import "../../../extension/upgradeable//ContractMetadata.sol";

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

contract GuardianAccountFactory is BaseAccountFactory, ContractMetadata, PermissionsEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // states
    EnumerableSet.AddressSet private allAccounts;
    address private constant emailService = address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720); // TODO: To be updated with the wallet address of the actual email service
    Guardian public guardian;
    AccountLock public accountLock;
    AccountGuardian public accountGuardian;

    // Events //
    event GuardianAccountFactoryContractDeployed(address indexed accountFactory);
    event GuardianContractDeployed(address indexed guardianContract);
    event AccountLockContractDeployed(address indexed accountLockContract);
    event AccountGuardianContractDeployed(address indexed accountGuardianContract);

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEntryPoint _entrypoint
    ) BaseAccountFactory(address(new GuardianAccount(_entrypoint, address(this))), address(_entrypoint)) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        guardian = new Guardian();
        accountLock = new AccountLock(guardian);

        // emit the contract addresses
        emit GuardianContractDeployed(address(guardian));
        emit AccountLockContractDeployed(address(accountLock));
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
            return account;
        }

        account = Clones.cloneDeterministic(impl, salt);

        if (msg.sender != entrypoint) {
            require(allAccounts.add(account), "AccountFactory: account already registered");
        }

        _initializeGuardianAccount(account, _admin, address(guardian), _email);
        emit AccountCreated(account, _admin);

        accountGuardian = new AccountGuardian(guardian, accountLock, payable(account), emailService, recoveryEmail);

        guardian.linkAccountToAccountGuardian(account, address(accountGuardian));

        emit AccountGuardianContractDeployed(address(accountGuardian));

        return account;
    }

    /// @notice Callback function for an Account to register itself on the factory.
    function onRegister(address _defaultAdmin, bytes memory _data) external {
        address account = msg.sender;
        require(_isAccountOfFactory(account, _data), "AccountFactory: not an account.");

        require(allAccounts.add(account), "AccountFactory: account already registered");
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
        return (address(accountLock));
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
        bytes calldata _data
    ) internal {
        GuardianAccount(payable(_account)).initialize(_admin, commonGuardian, address(accountLock), _data);
    }

    /// @dev Returns whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view virtual override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Returns the salt used when deploying an Account.
    function _generateSalt(bytes memory _data) internal view virtual returns (bytes32) {
        return keccak256(_data);
    }

    function _initializeAccount(address _account, address _admin, bytes calldata _data) internal virtual override {}
}
