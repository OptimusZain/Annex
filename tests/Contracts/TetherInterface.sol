pragma solidity ^0.6.12;

import "../../contracts/EIP20Interface.sol";

contract TetherInterface is EIP20Interface {
    function setParams(uint newBasisPoints, uint newMaxFee) external;
}
