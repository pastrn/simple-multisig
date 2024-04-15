// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Wallet } from "src/Wallet.sol";
import { IWallet } from "src/interfaces/IWallet.sol";
import { IWalletTypes } from "src/interfaces/IWallet.sol";

contract WalletTest is Test {
    event FundsDeposited(address, uint256);
    event TransactionSubmitted(address indexed owner, uint256 indexed txId);
    event TransactionApproved(address indexed owner, uint256 indexed txId);
    event ApprovalRevoked(address indexed owner, uint256 indexed txId);
    event TransactionExecuted(address indexed owner, uint256 indexed txId);
    event TransactionDeclined(uint256 indexed txId);
    event OwnersUpdated(address[] newOwners, uint8 newRequiredApprovals);

    error TestError();

    Wallet internal wallet;

    address internal constant DEPLOYER = address(bytes20(keccak256("deployer")));
    address internal constant OWNER_1 = address(bytes20(keccak256("owner_1")));
    address internal constant OWNER_2 = address(bytes20(keccak256("owner_2")));
    address internal constant OWNER_3 = address(bytes20(keccak256("owner_3")));
    address internal constant ATTACKER = address(bytes20(keccak256("attacker")));

    uint8 internal constant REQUIRED_APPROVALS = 2;
    uint256 internal constant SUPPLY_VALUE = 100 ether;
    uint256 internal constant DEPOSIT_VALUE = 1 ether;

    IWallet.Transaction internal defaultTx = IWalletTypes.Transaction(
        DEPLOYER,
        0, // id
        0, // value
        0, // executionDate
        IWalletTypes.TransactionStatus.Pending,
        bytes("random")
    );

    address[] internal OWNERS_ARRAY = [OWNER_1, OWNER_2, OWNER_3];
    address[] internal DUPLICATE_OWNERS_ARRAY = [OWNER_1, OWNER_2, OWNER_1];
    address[] internal NEW_OWNERS_ARRAY = [OWNER_1, OWNER_2, DEPLOYER];
    address[] internal EMPTY_ARRAY;
    address[] internal ZERO_ADDRESS_OWNERS_ARRAY = [OWNER_1, address(0), OWNER_3];

    function setUp() public  {
        wallet = new Wallet(OWNERS_ARRAY, REQUIRED_APPROVALS);
    }

    function test_constructor() public {
        assertEq(wallet.getRequiredApprovals(), REQUIRED_APPROVALS);
        _compareArrays(OWNERS_ARRAY, wallet.getOwners());
    }

    function test_deposit() public {
        vm.deal(OWNER_1, DEPOSIT_VALUE);

        vm.startPrank(OWNER_1);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.FundsDeposited(OWNER_1, DEPOSIT_VALUE);
        wallet.deposit{value: DEPOSIT_VALUE}();
        vm.stopPrank();
    }

    function test_deposit_Revert_If_ZeoDepositAmount() public {
        vm.prank(OWNER_1);
        vm.expectRevert(Wallet.ZeroDepositValue.selector);
        wallet.deposit{value: 0}();
    }

    function test_submitTransaction() public {
        vm.prank(OWNER_1);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionSubmitted(OWNER_1, 0);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        IWallet.Transaction memory submittedTx = wallet.getTransaction(0);
        _compareTransactions(submittedTx, defaultTx);
    }

    function test_submitTransaction_Revert_If_CallerNotOwner() public {
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
    }

    function test_submitAndApproveTransaction() public {
        vm.prank(OWNER_1);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionSubmitted(OWNER_1, 0);
        emit IWallet.TransactionApproved(OWNER_1, 0);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        IWallet.Transaction memory submittedTx = wallet.getTransaction(txId);
        _compareTransactions(submittedTx, defaultTx);
        assertEq(wallet.getApprovalCount(txId), 1);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), true);
    }

    function test_submitAndApproveTransaction_Revert_If_CallerNotOwner() public {
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
    }

    function test_approveTransaction() public {
        vm.startPrank(OWNER_1);
        uint256 txId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        assertEq(wallet.getApprovalCount(txId), 0);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionApproved(OWNER_1, 0);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 1);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), true);
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 2);
        assertEq(wallet.getApprovalStatus(txId, OWNER_2), true);
    }

    function test_approveTransaction_Revert_If_TransactionNotExist() public {
        vm.startPrank(OWNER_1);
        uint256 txCount = wallet.getTransactionCount();
        vm.expectRevert(Wallet.TransactionNotExist.selector);
        wallet.approveTransaction(txCount + 1);
    }

    function test_approveTransaction_Revert_If_TransactionAlreadyApproved() public {
        vm.startPrank(OWNER_1);
        uint256 txId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        assertEq(wallet.getApprovalCount(txId), 0);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 1);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), true);
        vm.expectRevert(Wallet.AlreadyApproved.selector);
        wallet.approveTransaction(txId);
        vm.stopPrank();
    }

    function test_approveTransaction_Revert_If_TransactionAlreadyExecuted() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveAndExecuteTransaction(txId);
        vm.prank(OWNER_3);
        vm.expectRevert(Wallet.TransactionAlreadyExecuted.selector);
        wallet.approveTransaction(txId);
    }

    function test_approveTransaction_Revert_If_TransactionDeclined() public {
        vm.startPrank(OWNER_1);
        uint256 declinedTxId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        bytes memory declineData = _prepareDeclineTransactionData(declinedTxId);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(declineTxId);
        vm.expectRevert(Wallet.TransactionIsDeclined.selector);
        wallet.approveTransaction(declinedTxId);
    }

    function test_approveTransaction_Revert_If_CallerNotOwner() public {
        vm.startPrank(OWNER_1);
        uint256 txId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.approveTransaction(txId);
    }

    function test_approveAndExecuteTransaction() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionApproved(OWNER_2, txId);
        emit IWallet.TransactionExecuted(OWNER_2, txId);
        wallet.approveAndExecuteTransaction(txId);
        IWallet.Transaction memory txState = wallet.getTransaction(txId);
        assertEq(uint8(txState.status), uint8(IWalletTypes.TransactionStatus.Executed));
    }

    function test_approveAndExecuteTransaction_Revert_If_TransactionNotExist() public {
        vm.startPrank(OWNER_1);
        uint256 txCount = wallet.getTransactionCount();
        vm.expectRevert(Wallet.TransactionNotExist.selector);
        wallet.approveAndExecuteTransaction(txCount + 1);
    }

    function test_approveAndExecuteTransaction_Revert_If_TransactionAlreadyApproved() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.expectRevert(Wallet.AlreadyApproved.selector);
        wallet.approveAndExecuteTransaction(txId);
        vm.stopPrank();
    }

    function test_approveAndExecuteTransaction_Revert_If_TransactionAlreadyExecuted() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveAndExecuteTransaction(txId);
        IWallet.Transaction memory txState = wallet.getTransaction(txId);
        assertEq(uint8(txState.status), uint8(IWalletTypes.TransactionStatus.Executed));
        vm.prank(OWNER_3);
        vm.expectRevert(Wallet.TransactionAlreadyExecuted.selector);
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_approveAndExecuteTransaction_Revert_If_TransactionDeclined() public {
        vm.startPrank(OWNER_1);
        uint256 declinedTxId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        bytes memory declineData = _prepareDeclineTransactionData(declinedTxId);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(declineTxId);
        vm.expectRevert(Wallet.TransactionIsDeclined.selector);
        wallet.approveAndExecuteTransaction(declinedTxId);
    }

    function test_approveAndExecuteTransaction_Revert_If_NotEnoughApprovals() public {
        bytes memory payload = _prepareUpdateOwnersData(OWNERS_ARRAY, REQUIRED_APPROVALS + 1);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveAndExecuteTransaction(txId);

        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(Wallet.NotEnoughApprovals.selector);
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_approveAndExecuteTransaction_Revert_If_InternalTransactionFailed() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(this), defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(WalletTest.TestError.selector)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_approveAndExecuteTransaction_Revert_If_CallerNotOwner() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_executeTransaction() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveTransaction(txId);
        vm.prank(OWNER_3);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionExecuted(OWNER_3, txId);
        wallet.executeTransaction(txId);
        IWalletTypes.Transaction memory txState = wallet.getTransaction(txId);
        assertEq(uint8(txState.status), uint8(IWalletTypes.TransactionStatus.Executed));
    }

    function test_executeTransaction_Revert_If_TransactionNotExist() public {
        vm.startPrank(OWNER_1);
        uint256 txCount = wallet.getTransactionCount();
        vm.expectRevert(Wallet.TransactionNotExist.selector);
        wallet.executeTransaction(txCount);
    }

    function test_executeTransaction_Revert_If_TransactionAlreadyExecuted() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveAndExecuteTransaction(txId);
        IWalletTypes.Transaction memory txState = wallet.getTransaction(txId);
        assertEq(uint8(txState.status), uint8(IWalletTypes.TransactionStatus.Executed));
        vm.prank(OWNER_3);
        vm.expectRevert(Wallet.TransactionAlreadyExecuted.selector);
        wallet.executeTransaction(txId);
    }

    function test_executeTransaction_Revert_If_TransactionDeclined() public {
        vm.startPrank(OWNER_1);
        uint256 declinedTxId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        bytes memory declineData = _prepareDeclineTransactionData(declinedTxId);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(declineTxId);
        vm.expectRevert(Wallet.TransactionIsDeclined.selector);
        wallet.executeTransaction(declinedTxId);
    }


    function test_executeTransaction_Revert_If_NotEnoughApprovals() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(Wallet.NotEnoughApprovals.selector);
        wallet.executeTransaction(txId);
    }

    function test_executeTransaction_Revert_If_InternalTransactionFailed() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(this), defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveTransaction(txId);
        vm.prank(OWNER_3);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(WalletTest.TestError.selector)
            )
        );
        wallet.executeTransaction(txId);
    }

    function test_executeTransaction_Revert_If_CallerNotOwner() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(this), defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveTransaction(txId);
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.executeTransaction(txId);
    }

    function test_revokeApproval() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        assertEq(wallet.getApprovalCount(txId), 1);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), true);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.ApprovalRevoked(OWNER_1, txId);
        wallet.revokeApproval(txId);
        assertEq(wallet.getApprovalCount(txId), 0);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), false);
    }

    function test_revokeApproval_Revert_If_TransactionNotExist() public {
        vm.startPrank(OWNER_1);
        uint256 txCount = wallet.getTransactionCount();
        vm.expectRevert(Wallet.TransactionNotExist.selector);
        wallet.revokeApproval(txCount + 1);
    }

    function test_revokeApproval_Revert_If_TransactionAlreadyExecuted() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        wallet.approveAndExecuteTransaction(txId);
        IWallet.Transaction memory txState = wallet.getTransaction(txId);
        assertEq(uint8(txState.status), uint8(IWalletTypes.TransactionStatus.Executed));
        vm.prank(OWNER_1);
        vm.expectRevert(Wallet.TransactionAlreadyExecuted.selector);
        wallet.revokeApproval(txId);
    }

    function test_revokeApproval_Revert_If_TransactionDeclined() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 declinedTxId = (wallet.getTransactionCount() - 1);
        bytes memory declineData = _prepareDeclineTransactionData(declinedTxId);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(declineTxId);
        vm.expectRevert(Wallet.TransactionIsDeclined.selector);
        wallet.revokeApproval(declinedTxId);
    }

    function test_revokeApproval_Revert_If_CallerNotOwner() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(this), defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.revokeApproval(txId);
    }

    function test_declineTransaction() public {
        vm.startPrank(OWNER_1);
        uint256 declinedTxId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        bytes memory declineData = _prepareDeclineTransactionData(declinedTxId);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.TransactionDeclined(declinedTxId);
        wallet.approveAndExecuteTransaction(declineTxId);
        assertEq(uint8(wallet.getTransactionStatus(declinedTxId)), uint8(IWalletTypes.TransactionStatus.Declined));
    }

    function test_declineTransaction_Revert_IfCallerNotOwner() public {
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.declineTransaction(0);
    }

    function test_declineTransaction_Revert_IfTransactionNotExist() public {
        vm.startPrank(OWNER_1);
        bytes memory declineData = _prepareDeclineTransactionData(wallet.getTransactionCount() + 1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.TransactionNotExist.selector)
            )
        );
        wallet.approveAndExecuteTransaction(declineTxId);
    }

    function test_declineTransaction_Revert_IfTransactionAlreadyExecuted() public {
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(wallet.getTransactionCount() - 1);
        vm.stopPrank();
        vm.startPrank(OWNER_1);
        bytes memory declineData = _prepareDeclineTransactionData(wallet.getTransactionCount() - 1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.TransactionAlreadyExecuted.selector)
            )
        );
        wallet.approveAndExecuteTransaction(declineTxId);
    }

    function test_declineTransaction_Revert_IfTransactionAlreadyDeclined() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 declinedTxId = wallet.getTransactionCount() - 1;
        bytes memory declineData = _prepareDeclineTransactionData(wallet.getTransactionCount() - 1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, declineData);
        uint256 declineTxId = wallet.getTransactionCount() - 1;
        vm.stopPrank();
        vm.startPrank(OWNER_2);
        wallet.approveAndExecuteTransaction(declineTxId);
        vm.stopPrank();
        vm.startPrank(address(wallet));
        vm.expectRevert(Wallet.TransactionIsDeclined.selector);
        wallet.declineTransaction(declinedTxId);
    }

    function test_updateOwners() public {
        _compareArrays(OWNERS_ARRAY, wallet.getOwners());
        assertEq(REQUIRED_APPROVALS, wallet.getRequiredApprovals());
        bytes memory payload = _prepareUpdateOwnersData(NEW_OWNERS_ARRAY, REQUIRED_APPROVALS + 1);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IWallet.OwnersUpdated(NEW_OWNERS_ARRAY, REQUIRED_APPROVALS + 1);
        wallet.approveAndExecuteTransaction(txId);
        _compareArrays(NEW_OWNERS_ARRAY, wallet.getOwners());
        assertEq(REQUIRED_APPROVALS + 1, wallet.getRequiredApprovals());
    }

    function test_updateOwners_Revert_If_InvalidOwnersArray() public {
        bytes memory payload = _prepareUpdateOwnersData(EMPTY_ARRAY, REQUIRED_APPROVALS);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.InvalidOwnersArray.selector)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_ZeroRequiredApprovals() public {
        bytes memory payload = _prepareUpdateOwnersData(NEW_OWNERS_ARRAY, 0);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.InvalidRequiredApprovals.selector)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_InvalidRequiredApprovals() public {
        uint256 invalidApprovalsNumber = NEW_OWNERS_ARRAY.length + 1;
        bytes memory payload = _prepareUpdateOwnersData(NEW_OWNERS_ARRAY, uint8(invalidApprovalsNumber));
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.InvalidRequiredApprovals.selector)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_ZeroOwnerAddress() public {
        bytes memory payload = _prepareUpdateOwnersData(ZERO_ADDRESS_OWNERS_ARRAY, REQUIRED_APPROVALS);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.ZeroOwnerAddress.selector, 1)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_DuplicatedOwnerAddress() public {
        bytes memory payload = _prepareUpdateOwnersData(DUPLICATE_OWNERS_ARRAY, REQUIRED_APPROVALS);
        vm.prank(OWNER_1);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.DuplicatedOwnerAddress.selector, OWNER_1)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_WalletHasPendingTransactions() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        bytes memory payload = _prepareUpdateOwnersData(NEW_OWNERS_ARRAY, REQUIRED_APPROVALS);
        wallet.submitAndApproveTransaction(address(wallet), defaultTx.value, payload);
        uint256 txId = (wallet.getTransactionCount() - 1);
        vm.stopPrank();
        vm.prank(OWNER_2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Wallet.InternalTransactionFailed.selector,
                abi.encodeWithSelector(Wallet.WalletHasPendingTransactions.selector)
            )
        );
        wallet.approveAndExecuteTransaction(txId);
    }

    function test_updateOwners_Revert_If_CallerNotMultisig() public {
        vm.prank(ATTACKER);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.updateOwners(NEW_OWNERS_ARRAY, REQUIRED_APPROVALS);

        vm.prank(OWNER_1);
        vm.expectRevert(Wallet.UnauthorizedCaller.selector);
        wallet.updateOwners(NEW_OWNERS_ARRAY, REQUIRED_APPROVALS);
    }

    function test_getApprovalCount() public {
        vm.startPrank(OWNER_1);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        assertEq(wallet.getApprovalCount(txId), 0);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 1);
        vm.stopPrank();
        vm.prank(OWNER_2);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 2);
        vm.prank(OWNER_3);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalCount(txId), 3);
    }

    function test_getApprovalStatus() public {
        vm.startPrank(OWNER_1);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), false);
        assertEq(wallet.getApprovalStatus(txId, OWNER_2), false);
        assertEq(wallet.getApprovalStatus(txId, OWNER_3), false);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalStatus(txId, OWNER_1), true);
        vm.stopPrank();
        vm.prank(OWNER_2);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalStatus(txId, OWNER_2), true);
        vm.prank(OWNER_3);
        wallet.approveTransaction(txId);
        assertEq(wallet.getApprovalStatus(txId, OWNER_3), true);
    }

    function test_getTransaction() public {
        vm.startPrank(OWNER_1);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        IWalletTypes.Transaction memory submittedTx = wallet.getTransaction(txId);
        _compareTransactions(submittedTx, defaultTx);
        txId = wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        submittedTx = wallet.getTransaction(txId);
        _compareTransactions(submittedTx, defaultTx);
    }

    function test_getTransaction_Revert_IfTransactionNotExist() public {
        uint256 txCount = wallet.getTransactionCount();
        vm.expectRevert(Wallet.TransactionNotExist.selector);
        wallet.getTransaction(txCount);
    }

    function test_getTransactions() public {
        vm.startPrank(OWNER_1);
        for (uint i = 0; i < 5; i++) {
            wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        }

        // Case 1: txId >= _transactions.length
        IWalletTypes.Transaction[] memory transactions = wallet.getTransactions(5, 1);
        assertEq(transactions.length, 0);

        // Case 2: limit == 0
        transactions = wallet.getTransactions(0, 0);
        assertEq(transactions.length, 0);

        // Case 3: Remaining length > limit
        transactions = wallet.getTransactions(2, 2); // Should only return 2 transactions starting from index 2
        assertEq(transactions.length, 2);
        assertEq(transactions[0].to, defaultTx.to);
        assertEq(transactions[1].to, defaultTx.to);

        // Case 4: Remaining length < limit
        transactions = wallet.getTransactions(3, 10); // Only 2 transactions available starting from index 3
        assertEq(transactions.length, 2);
        assertEq(transactions[0].to, defaultTx.to);
        assertEq(transactions[1].to, defaultTx.to);
    }

    function test_getTransactionStatus() public {
        vm.startPrank(OWNER_1);
        wallet.submitAndApproveTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        uint256 txId = (wallet.getTransactionCount() - 1);
        IWalletTypes.Transaction memory submittedTx = wallet.getTransaction(txId);
        assertEq(uint8(submittedTx.status), uint8(IWalletTypes.TransactionStatus.Pending));
    }

    function test_isOwner() public {
        assertEq(wallet.isOwner(OWNER_1), true);
        assertEq(wallet.isOwner(ATTACKER), false);
    }

    function test_getPendingTransactionsCount() public {
        assertEq(wallet.getPendingTransactionsCount(), 0);
        vm.prank(OWNER_1);
        wallet.submitTransaction(defaultTx.to, defaultTx.value, defaultTx.data);
        assertEq(wallet.getPendingTransactionsCount(), 1);
    }

    function test_safeCastToUint64_Revert_If_MathOverflow() public {
        vm.expectRevert(Wallet.MathOverflow.selector);
        wallet.safeCastToUint64(type(uint256).max);
    }

    function _compareArrays(address[] memory firstArray, address[] memory secondArray) internal {
        require(firstArray.length == secondArray.length, "Arrays length mismatch");
        for (uint256 i = 0; i < firstArray.length; i++) {
            assertEq(firstArray[i], secondArray[i]);
        }
    }

    function _compareTransactions(IWallet.Transaction memory firstTransaction, IWallet.Transaction memory secondTransaction) internal {
        assertEq(firstTransaction.to, secondTransaction.to);
        assertEq(uint8(firstTransaction.status), uint8(secondTransaction.status));
        assertEq(firstTransaction.value, secondTransaction.value);
        assertEq(firstTransaction.data, secondTransaction.data);
    }

    function _prepareUpdateOwnersData(address[] memory newOwners, uint8 newRequiredApprovals) internal pure returns (bytes memory) {
        return abi.encodeCall(IWallet.updateOwners, (newOwners, newRequiredApprovals));
    }

    function _prepareDeclineTransactionData(uint256 txId) internal pure returns (bytes memory) {
        return abi.encodeCall(IWallet.declineTransaction, txId);
    }

    // To revert low level calls from the wallet for testing
    receive() external payable {
        revert TestError();
    }
    fallback() external payable {
        revert TestError();
    }
}