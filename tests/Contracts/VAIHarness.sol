pragma solidity ^0.6.12;

import "../../contracts/VAI/VAI.sol";

contract VAIHarness is VAI {
    uint blockNumber = 100000;

    constructor(uint chainId) VAI(chainId) public {}

    function harnessFastForward(uint blocks) public {
        blockNumber += blocks;
    }

    function harnessSetTotalSupply(uint _totalSupply) public {
        totalSupply = _totalSupply;
    }

    function harnessIncrementTotalSupply(uint addtlSupply_) public {
        totalSupply = totalSupply + addtlSupply_;
    }

    function harnessSetBalanceOf(address account, uint _amount) public {
        balanceOf[account] = _amount;
    }

}
