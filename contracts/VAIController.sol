pragma solidity ^0.5.16;

import "./AToken.sol"; import "./PriceOracle.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./VAIControllerStorage.sol";
import "./VAIUnitroller.sol";
import "./VAI/VAI.sol";

interface ComptrollerLensInterface {
    function protocolPaused() external view returns (bool);
    function mintedVAIs(address account) external view returns (uint);
    function vaiMintRate() external view returns (uint);
    function annexVAIRate() external view returns (uint);
    function annexAccrued(address account) external view returns(uint);
    function getAssetsIn(address account) external view returns (AToken[] memory);
    function oracle() external view returns (PriceOracle);

    function distributeVAIMinterAnnex(address vaiMinter, bool distributeAll) external;
}

/**
 * @title Annex's VAI Comptroller Contract
 * @author Annex
 */
contract VAIController is VAIControllerStorage, VAIControllerErrorReporter, Exponential {

    /// @notice Emitted when Comptroller is changed
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when VAI is minted
     */
    event MintVAI(address minter, uint mintVAIAmount);

    /**
     * @notice Event emitted when VAI is repaid
     */
    event RepayVAI(address repayer, uint repayVAIAmount);

    /// @notice The initial Annex index for a market
    uint224 public constant annexInitialIndex = 1e36;

    /*** Main Actions ***/

    function mintVAI(uint mintVAIAmount) external returns (uint) {
        if(address(comptroller) != address(0)) {
            require(!ComptrollerLensInterface(address(comptroller)).protocolPaused(), "protocol is paused");

            address minter = msg.sender;

            // Keep the flywheel moving
            updateAnnexVAIMintIndex();
            ComptrollerLensInterface(address(comptroller)).distributeVAIMinterAnnex(minter, false);

            uint oErr;
            MathError mErr;
            uint accountMintVAINew;
            uint accountMintableVAI;

            (oErr, accountMintableVAI) = getMintableVAI(minter);
            if (oErr != uint(Error.NO_ERROR)) {
                return uint(Error.REJECTION);
            }

            // check that user have sufficient mintableVAI balance
            if (mintVAIAmount > accountMintableVAI) {
                return fail(Error.REJECTION, FailureInfo.VAI_MINT_REJECTION);
            }

            (mErr, accountMintVAINew) = addUInt(ComptrollerLensInterface(address(comptroller)).mintedVAIs(minter), mintVAIAmount);
            require(mErr == MathError.NO_ERROR, "VAI_MINT_AMOUNT_CALCULATION_FAILED");
            uint error = comptroller.setMintedVAIOf(minter, accountMintVAINew);
            if (error != 0 ) {
                return error;
            }

            VAI(getVAIAddress()).mint(minter, mintVAIAmount);
            emit MintVAI(minter, mintVAIAmount);

            return uint(Error.NO_ERROR);
        }
    }

    /**
     * @notice Repay VAI
     */
    function repayVAI(uint repayVAIAmount) external returns (uint) {
        if(address(comptroller) != address(0)) {
            require(!ComptrollerLensInterface(address(comptroller)).protocolPaused(), "protocol is paused");

            address repayer = msg.sender;

            updateAnnexVAIMintIndex();
            ComptrollerLensInterface(address(comptroller)).distributeVAIMinterAnnex(repayer, false);

            uint actualBurnAmount;

            uint vaiBalance = ComptrollerLensInterface(address(comptroller)).mintedVAIs(repayer);

            if(vaiBalance > repayVAIAmount) {
                actualBurnAmount = repayVAIAmount;
            } else {
                actualBurnAmount = vaiBalance;
            }

            uint error = comptroller.setMintedVAIOf(repayer, vaiBalance - actualBurnAmount);
            if (error != 0) {
                return error;
            }

            VAI(getVAIAddress()).burn(repayer, actualBurnAmount);
            emit RepayVAI(repayer, actualBurnAmount);

            return uint(Error.NO_ERROR);
        }
    }

    /**
     * @notice Initialize the AnnexVAIState
     */
    function _initializeAnnexVAIState(uint blockNumber) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        if (isAnnexVAIInitialized == false) {
            isAnnexVAIInitialized = true;
            uint vaiBlockNumber = blockNumber == 0 ? getBlockNumber() : blockNumber;
            annexVAIState = AnnexVAIState({
                index: annexInitialIndex,
                block: safe32(vaiBlockNumber, "block number overflows")
            });
        }
    }

    /**
     * @notice Accrue ANX to by updating the VAI minter index
     */
    function updateAnnexVAIMintIndex() public returns (uint) {
        uint vaiMinterSpeed = ComptrollerLensInterface(address(comptroller)).annexVAIRate();
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(annexVAIState.block));
        if (deltaBlocks > 0 && vaiMinterSpeed > 0) {
            uint vaiAmount = VAI(getVAIAddress()).totalSupply();
            uint annexAccrued = mul_(deltaBlocks, vaiMinterSpeed);
            Double memory ratio = vaiAmount > 0 ? fraction(annexAccrued, vaiAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: annexVAIState.index}), ratio);
            annexVAIState = AnnexVAIState({
                index: safe224(index.mantissa, "new index overflows"),
                block: safe32(blockNumber, "block number overflows")
            });
        } else if (deltaBlocks > 0) {
            annexVAIState.block = safe32(blockNumber, "block number overflows");
        }
    }

    /**
     * @notice Calculate ANX accrued by a VAI minter
     * @param vaiMinter The address of the VAI minter to distribute ANX to
     */
    function calcDistributeVAIMinterAnnex(address vaiMinter) public returns(uint, uint, uint, uint) {
        // Check caller is comptroller
        if (msg.sender != address(comptroller)) {
            return (fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK), 0, 0, 0);
        }

        Double memory vaiMintIndex = Double({mantissa: annexVAIState.index});
        Double memory vaiMinterIndex = Double({mantissa: annexVAIMinterIndex[vaiMinter]});
        annexVAIMinterIndex[vaiMinter] = vaiMintIndex.mantissa;

        if (vaiMinterIndex.mantissa == 0 && vaiMintIndex.mantissa > 0) {
            vaiMinterIndex.mantissa = annexInitialIndex;
        }

        Double memory deltaIndex = sub_(vaiMintIndex, vaiMinterIndex);
        uint vaiMinterAmount = ComptrollerLensInterface(address(comptroller)).mintedVAIs(vaiMinter);
        uint vaiMinterDelta = mul_(vaiMinterAmount, deltaIndex);
        uint vaiMinterAccrued = add_(ComptrollerLensInterface(address(comptroller)).annexAccrued(vaiMinter), vaiMinterDelta);
        return (uint(Error.NO_ERROR), vaiMinterAccrued, vaiMinterDelta, vaiMintIndex.mantissa);
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new comptroller
      * @dev Admin function to set a new comptroller
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setComptroller(ComptrollerInterface comptroller_) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        ComptrollerInterface oldComptroller = comptroller;
        comptroller = comptroller_;
        emit NewComptroller(oldComptroller, comptroller_);

        return uint(Error.NO_ERROR);
    }

    function _become(VAIUnitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account total supply balance.
     *  Note that `aTokenBalance` is the number of aTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountAmountLocalVars {
        uint totalSupplyAmount;
        uint sumSupply;
        uint sumBorrowPlusEffects;
        uint aTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    function getMintableVAI(address minter) public view returns (uint, uint) {
        PriceOracle oracle = ComptrollerLensInterface(address(comptroller)).oracle();
        AToken[] memory enteredMarkets = ComptrollerLensInterface(address(comptroller)).getAssetsIn(minter);

        AccountAmountLocalVars memory vars; // Holds all our calculation results

        uint oErr;
        MathError mErr;

        uint accountMintableVAI;
        uint i;

        /**
         * We use this formula to calculate mintable VAI amount.
         * totalSupplyAmount * VAIMintRate - (totalBorrowAmount + mintedVAIOf)
         */
        for (i = 0; i < enteredMarkets.length; i++) {
            (oErr, vars.aTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = enteredMarkets[i].getAccountSnapshot(minter);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (uint(Error.SNAPSHOT_ERROR), 0);
            }
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(enteredMarkets[i]);
            if (vars.oraclePriceMantissa == 0) {
                return (uint(Error.PRICE_ERROR), 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            (mErr, vars.tokensToDenom) = mulExp(vars.exchangeRate, vars.oraclePrice);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // sumSupply += tokensToDenom * aTokenBalance
            (mErr, vars.sumSupply) = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.aTokenBalance, vars.sumSupply);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }
        }

        (mErr, vars.sumBorrowPlusEffects) = addUInt(vars.sumBorrowPlusEffects, ComptrollerLensInterface(address(comptroller)).mintedVAIs(minter));
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (mErr, accountMintableVAI) = mulUInt(vars.sumSupply, ComptrollerLensInterface(address(comptroller)).vaiMintRate());
        require(mErr == MathError.NO_ERROR, "VAI_MINT_AMOUNT_CALCULATION_FAILED");

        (mErr, accountMintableVAI) = divUInt(accountMintableVAI, 10000);
        require(mErr == MathError.NO_ERROR, "VAI_MINT_AMOUNT_CALCULATION_FAILED");


        (mErr, accountMintableVAI) = subUInt(accountMintableVAI, vars.sumBorrowPlusEffects);
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.REJECTION), 0);
        }

        return (uint(Error.NO_ERROR), accountMintableVAI);
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the VAI token
     * @return The address of VAI
     */
    function getVAIAddress() public view returns (address) {
        return 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7;
    }
}
