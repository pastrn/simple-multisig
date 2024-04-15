// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/// @title Interface for defining wallet transaction types for a multi-signature wallet
/// @dev This interface defines the data structures and status types used by the wallet, including a Transaction struct for multi-signature transactions and a TransactionStatus enum to indicate the current status of each transaction.
interface IWalletTypes {

    /// @title Enumeration of transaction statuses
    /// @dev Enumerates the different states a transaction can have in a multi-signature wallet
    enum TransactionStatus {
        Pending,    // Transaction has been submitted and is awaiting further approvals
        Executed,   // Transaction has received all necessary approvals and has been executed
        Declined    // Transaction has been declined and can not be executed anymore
    }

    /// @title Transaction structure for a multi-signature wallet
    /// @dev This struct stores details about each transaction that requires multi-signature approval.
    struct Transaction {
        /// @notice The destination address of the transaction
        /// @dev 20-byte Ethereum address to which the transaction will be sent
        address to;

        /// @notice Identifier for the transaction
        /// @dev Uses a 64-bit unsigned integer to uniquely identify the transaction
        uint64 id;

        /// @notice Amount of Ether (in wei) involved in the transaction
        /// @dev 64-bit unsigned integer representing the transaction value in wei
        uint64 value;

        /// @notice Execution date of the transaction as a timestamp
        /// @dev Uses a 128-bit unsigned integer to store the Unix timestamp of the transaction execution date
        uint128 executionDate;

        /// @notice Current status of the transaction
        /// @dev Enumerated status indicating whether the transaction is pending, executed, or declined
        TransactionStatus status;

        /// @notice Payload of the transaction
        /// @dev Dynamically-sized byte array containing the transaction data payload
        bytes data;
    }
}

/// @title Interface for wallet functionalities in a multi-signature wallet system
/// @dev Extends IWalletTypes to include the management and interaction of wallet transactions
interface IWallet is IWalletTypes {

    /// @notice Emitted when funds are deposited into the wallet
    event FundsDeposited(address indexed sender, uint256 indexed amount);

    /// @notice Emitted when a new transaction is submitted
    event TransactionSubmitted(address indexed owner, uint256 indexed txId);

    /// @notice Emitted when a transaction is approved by an owner
    event TransactionApproved(address indexed owner, uint256 indexed txId);

    /// @notice Emitted when an approval for a transaction is revoked by an owner
    event ApprovalRevoked(address indexed owner, uint256 indexed txId);

    /// @notice Emitted when a transaction is executed
    event TransactionExecuted(address indexed owner, uint256 indexed txId);

    /// @notice Emitted when a transaction is declined
    event TransactionDeclined(uint256 indexed txId);

    /// @notice Emitted when the list of owners or their required number of approvals is updated
    event OwnersUpdated(address[] newOwners, uint8 newRequiredApprovals);

    /// @notice Submits a transaction to the wallet
    /// @param to The destination address of the transaction
    /// @param value The amount of Ether (in wei) involved in the transaction
    /// @param data The data payload of the transaction
    /// @return txId The unique identifier for the newly created transaction
    function submitTransaction(address to, uint64 value, bytes calldata data) external returns (uint64);

    /// @notice Submits and immediately approves a transaction
    /// @param to The destination address of the transaction
    /// @param value The amount of Ether (in wei) involved in the transaction
    /// @param data The data payload of the transaction
    function submitAndApproveTransaction(address to, uint64 value, bytes calldata data) external;

    /// @notice Approves a pending transaction
    /// @param txId The identifier of the transaction to approve
    function approveTransaction(uint256 txId) external;

    /// @notice Approves and executes a transaction if the required number of approvals is met
    /// @param txId The identifier of the transaction to approve and execute
    function approveAndExecuteTransaction(uint256 txId) external;

    /// @notice Executes a transaction if the required number of approvals is met
    /// @param txId The identifier of the transaction to execute
    function executeTransaction(uint256 txId) external;

    /// @notice Revokes an approval for a transaction
    /// @param txId The identifier of the transaction for which to revoke an approval
    function revokeApproval(uint256 txId) external;

    /// @notice Declines the transaction
    /// @param txId The identifier of the transaction for which to make a decline
    function declineTransaction(uint256 txId) external;

    /// @notice Updates the list of owners and the number of required approvals
    /// @param newOwners The new list of owners
    /// @param newRequiredApprovals The new threshold of required approvals
    function updateOwners(address[] memory newOwners, uint8 newRequiredApprovals) external;

    /// @notice Returns the number of approvals for a transaction
    /// @param txId The identifier of the transaction
    /// @return The number of approvals
    function getApprovalCount(uint256 txId) external view returns (uint256);

    /// @notice Checks if a transaction is approved by a specific owner
    /// @param txId The identifier of the transaction
    /// @param owner The address of the owner to check for approval status
    /// @return True if the transaction is approved by the owner, otherwise false
    function getApprovalStatus(uint256 txId, address owner) external view returns (bool);

    /// @notice Retrieves a transaction by its identifier
    /// @param txId The identifier of the transaction to retrieve
    /// @return The transaction data
    function getTransaction(uint256 txId) external view returns (Transaction memory);

    /// @notice Retrieves a list of transactions starting from a specific index
    /// @param txId The starting index for the list of transactions
    /// @param limit The maximum number of transactions to return
    /// @return An array of transactions
    function getTransactions(uint256 txId, uint256 limit) external view returns (Transaction[] memory);

    /// @notice Returns a list of all owners
    /// @return An array of owner addresses
    function getOwners() external view returns (address[] memory);

    /// @notice Checks if a specific address is an owner
    /// @param account The address to check
    /// @return True if the address is an owner, otherwise false
    function isOwner(address account) external view returns (bool);

    /// @notice Returns the number of approvals required to execute a transaction
    /// @return The required number of approvals
    function getRequiredApprovals() external view returns (uint256);

    /// @notice Returns the total number of transactions that have been submitted
    /// @return The total number of transactions
    function getTransactionCount() external view returns (uint256);
}
