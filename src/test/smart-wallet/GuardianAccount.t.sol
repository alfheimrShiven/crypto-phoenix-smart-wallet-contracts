// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

// Test utils
import "../utils/BaseTest.sol";

// Account Abstraction setup for smart wallets.
import { EntryPoint, IEntryPoint } from "contracts/prebuilts/account/utils/Entrypoint.sol";
import { UserOperation } from "contracts/prebuilts/account/utils/UserOperation.sol";

// Target
import { IAccountPermissions } from "contracts/extension/interface/IAccountPermissions.sol";
import { GuardianAccountFactory } from "contracts/prebuilts/account/guardian/GuardianAccountFactory.sol";
import { GuardianAccount } from "contracts/prebuilts/account/guardian/GuardianAccount.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

/// @dev This is a dummy contract to test contract interactions with Account.
contract Number {
    uint256 public num;

    function setNum(uint256 _num) public {
        num = _num;
    }

    function doubleNum() public {
        num *= 2;
    }

    function incrementNum() public {
        num += 1;
    }
}

contract GuardianAccountTest is BaseTest {
    // Target contracts
    EntryPoint private entrypoint;
    GuardianAccountFactory private guardianAccountFactory;

    // Mocks
    Number internal numberContract;

    // Test params
    uint256 private accountAdminPKey = 100;
    address private accountAdmin;

    uint256 private accountSignerPKey = 200;
    address private accountSigner;

    uint256 private nonSignerPKey = 300;
    address private nonSigner;

    // UserOp terminology: `sender` is the smart wallet.
    address private sender = 0x9E9A101B93f334400AC115b33C8b4AdA0646DA48;
    address payable private beneficiary = payable(address(0x45654));

    bytes32 private uidCache = bytes32("random uid");

    string public userEmail = "shiven@gmail.com";
    bytes public userEmailEncoded = abi.encode(userEmail);

    event AccountCreated(address indexed account, address indexed accountAdmin);

    function _prepareSignature(
        IAccountPermissions.SignerPermissionRequest memory _req
    ) internal view returns (bytes32 typedDataHash) {
        bytes32 typehashSignerPermissionRequest = keccak256(
            "SignerPermissionRequest(address signer,uint8 isAdmin,address[] approvedTargets,uint256 nativeTokenLimitPerTransaction,uint128 permissionStartTimestamp,uint128 permissionEndTimestamp,uint128 reqValidityStartTimestamp,uint128 reqValidityEndTimestamp,bytes32 uid)"
        );
        bytes32 nameHash = keccak256(bytes("Account"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 typehashEip712 = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 domainSeparator = keccak256(abi.encode(typehashEip712, nameHash, versionHash, block.chainid, sender));

        bytes memory encodedRequestStart = abi.encode(
            typehashSignerPermissionRequest,
            _req.signer,
            _req.isAdmin,
            keccak256(abi.encodePacked(_req.approvedTargets)),
            _req.nativeTokenLimitPerTransaction
        );

        bytes memory encodedRequestEnd = abi.encode(
            _req.permissionStartTimestamp,
            _req.permissionEndTimestamp,
            _req.reqValidityStartTimestamp,
            _req.reqValidityEndTimestamp,
            _req.uid
        );

        bytes32 structHash = keccak256(bytes.concat(encodedRequestStart, encodedRequestEnd));
        typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _signSignerPermissionRequest(
        IAccountPermissions.SignerPermissionRequest memory _req
    ) internal view returns (bytes memory signature) {
        bytes32 typedDataHash = _prepareSignature(_req);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountAdminPKey, typedDataHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _setupUserOp(
        uint256 _signerPKey,
        bytes memory _initCode,
        bytes memory _callDataForEntrypoint
    ) internal returns (UserOperation[] memory ops) {
        uint256 nonce = entrypoint.getNonce(sender, 0);

        // Get user op fields
        UserOperation memory op = UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: _initCode,
            callData: _callDataForEntrypoint,
            callGasLimit: 1e10,
            verificationGasLimit: 1e8,
            preVerificationGas: 1e8,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Sign UserOp
        bytes32 opHash = EntryPoint(entrypoint).getUserOpHash(op);
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(opHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPKey, msgHash);
        bytes memory userOpSignature = abi.encodePacked(r, s, v);

        address recoveredSigner = ECDSA.recover(msgHash, v, r, s);
        address expectedSigner = vm.addr(_signerPKey);
        assertEq(recoveredSigner, expectedSigner);

        op.signature = userOpSignature;

        // Store UserOp
        ops = new UserOperation[](1);
        ops[0] = op;
    }

    function _setupUserOpWithSender(
        bytes memory _initCode,
        bytes memory _callDataForEntrypoint,
        address _sender
    ) internal returns (UserOperation[] memory ops) {
        uint256 nonce = entrypoint.getNonce(_sender, 0);

        // Get user op fields
        UserOperation memory op = UserOperation({
            sender: _sender,
            nonce: nonce,
            initCode: _initCode,
            callData: _callDataForEntrypoint,
            callGasLimit: 1e10,
            verificationGasLimit: 1e8,
            preVerificationGas: 1e8,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Sign UserOp
        bytes32 opHash = EntryPoint(entrypoint).getUserOpHash(op);
        bytes32 msgHash = ECDSA.toEthSignedMessageHash(opHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountAdminPKey, msgHash);
        bytes memory userOpSignature = abi.encodePacked(r, s, v);

        address recoveredSigner = ECDSA.recover(msgHash, v, r, s);
        address expectedSigner = vm.addr(accountAdminPKey);
        assertEq(recoveredSigner, expectedSigner);

        op.signature = userOpSignature;

        // Store UserOp
        ops = new UserOperation[](1);
        ops[0] = op;
    }

    function _setupUserOpExecuteWithSender(
        bytes memory _initCode,
        address _target,
        uint256 _value,
        bytes memory _callData,
        address _sender
    ) internal returns (UserOperation[] memory) {
        bytes memory callDataForEntrypoint = abi.encodeWithSignature(
            "execute(address,uint256,bytes)",
            _target,
            _value,
            _callData
        );

        return _setupUserOpWithSender(_initCode, callDataForEntrypoint, _sender);
    }

    function _setupUserOpExecute(
        uint256 _signerPKey,
        bytes memory _initCode,
        address _target,
        uint256 _value,
        bytes memory _callData
    ) internal returns (UserOperation[] memory) {
        bytes memory callDataForEntrypoint = abi.encodeWithSignature(
            "execute(address,uint256,bytes)",
            _target,
            _value,
            _callData
        );

        return _setupUserOp(_signerPKey, _initCode, callDataForEntrypoint);
    }

    function _setupUserOpExecuteBatch(
        uint256 _signerPKey,
        bytes memory _initCode,
        address[] memory _target,
        uint256[] memory _value,
        bytes[] memory _callData
    ) internal returns (UserOperation[] memory) {
        bytes memory callDataForEntrypoint = abi.encodeWithSignature(
            "executeBatch(address[],uint256[],bytes[])",
            _target,
            _value,
            _callData
        );

        return _setupUserOp(_signerPKey, _initCode, callDataForEntrypoint);
    }

    /// @dev Returns the salt used when deploying an Account.
    function _generateSalt(bytes memory _data) internal view virtual returns (bytes32) {
        return keccak256(_data);
    }

    function setUp() public override {
        super.setUp();

        // Setup signers.
        accountAdmin = vm.addr(accountAdminPKey);
        vm.deal(accountAdmin, 100 ether);

        accountSigner = vm.addr(accountSignerPKey);
        nonSigner = vm.addr(nonSignerPKey);

        // Setup contracts
        entrypoint = new EntryPoint();
        // deploy account factory
        guardianAccountFactory = new GuardianAccountFactory(IEntryPoint(payable(address(entrypoint))));
        // deploy dummy contract
        numberContract = new Number();
    }

    /*///////////////////////////////////////////////////////////////
                        Test: creating an account
    //////////////////////////////////////////////////////////////*/

    /// @dev Create an account by directly calling the factory.
    function test_state_createGuardianAccount_viaFactory() public {
        vm.startPrank(accountAdmin);
        vm.expectEmit(true, true, false, true);
        emit AccountCreated(sender, accountAdmin);

        address smartWalletAccount = guardianAccountFactory.createAccount(accountAdmin, userEmailEncoded);

        address[] memory allAccounts = guardianAccountFactory.getAllAccounts();

        assert(smartWalletAccount != address(0));
        assertEq(allAccounts.length, 1);
        assertEq(allAccounts[0], sender);
        vm.stopPrank();
    }

    /// @dev Create an account via Entrypoint.
    function test_state_createGuardianAccount_viaEntrypoint() public {
        bytes memory initCallData = abi.encodeWithSignature(
            "createAccount(address,bytes)",
            accountAdmin,
            userEmailEncoded
        );
        bytes memory initCode = abi.encodePacked(abi.encodePacked(address(guardianAccountFactory)), initCallData);

        UserOperation[] memory userOpCreateAccount = _setupUserOpExecute(
            accountAdminPKey,
            initCode,
            address(0),
            0,
            bytes("")
        );

        vm.expectEmit(true, true, false, true);
        emit AccountCreated(sender, accountAdmin);
        EntryPoint(entrypoint).handleOps(userOpCreateAccount, beneficiary);

        address[] memory allAccounts = guardianAccountFactory.getAllAccounts();
        assertEq(allAccounts.length, 1);
        assertEq(allAccounts[0], sender);
    }

    /// @dev Try registering with factory with a contract not deployed by factory.
    function test_revert_onRegister_nonGuardianFactoryChildContract() public {
        vm.prank(address(0x12345));
        vm.expectRevert("AccountFactory: not an account.");
        guardianAccountFactory.onRegister(_generateSalt(userEmailEncoded));
    }

    /// @dev Create more than one accounts with the same admin.
    function test_state_guardianCreateAccount_viaEntrypoint_multipleAccountSameAdminDiffSalt() public {
        assertEq(guardianAccountFactory.totalAccounts(), 0);

        uint256 amount = 10;
        for (uint256 i = 0; i < amount; i += 1) {
            bytes memory userEmailDiffSaltCalldata = abi.encode(userEmail, i);
            bytes memory initCallData = abi.encodeWithSignature(
                "createAccount(address,bytes)",
                accountAdmin,
                userEmailDiffSaltCalldata
            );

            bytes memory initCode = abi.encodePacked(abi.encodePacked(address(guardianAccountFactory)), initCallData);

            address expectedSenderAddress = Clones.predictDeterministicAddress(
                guardianAccountFactory.accountImplementation(),
                _generateSalt(userEmailDiffSaltCalldata),
                address(guardianAccountFactory)
            );

            UserOperation[] memory userOpCreateAccount = _setupUserOpExecuteWithSender(
                initCode,
                address(0),
                0,
                userEmailDiffSaltCalldata,
                expectedSenderAddress
            );

            vm.expectEmit(true, true, false, true);
            emit AccountCreated(expectedSenderAddress, accountAdmin);
            EntryPoint(entrypoint).handleOps(userOpCreateAccount, beneficiary);
        }

        address[] memory allAccounts = guardianAccountFactory.getAllAccounts();
        assertEq(allAccounts.length, amount);
        assertEq(guardianAccountFactory.totalAccounts(), amount);

        for (uint256 i = 0; i < amount; i += 1) {
            assertEq(
                allAccounts[i],
                Clones.predictDeterministicAddress(
                    guardianAccountFactory.accountImplementation(),
                    _generateSalt(abi.encode(userEmail, i)),
                    address(guardianAccountFactory)
                )
            );
        }
    }

    /// @dev Cannot create more than one accounts with the same admin and the same email.
    function test_revert_guardianCreateAccount_viaFactory_multipleAccountSameAdminSameSalt() public {
        assertEq(guardianAccountFactory.totalAccounts(), 0);

        vm.expectEmit(true, true, false, true);
        emit AccountCreated(sender, accountAdmin);
        vm.prank(accountAdmin);
        guardianAccountFactory.createAccount(accountAdmin, userEmailEncoded);

        vm.expectRevert("AccountFactory: account already registered");
        vm.prank(accountAdmin);
        guardianAccountFactory.createAccount(accountAdmin, userEmailEncoded);

        assertEq(guardianAccountFactory.totalAccounts(), 1);
    }

    /// @dev Cannot create more than one accounts with the same admin and the same email.
    function test_revert_guardianCreateAccount_viaEntrypoint_multipleAccountSameAdminSameSalt() public {
        assertEq(guardianAccountFactory.totalAccounts(), 0);

        bytes memory initCallData = abi.encodeWithSignature(
            "createAccount(address,bytes)",
            accountAdmin,
            userEmailEncoded
        );

        bytes memory initCode = abi.encodePacked(abi.encodePacked(address(guardianAccountFactory)), initCallData);

        UserOperation[] memory userOpCreateAccount = _setupUserOpExecuteWithSender(
            initCode,
            address(0),
            0,
            userEmailEncoded,
            sender
        );

        vm.expectEmit(true, true, false, true);
        emit AccountCreated(sender, accountAdmin);
        EntryPoint(entrypoint).handleOps(userOpCreateAccount, beneficiary);

        vm.expectRevert();
        EntryPoint(entrypoint).handleOps(userOpCreateAccount, beneficiary);

        assertEq(guardianAccountFactory.totalAccounts(), 1);
    }

    /*///////////////////////////////////////////////////////////////
    //                     Test: performing a contract call
    //     //////////////////////////////////////////////////////////////*/

    function _guardian_setup_executeTransaction() internal {
        bytes memory initCallData = abi.encodeWithSignature(
            "createAccount(address,bytes)",
            accountAdmin,
            userEmailEncoded
        );
        bytes memory initCode = abi.encodePacked(abi.encodePacked(address(guardianAccountFactory)), initCallData);

        UserOperation[] memory userOpCreateAccount = _setupUserOpExecute(
            accountAdminPKey,
            initCode,
            address(0),
            0,
            bytes("")
        );

        EntryPoint(entrypoint).handleOps(userOpCreateAccount, beneficiary);
    }

    //     /// @dev Perform a state changing transaction directly via account.
    function test_state_guardianAccount_executeTransaction() public {
        _guardian_setup_executeTransaction();

        // Error: Returning a diff account address due to getAddress()
        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(numberContract.num(), 0);

        vm.prank(accountAdmin);
        GuardianAccount(payable(account)).execute(
            address(numberContract),
            0,
            abi.encodeWithSignature("setNum(uint256)", 42)
        );

        assertEq(numberContract.num(), 42);
    }

    /// @dev Perform many state changing transactions in a batch directly via account.
    function test_state_guardianAccount_executeBatchTransaction() public {
        _guardian_setup_executeTransaction();

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(numberContract.num(), 0);

        uint256 count = 3;
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory callData = new bytes[](count);

        for (uint256 i = 0; i < count; i += 1) {
            targets[i] = address(numberContract);
            values[i] = 0;
            callData[i] = abi.encodeWithSignature("incrementNum()", i);
        }

        vm.prank(accountAdmin);
        GuardianAccount(payable(account)).executeBatch(targets, values, callData);

        assertEq(numberContract.num(), count);
    }

    /// @dev Perform a state changing transaction via Entrypoint.
    function test_state_guardianAccount_executeTransaction_viaEntrypoint() public {
        _guardian_setup_executeTransaction();

        assertEq(numberContract.num(), 0);

        UserOperation[] memory userOp = _setupUserOpExecute(
            accountAdminPKey,
            bytes(""),
            address(numberContract),
            0,
            abi.encodeWithSignature("setNum(uint256)", 42)
        );

        EntryPoint(entrypoint).handleOps(userOp, beneficiary);

        assertEq(numberContract.num(), 42);
    }

    /// @dev Perform many state changing transactions in a batch via Entrypoint.
    function test_state_guardianAccount_executeBatchTransaction_viaEntrypoint() public {
        _guardian_setup_executeTransaction();

        assertEq(numberContract.num(), 0);

        uint256 count = 3;
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory callData = new bytes[](count);

        for (uint256 i = 0; i < count; i += 1) {
            targets[i] = address(numberContract);
            values[i] = 0;
            callData[i] = abi.encodeWithSignature("incrementNum()", i);
        }

        UserOperation[] memory userOp = _setupUserOpExecuteBatch(
            accountAdminPKey,
            bytes(""),
            targets,
            values,
            callData
        );

        EntryPoint(entrypoint).handleOps(userOp, beneficiary);

        assertEq(numberContract.num(), count);
    }

    /// @dev Perform many state changing transactions in a batch via Entrypoint.
    function test_state_guardianAccount_executeBatchTransaction_viaAccountSigner() public {
        _guardian_setup_executeTransaction();

        assertEq(numberContract.num(), 0);

        uint256 count = 3;
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory callData = new bytes[](count);

        for (uint256 i = 0; i < count; i += 1) {
            targets[i] = address(numberContract);
            values[i] = 0;
            callData[i] = abi.encodeWithSignature("incrementNum()", i);
        }

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        address[] memory approvedTargets = new address[](1);
        approvedTargets[0] = address(numberContract);

        IAccountPermissions.SignerPermissionRequest memory permissionsReq = IAccountPermissions.SignerPermissionRequest(
            accountSigner,
            0,
            approvedTargets,
            1 ether,
            0,
            type(uint128).max,
            0,
            type(uint128).max,
            uidCache
        );

        vm.prank(accountAdmin);
        bytes memory sig = _signSignerPermissionRequest(permissionsReq);

        GuardianAccount(payable(account)).setPermissionsForSigner(permissionsReq, sig);

        UserOperation[] memory userOp = _setupUserOpExecuteBatch(
            accountSignerPKey,
            bytes(""),
            targets,
            values,
            callData
        );

        EntryPoint(entrypoint).handleOps(userOp, beneficiary);

        assertEq(numberContract.num(), count);
    }

    /// @dev Perform a state changing transaction via Entrypoint and a SIGNER_ROLE holder.
    function test_state_guardianAccount_executeTransaction_viaAccountSigner() public {
        _guardian_setup_executeTransaction();

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        address[] memory approvedTargets = new address[](1);
        approvedTargets[0] = address(numberContract);

        IAccountPermissions.SignerPermissionRequest memory permissionsReq = IAccountPermissions.SignerPermissionRequest(
            accountSigner,
            0,
            approvedTargets,
            1 ether,
            0,
            type(uint128).max,
            0,
            type(uint128).max,
            uidCache
        );

        vm.prank(accountAdmin);
        bytes memory sig = _signSignerPermissionRequest(permissionsReq);
        GuardianAccount(payable(account)).setPermissionsForSigner(permissionsReq, sig);

        assertEq(numberContract.num(), 0);

        UserOperation[] memory userOp = _setupUserOpExecute(
            accountSignerPKey,
            bytes(""),
            address(numberContract),
            0,
            abi.encodeWithSignature("setNum(uint256)", 42)
        );

        EntryPoint(entrypoint).handleOps(userOp, beneficiary);

        assertEq(numberContract.num(), 42);
    }

    /// @dev Revert: perform a state changing transaction via Entrypoint without appropriate permissions.
    function test_revert_guardianAccount_executeTransaction_nonSigner_viaEntrypoint() public {
        _guardian_setup_executeTransaction();

        assertEq(numberContract.num(), 0);

        UserOperation[] memory userOp = _setupUserOpExecute(
            accountSignerPKey,
            bytes(""),
            address(numberContract),
            0,
            abi.encodeWithSignature("setNum(uint256)", 42)
        );

        vm.expectRevert();
        EntryPoint(entrypoint).handleOps(userOp, beneficiary);
    }

    /// @dev Revert: non-admin performs a state changing transaction directly via account contract.
    function test_revert_executeTransaction_nonSigner_viaDirectCall() public {
        _guardian_setup_executeTransaction();

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);
        address[] memory approvedTargets = new address[](1);
        approvedTargets[0] = address(numberContract);
        IAccountPermissions.SignerPermissionRequest memory permissionsReq = IAccountPermissions.SignerPermissionRequest(
            accountSigner,
            0,
            approvedTargets,
            1 ether,
            0,
            type(uint128).max,
            0,
            type(uint128).max,
            uidCache
        );

        vm.prank(accountAdmin);
        bytes memory sig = _signSignerPermissionRequest(permissionsReq);
        GuardianAccount(payable(account)).setPermissionsForSigner(permissionsReq, sig);

        assertEq(numberContract.num(), 0);

        vm.prank(accountSigner);
        vm.expectRevert("Account: not admin or EntryPoint.");
        GuardianAccount(payable(account)).execute(
            address(numberContract),
            0,
            abi.encodeWithSignature("setNum(uint256)", 42)
        );
    }

    /*///////////////////////////////////////////////////////////////
    //                 Test: receiving and sending native tokens
    //     ///////////////////////////////////////////////////////////*/

    /// @dev Send native tokens to an account.
    function test_state_guardianAccount_accountReceivesNativeTokens() public {
        _guardian_setup_executeTransaction();

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(address(account).balance, 0);

        vm.prank(accountAdmin);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = payable(account).call{ value: 1000 }("");

        // Silence warning: Return value of low-level calls not used.
        (success, data) = (success, data);

        assertEq(address(account).balance, 1000);
    }

    /// @dev Transfer native tokens out of an account.
    function test_state_guardianAccount_transferOutsNativeTokens() public {
        _guardian_setup_executeTransaction();

        uint256 value = 1000;

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);
        vm.prank(accountAdmin);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = payable(account).call{ value: value }("");
        assertEq(address(account).balance, value);

        // Silence warning: Return value of low-level calls not used.
        (success, data) = (success, data);

        address recipient = address(0x3456);

        UserOperation[] memory userOp = _setupUserOpExecute(accountAdminPKey, bytes(""), recipient, value, bytes(""));

        EntryPoint(entrypoint).handleOps(userOp, beneficiary);
        assertEq(address(account).balance, 0);
        assertEq(recipient.balance, value);
    }

    /// @dev Add and remove a deposit for the account from the Entrypoint.

    function test_state_guardianAccount_addAndWithdrawDeposit() public {
        _guardian_setup_executeTransaction();

        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(EntryPoint(entrypoint).balanceOf(account), 0);

        vm.prank(accountAdmin);
        GuardianAccount(payable(account)).addDeposit{ value: 1000 }();
        assertEq(EntryPoint(entrypoint).balanceOf(account), 1000);

        vm.prank(accountAdmin);
        GuardianAccount(payable(account)).withdrawDepositTo(payable(accountSigner), 500);
        assertEq(EntryPoint(entrypoint).balanceOf(account), 500);
    }

    /*///////////////////////////////////////////////////////////////
    //                 Test: receiving ERC-721 and ERC-1155 NFTs
    //     ///////////////////////////////////////////////////////////*/

    /// @dev Send an ERC-721 NFT to an account.
    function test_state_guardianAccount_receiveERC721NFT() public {
        _guardian_setup_executeTransaction();
        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(erc721.balanceOf(account), 0);

        erc721.mint(account, 1);

        assertEq(erc721.balanceOf(account), 1);
    }

    /// @dev Send an ERC-1155 NFT to an account.
    function test_state_guardianAccount_receiveERC1155NFT() public {
        _guardian_setup_executeTransaction();
        address account = guardianAccountFactory.getAddress(accountAdmin, userEmailEncoded);

        assertEq(erc1155.balanceOf(account, 0), 0);

        erc1155.mint(account, 0, 1);

        assertEq(erc1155.balanceOf(account, 0), 1);
    }

    //     /*///////////////////////////////////////////////////////////////
    //                 Test: setting contract metadata
    //     //////////////////////////////////////////////////////////////*/

    //     /// @dev Set contract metadata via admin or entrypoint.
    //     function test_state_contractMetadata() public {
    //         _guardian_setup_executeTransaction();
    //         address account = guardianAccountFactory.getAddress(accountAdmin, bytes(""));

    //         vm.prank(accountAdmin);
    //         GuardianAccount(payable(account)).setContractURI("https://example.com");
    //         assertEq(GuardianAccount(payable(account)).contractURI(), "https://example.com");

    //         UserOperation[] memory userOp = _setupUserOpExecute(
    //             accountAdminPKey,
    //             bytes(""),
    //             address(account),
    //             0,
    //             abi.encodeWithSignature("setContractURI(string)", "https://thirdweb.com")
    //         );

    //         EntryPoint(entrypoint).handleOps(userOp, beneficiary);
    //         assertEq(GuardianAccount(payable(account)).contractURI(), "https://thirdweb.com");

    //         address[] memory approvedTargets = new address[](0);

    //         IAccountPermissions.SignerPermissionRequest memory permissionsReq = IAccountPermissions.SignerPermissionRequest(
    //             accountSigner,
    //             0,
    //             approvedTargets,
    //             1 ether,
    //             0,
    //             type(uint128).max,
    //             0,
    //             type(uint128).max,
    //             uidCache
    //         );

    //         vm.prank(accountAdmin);
    //         bytes memory sig = _signSignerPermissionRequest(permissionsReq);
    //         GuardianAccount(payable(account)).setPermissionsForSigner(permissionsReq, sig);

    //         UserOperation[] memory userOpViaSigner = _setupUserOpExecute(
    //             accountSignerPKey,
    //             bytes(""),
    //             address(account),
    //             0,
    //             abi.encodeWithSignature("setContractURI(string)", "https://thirdweb.com")
    //         );

    //         vm.expectRevert();
    //         EntryPoint(entrypoint).handleOps(userOpViaSigner, beneficiary);
    //     }
}
