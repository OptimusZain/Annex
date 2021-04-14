pragma solidity ^0.5.16;

import "./ComptrollerInterface.sol";

contract VAIUnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public vaiControllerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingVAIControllerImplementation;
}

contract VAIControllerStorage is VAIUnitrollerAdminStorage {
    ComptrollerInterface public comptroller;

    struct AnnexVAIState {
        /// @notice The last updated annexVAIMintIndex
        uint224 index;

        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice The Annex VAI state
    AnnexVAIState public annexVAIState;

    /// @notice The Annex VAI state initialized
    bool public isAnnexVAIInitialized;

    /// @notice The Annex VAI minter index as of the last time they accrued ANX
    mapping(address => uint) public annexVAIMinterIndex;
}
