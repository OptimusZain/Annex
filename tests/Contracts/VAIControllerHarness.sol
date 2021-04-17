pragma solidity ^0.5.16;

import "../../contracts/VAIController.sol";

contract VAIControllerHarness is VAIController {
    address vaiAddress;
    uint public blockNumber;

    constructor() VAIController() public {}

    function setAnnexVAIState(uint224 index, uint32 blockNumber_) public {
        annexVAIState.index = index;
        annexVAIState.block = blockNumber_;
    }

    function setVAIAddress(address vaiAddress_) public {
        vaiAddress = vaiAddress_;
    }

    function getVAIAddress() public view returns (address) {
        return vaiAddress;
    }

    function setAnnexVAIMinterIndex(address vaiMinter, uint index) public {
        annexVAIMinterIndex[vaiMinter] = index;
    }

    function harnessUpdateAnnexVAIMintIndex() public {
        updateAnnexVAIMintIndex();
    }

    function harnessCalcDistributeVAIMinterAnnex(address vaiMinter) public {
        calcDistributeVAIMinterAnnex(vaiMinter);
    }

    function harnessFastForward(uint blocks) public returns (uint) {
        blockNumber += blocks;
        return blockNumber;
    }

    function setBlockNumber(uint number) public {
        blockNumber = number;
    }

    function getBlockNumber() public view returns (uint) {
        return blockNumber;
    }
}
