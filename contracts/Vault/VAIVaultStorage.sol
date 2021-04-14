pragma solidity ^0.5.16;
import "./SafeMath.sol";
import "./IBEP20.sol";

contract VAIVaultAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of VAI Vault
    */
    address public vaiVaultImplementation;

    /**
    * @notice Pending brains of VAI Vault
    */
    address public pendingVAIVaultImplementation;
}

contract VAIVaultStorage is VAIVaultAdminStorage {
    /// @notice The ANX TOKEN!
    IBEP20 public anx;

    /// @notice The VAI TOKEN!
    IBEP20 public vai;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice ANX balance of vault
    uint256 public anxBalance;

    /// @notice Accumulated ANX per share
    uint256 public accANXPerShare;

    //// pending rewards awaiting anyone to update
    uint256 public pendingRewards;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;
}
