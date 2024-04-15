// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWallet } from "./interfaces/IWallet.sol";

/// @title Multi-Signature Wallet Contract
/// @notice Implements transaction handling with multi-signature validation
/// @author https://github.com/pastrn
contract Wallet is IWallet {

    /// @notice Count of pending transactions requiring approvals or declines
    uint64 private _pendingTransactions;

    /// @notice Number of approvals required for executing any transaction
    uint8 private _requiredApprovals;

    /// @notice List of owner addresses authorized to submit, approve and execute transactions
    address[] private _owners;

    /// @notice Array storing all transaction records
    Transaction[] private _transactions;

    /// @notice Mapping to check if an address is an owner of the wallet
    mapping(address => bool) private _isOwner;

    /// @notice Mapping of transaction IDs to their respective approval counts
    mapping(uint256 => uint256) private _approvalCount;

    /// @notice Mapping of transaction IDs to owner approval statuses
    mapping(uint256 => mapping(address => bool)) private _approvalStatus;

    /// @dev Thrown if a deposit of zero value is attempted
    error ZeroDepositValue();

    /// @dev Thrown if an unauthorized caller tries to perform an action
    error UnauthorizedCaller();

    /// @dev Thrown if a transaction is attempted to submit with a zero destination address
    error ZeroDestinationAddress();

    /// @dev Thrown if a non-existent transaction is referenced
    error TransactionNotExist();

    /// @dev Thrown if an action is attempted on an already executed transaction
    error TransactionAlreadyExecuted();

    /// @dev Thrown if an action is attempted on a declined transaction
    error TransactionIsDeclined();

    /// @dev Thrown if a transaction has already been approved by the caller
    error AlreadyApproved();

    /// @dev Thrown if an empty owner array is provided
    error InvalidOwnersArray();

    /// @dev Thrown if a zero address is provided as an owner inside the array
    error ZeroOwnerAddress(uint256 index);

    /// @dev Thrown if a duplicated owner address is added to the array
    error DuplicatedOwnerAddress(address owner);

    /// @dev Thrown if an invalid number of required approvals is set
    error InvalidRequiredApprovals();

    /// @dev Thrown if the wallet has pending transactions when an update or other critical action is attempted
    error WalletHasPendingTransactions();

    /// @dev Thrown if there are not enough approvals to execute a transaction
    error NotEnoughApprovals();

    /// @dev Thrown if a transaction fails to execute
    error InternalTransactionFailed(bytes data);

    /// @dev Thrown in case of arithmetic overflow
    error MathOverflow();

    /// @notice Modifier that allows only wallet owners to call a function
    /// @dev Reverts with UnauthorizedCaller if the sender is not recognized as an owner
    modifier onlyOwner() {
        if (!_isOwner[msg.sender]) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /// @notice Modifier that allows only the contract itself to call a function
    /// @dev Reverts with UnauthorizedCaller if the function is called from any address other than the contract itself
    modifier onlySelfCall() {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /// @notice Initializes a new Wallet contract with specified owners and required approvals count
    /// @dev Calls the internal _updateOwners function to set the initial state of owners and their approval requirements
    /// @param newOwners Array of addresses to be set as owners of the wallet
    /// @param newRequiredApprovals Minimum number of approvals required for executing transactions
    constructor(address[] memory newOwners, uint8 newRequiredApprovals) {
        _updateOwners(newOwners, newRequiredApprovals);
    }


    /// @notice Allows deposit of Ether into the wallet
    /// @dev Reverts if the deposited value is zero
    function deposit() external payable {
        if (msg.value == 0) {
            revert ZeroDepositValue();
        }
        emit FundsDeposited(msg.sender, msg.value);
    }

    /// @notice Submits a new transaction for later approval and execution
    /// @dev Only callable by an owner, returns a transaction ID
    /// @param to The recipient address of the transaction
    /// @param value The amount of Ether (in wei) to send
    /// @param data Additional transaction data
    /// @return txId The identifier of the submitted transaction
    function submitTransaction(
        address to,
        uint64 value,
        bytes calldata data
    ) external onlyOwner returns (uint64 txId) {
        txId = _submitTransaction(to, value, data);
    }

    /// @notice Submits and immediately approves a transaction
    /// @dev Only callable by an owner
    /// @param to The recipient address of the transaction
    /// @param value The amount of Ether (in wei) to send
    /// @param data Additional transaction data
    function submitAndApproveTransaction(
        address to,
        uint64 value,
        bytes calldata data
    ) external onlyOwner {
        uint64 txId = _submitTransaction(to, value, data);
        _approveTransaction(uint256(txId));
    }

    /// @notice Approves a transaction pending execution
    /// @dev Only callable by an owner
    /// @param txId The identifier of the transaction to approve
    function approveTransaction(uint256 txId) external onlyOwner {
        _approveTransaction(txId);
    }

    /// @notice Approves and executes a transaction if enough approvals are obtained
    /// @dev Only callable by an owner
    /// @param txId The identifier of the transaction to approve and execute
    function approveAndExecuteTransaction(uint256 txId) external onlyOwner {
        _approveTransaction(txId);
        _executeTransaction(txId);
    }

    /// @notice Executes a transaction that has met the required number of approvals
    /// @dev Only callable by an owner
    /// @param txId The identifier of the transaction to execute
    function executeTransaction(uint256 txId) external onlyOwner {
        _executeTransaction(txId);
    }

    /// @notice Revokes approval for a transaction
    /// @dev Only callable by an owner
    /// @param txId The identifier of the transaction for which to revoke approval
    function revokeApproval(uint256 txId) external onlyOwner {
        _revokeApproval(txId);
    }

    /// @notice Declines a transaction, preventing its execution
    /// @dev Only callable internally by the contract
    /// @param txId The identifier of the transaction to decline
    function declineTransaction(uint256 txId) external onlySelfCall {
        _declineTransaction(txId);
    }

    /// @notice Updates the list of owners and the number of required approvals
    /// @dev Only callable internally by the contract
    /// @param newOwners The new list of owners
    /// @param newRequiredApprovals The new number of required approvals
    function updateOwners(address[] memory newOwners, uint8 newRequiredApprovals) external onlySelfCall {
        _updateOwners(newOwners, newRequiredApprovals);
    }


    /// @notice Retrieves the count of approvals for a specific transaction
    /// @param txId The identifier of the transaction
    /// @return The number of approvals the transaction has received
    function getApprovalCount(uint256 txId) external view returns (uint256) {
        return _approvalCount[txId];
    }

    /// @notice Checks if a specific transaction has been approved by a given owner
    /// @param txId The identifier of the transaction
    /// @param owner The address of the owner to check for approval
    /// @return True if the transaction is approved by the owner, false otherwise
    function getApprovalStatus(uint256 txId, address owner) external view returns (bool) {
        return _approvalStatus[txId][owner];
    }

    /// @notice Retrieves a transaction by its identifier
    /// @param txId The identifier of the transaction to retrieve
    /// @return The transaction data
    /// @dev Reverts if the transaction does not exist
    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        if (txId >= _transactions.length) {
            revert TransactionNotExist();
        }
        return _transactions[txId];
    }

    /// @notice Retrieves a list of transactions starting from a specified index
    /// @param txId The starting index for transaction retrieval
    /// @param limit The maximum number of transactions to return
    /// @return txs An array of transactions
    function getTransactions(uint256 txId, uint256 limit) external view returns (Transaction[] memory txs) {
        uint256 len = _transactions.length;
        if (len <= txId || limit == 0) {
            txs = new Transaction[](0);
        } else {
            len -= txId;
            if (len > limit) {
                len = limit;
            }
            txs = new Transaction[](len);
            for (uint256 i = 0; i < len; i++) {
                txs[i] = _transactions[txId];
                txId++;
            }
        }
    }

    /// @notice Retrieves the status of a transaction by its identifier
    /// @param txId The identifier of the transaction
    /// @return status The status of the transaction
    function getTransactionStatus(uint256 txId) external view returns (TransactionStatus status) {
        return _transactions[txId].status;
    }

    /// @notice Retrieves a list of all wallet owners
    /// @return An array of owner addresses
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    /// @notice Checks if a specific address is an owner of the wallet
    /// @param account The address to verify
    /// @return True if the address is an owner, false otherwise
    function isOwner(address account) external view returns (bool) {
        return _isOwner[account];
    }

    /// @notice Retrieves the number of approvals required for a transaction to be executed
    /// @return The required number of approvals
    function getRequiredApprovals() external view returns (uint256) {
        return _requiredApprovals;
    }

    /// @notice Retrieves the total number of transactions that have been submitted to the wallet
    /// @return The total number of transactions
    function getTransactionCount() external view returns (uint256) {
        return _transactions.length;
    }

    /// @notice Retrieves the number of transactions that are pending approval, decline or execution
    /// @return The total count of pending transactions
    function getPendingTransactionsCount() external view returns (uint256) {
        return _pendingTransactions;
    }

    /// @notice Safely casts a uint256 to a uint64
    /// @dev Reverts with MathOverflow if the number exceeds uint64's maximum value
    /// @param number The number to cast
    /// @return The number casted to uint64
    function safeCastToUint64(uint256 number) public pure returns (uint64) {
        if (number > type(uint64).max) {
            revert MathOverflow();
        }
        return uint64(number);
    }

    /// @notice Submits a transaction to the wallet
    /// @dev Adds a new transaction to the wallet and emits the TransactionSubmitted event
    /// @param to The recipient address of the transaction
    /// @param value The amount of Ether (in wei) to be transferred
    /// @param data Additional data to be sent with the transaction
    /// @return txId The unique identifier of the submitted transaction
    function _submitTransaction(
        address to,
        uint64 value,
        bytes calldata data
    ) internal returns (uint64 txId) {
        _transactions.push(
            Transaction({
                to: to,
                id: 0, // Temporary ID, will be updated below
                value: value,
                executionDate: 0,
                status: TransactionStatus.Pending,
                data: data
            })
        );
        txId = safeCastToUint64(_transactions.length - 1);
        _transactions[uint256(txId)].id = txId;
        _pendingTransactions++;
        emit TransactionSubmitted(msg.sender, txId);
    }

    /// @notice Approves a transaction
    /// @dev Marks a transaction as approved if it has not been executed or declined and updates the approval status
    /// @param txId The identifier of the transaction to approve
    function _approveTransaction(uint256 txId) internal {
        if (txId >= _transactions.length) {
            revert TransactionNotExist();
        }
        if (_approvalStatus[txId][msg.sender]) {
            revert AlreadyApproved();
        }
        Transaction memory transaction = _transactions[txId];
        if (transaction.status == TransactionStatus.Executed) {
            revert TransactionAlreadyExecuted();
        }
        if (transaction.status == TransactionStatus.Declined) {
            revert TransactionIsDeclined();
        }
        _approvalCount[txId]++;
        _approvalStatus[txId][msg.sender] = true;
        emit TransactionApproved(msg.sender, txId);
    }

    /// @notice Executes a transaction
    /// @dev Executes a transaction if it has enough approvals and has not been executed or declined
    /// @param txId The identifier of the transaction to execute
    function _executeTransaction(uint256 txId) internal {
        if (txId >= _transactions.length) {
            revert TransactionNotExist();
        }
        Transaction storage transaction = _transactions[txId];
        if (transaction.status == TransactionStatus.Executed) {
            revert TransactionAlreadyExecuted();
        }
        if (transaction.status == TransactionStatus.Declined) {
            revert TransactionIsDeclined();
        }
        if (_approvalCount[txId] < _requiredApprovals) {
            revert NotEnoughApprovals();
        }
        transaction.status = TransactionStatus.Executed;
        _pendingTransactions--;
        emit TransactionExecuted(msg.sender, txId);
        (bool success, bytes memory data) = transaction.to.call{value: transaction.value}(transaction.data);
        if (!success) {
            revert InternalTransactionFailed(data);
        }
    }

    /// @notice Revokes approval for a transaction
    /// @dev Decreases the approval count for a transaction and updates the approval status
    /// @param txId The identifier of the transaction for which to revoke approval
    function _revokeApproval(uint256 txId) internal {
        if (txId >= _transactions.length) {
            revert TransactionNotExist();
        }
        Transaction storage transaction = _transactions[txId];
        if (transaction.status == TransactionStatus.Executed) {
            revert TransactionAlreadyExecuted();
        }
        if (transaction.status == TransactionStatus.Declined) {
            revert TransactionIsDeclined();
        }
        _approvalCount[txId]--;
        _approvalStatus[txId][msg.sender] = false;
        emit ApprovalRevoked(msg.sender, txId);
    }

    /// @notice Declines a transaction, preventing further approvals and execution
    /// @dev Marks a transaction as declined and decreases the pending transaction count
    /// @param txId The identifier of the transaction to decline
    function _declineTransaction(uint256 txId) internal {
        if (txId >= _transactions.length) {
            revert TransactionNotExist();
        }
        Transaction storage transaction = _transactions[txId];
        if (transaction.status == TransactionStatus.Executed) {
            revert TransactionAlreadyExecuted();
        }
        if (transaction.status == TransactionStatus.Declined) {
            revert TransactionIsDeclined();
        }
        transaction.status = TransactionStatus.Declined;
        _pendingTransactions--;
        emit TransactionDeclined(txId);
    }

    /// @notice Updates the list of wallet owners and the required approvals
    /// @dev Reconfigures the owner list and required approvals for transactions, ensuring no pending transactions exist
    /// @param newOwners The new list of wallet owners
    /// @param newRequiredApprovals The new number of required approvals for executing transactions
    function _updateOwners(address[] memory newOwners, uint8 newRequiredApprovals) internal {
        if (newOwners.length == 0) {
            revert InvalidOwnersArray();
        }
        if (newRequiredApprovals == 0) {
            revert InvalidRequiredApprovals();
        }
        if (newRequiredApprovals > newOwners.length) {
            revert InvalidRequiredApprovals();
        }
        if (_pendingTransactions != 0) {
            revert WalletHasPendingTransactions();
        }
        for (uint256 i = 0; i < _owners.length; i++) {
            _isOwner[_owners[i]] = false;
        }
        for (uint256 i = 0; i < newOwners.length; i++) {
            address owner = newOwners[i];
            if (owner == address(0)) {
                revert ZeroOwnerAddress(i);
            }
            if (_isOwner[owner]) {
                revert DuplicatedOwnerAddress(owner);
            }
            _isOwner[owner] = true;
        }
        _owners = newOwners;
        _requiredApprovals = newRequiredApprovals;
        emit OwnersUpdated(newOwners, newRequiredApprovals);
    }
}
