// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISwap} from "../../interfaces/swap/ISwap.sol";
import {GMXTypes} from "./GMXTypes.sol";
import {GMXReader} from "./GMXReader.sol";
import {GMXWorker} from "./GMXWorker.sol";

/**
 * @title GMXManager
 * @author Steadefi
 * @notice Re-usable library functions for calculations and operations of borrows, repays, swaps
 * adding and removal of liquidity to yield source
 * Summary: borrowing, repaying, swapping, and adding/removing liquidity to/from a yield source in total and for long and short tokens
 */
library GMXManager {
    using SafeERC20 for IERC20;

    /* ====================== CONSTANTS ======================== */

    uint256 public constant SAFE_MULTIPLIER = 1e18;

    /* ===================== VIEW FUNCTIONS ==================== */

    /**
     * @notice Calculate if token swap is needed to ensure enough repayment for both tokenA and tokenB
     * @notice Assume that after swapping one token for the other, there is still enough to repay both tokens
     * @param self GMXTypes.Store
     * @param rp GMXTypes.RepayParams
     * @return swapNeeded boolean if swap is needed
     * @return tokenFrom address of token to swap from
     * @return tokenTo address of token to swap to
     * @return tokenToAmt amount of tokenFrom to swap in token decimals
     */

    // determine whether a token swap is necessary to ensure there is enough of both tokenA and tokenB for repayment.
    function calcSwapForRepay(
        // struct
        GMXTypes.Store storage self,
        GMXTypes.RepayParams memory rp
    ) external view returns (bool, address, address, uint256) {
        address _tokenFrom;
        address _tokenTo;
        uint256 _tokenToAmt;

        // #audit if B swap to A, then B is not enough to repay
        if (rp.repayTokenAAmt > self.tokenA.balanceOf(address(this))) {
            // If more tokenA is needed for repayment
            // it means that there's a shortfall of tokenA for repayment.
            // Calculates the amount of tokenFrom needed for the swap.
            _tokenToAmt =
                rp.repayTokenAAmt -
                self.tokenA.balanceOf(address(this));
            //  indicating that a swap is needed.
            _tokenFrom = address(self.tokenB);
            _tokenTo = address(self.tokenA);

            return (true, _tokenFrom, _tokenTo, _tokenToAmt);
        } else if (rp.repayTokenBAmt > self.tokenB.balanceOf(address(this))) {
            // If more tokenB is needed for repayment
            _tokenToAmt =
                rp.repayTokenBAmt -
                self.tokenB.balanceOf(address(this));
            _tokenFrom = address(self.tokenA);
            _tokenTo = address(self.tokenB);

            return (true, _tokenFrom, _tokenTo, _tokenToAmt);
            // If neither condition is met, it means there is enough to repay both tokens:
        } else {
            // If more there is enough to repay both tokens
            return (false, address(0), address(0), 0);
        }
    }

    /**
     * @notice Calculate amount of tokenA and tokenB to borrow
     * @param self GMXTypes.Store
     * @param depositValue USD value in 1e18
     */
    function calcBorrow(
        GMXTypes.Store storage self,
        uint256 depositValue
    ) external view returns (uint256, uint256) {
        // # audit: divide
        // Calculate final position value based on deposit value and leverage
        // 1e18 or 10^18
        uint256 _positionValue = (depositValue * self.leverage) /
            SAFE_MULTIPLIER;

        // Obtain the value to borrow
        uint256 _borrowValue = _positionValue - depositValue;

        uint256 _tokenADecimals = IERC20Metadata(address(self.tokenA))
            .decimals();
        uint256 _tokenBDecimals = IERC20Metadata(address(self.tokenB))
            .decimals();
        // Variables to hold the amounts of tokenA and tokenB to borrow.
        uint256 _borrowLongTokenAmt;
        uint256 _borrowShortTokenAmt;

        // If delta is long, borrow all in short token
        // convert a value from tokenB to its equivalent USD value.
        // long Delta Strategy:
        // e.g. expect Token M to grow: borrow the short Token N to acquire more of the long asset Token M

        if (self.delta == GMXTypes.Delta.Long) {
            _borrowShortTokenAmt =
                (_borrowValue * SAFE_MULTIPLIER) /
                GMXReader.convertToUsdValue(
                    self,
                    address(self.tokenB),
                    10 ** (_tokenBDecimals)
                ) /
                (10 ** (18 - _tokenBDecimals));
        }

        // If delta is neutral, borrow appropriate amount in long token to hedge, and the rest in short token

        if (self.delta == GMXTypes.Delta.Neutral) {
            // Get token weights in LP, e.g. 50% = 5e17
            // if TokenA has a weight of 50%, _tokenAWeight would be 5e17 (since percentages are represented as values between 0 and 1).
            (uint256 _tokenAWeight, ) = GMXReader.tokenWeights(self);

            // Get value of long token (typically tokenA)
            uint256 _longTokenWeightedValue = (_tokenAWeight * _positionValue) /
                SAFE_MULTIPLIER;

            // Borrow appropriate amount in long token to hedge
            _borrowLongTokenAmt =
                (_longTokenWeightedValue * SAFE_MULTIPLIER) /
                GMXReader.convertToUsdValue(
                    self,
                    address(self.tokenA),
                    10 ** (_tokenADecimals)
                ) /
                (10 ** (18 - _tokenADecimals));

            // Borrow the shortfall value in short token
            _borrowShortTokenAmt =
                ((_borrowValue - _longTokenWeightedValue) * SAFE_MULTIPLIER) /
                GMXReader.convertToUsdValue(
                    self,
                    address(self.tokenB),
                    10 ** (_tokenBDecimals)
                ) /
                (10 ** (18 - _tokenBDecimals));
        }

        return (_borrowLongTokenAmt, _borrowShortTokenAmt);
    }

    /**
     * @notice Calculate amount of tokenA and tokenB to repay based on token shares ratio being withdrawn
     * @param self GMXTypes.Store
     * @param shareRatio Amount of vault token shares relative to total supply in 1e18
     */
    function calcRepay(
        GMXTypes.Store storage self,
        uint256 shareRatio
    ) external view returns (uint256, uint256) {
        (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = GMXReader.debtAmt(
            self
        );

        //  calculates the amount of tokenA to be repaid
        uint256 _repayTokenAAmt = (shareRatio * tokenADebtAmt) /
            SAFE_MULTIPLIER;
        uint256 _repayTokenBAmt = (shareRatio * tokenBDebtAmt) /
            SAFE_MULTIPLIER;

        return (_repayTokenAAmt, _repayTokenBAmt);
    }

    /**
     * @notice Calculate minimum market (GM LP) tokens to receive when adding liquidity
     * @param self GMXTypes.Store
     * @param depositValue USD value in 1e18
     * @param slippage Slippage value in 1e4
     * @return minMarketTokenAmt in 1e18
     */
    function calcMinMarketSlippageAmt(
        GMXTypes.Store storage self,
        uint256 depositValue,
        // representing the slippage value in 1e4 (percentage)
        uint256 slippage
    ) external view returns (uint256) {
        // calculates the value of LP tokens based on the provided parameters.
        uint256 _lpTokenValue = self.gmxOracle.getLpTokenValue(
            address(self.lpToken),
            address(self.tokenA),
            address(self.tokenA),
            address(self.tokenB),
            false,
            false
        );

        return
            // if slippage is 100 (1%), then 10000 - slippage is 9900, which represents a 99% slippage tolerance
            // #audit minus slippage
            (((depositValue * SAFE_MULTIPLIER) / _lpTokenValue) *
                (10000 - slippage)) / 10000;
    }

    /**
     * @notice Calculate minimum tokens to receive when removing liquidity
     * @dev minLongToken and minShortToken should be the token which we want to receive
     * after liquidity withdrawal and swap
     * @param self GMXTypes.Store
     * @param lpAmt Amt of lp tokens to remove liquidity in 1e18
     * @param minLongToken Address of token to receive longToken in
     * @param minShortToken Address of token to receive shortToken in
     * @param slippage Slippage value in 1e4
     * @return minTokenAAmt in 1e18
     * @return minTokenBAmt in 1e18
     */

    function calcMinTokensSlippageAmt(
        GMXTypes.Store storage self,
        uint256 lpAmt,
        address minLongToken,
        address minShortToken,
        uint256 slippage
    ) external view returns (uint256, uint256) {
        // the value of the liquidity being withdrawn = the amount of LP tokens  * the value of LP tokens
        uint256 _withdrawValue = (lpAmt *
            self.gmxOracle.getLpTokenValue(
                address(self.lpToken),
                address(self.tokenA),
                address(self.tokenA),
                address(self.tokenB),
                false,
                false
            )) / SAFE_MULTIPLIER;

        (uint256 _tokenAWeight, uint256 _tokenBWeight) = GMXReader.tokenWeights(
            self
        );

        // the value of the liquidity being withdrawn * the weight of TokenA in the LP
        uint256 _minLongTokenAmt = (((_withdrawValue * _tokenAWeight) /
            SAFE_MULTIPLIER) * SAFE_MULTIPLIER) /
            GMXReader.convertToUsdValue(
                self,
                minLongToken,
                10 ** (IERC20Metadata(minLongToken).decimals())
            ) /
            (10 ** (18 - IERC20Metadata(minLongToken).decimals()));

        uint256 _minShortTokenAmt = (((_withdrawValue * _tokenBWeight) /
            SAFE_MULTIPLIER) * SAFE_MULTIPLIER) /
            GMXReader.convertToUsdValue(
                self,
                minShortToken,
                10 ** (IERC20Metadata(minShortToken).decimals())
            ) /
            (10 ** (18 - IERC20Metadata(minShortToken).decimals()));

        return (
            (_minLongTokenAmt * (10000 - slippage)) / 10000,
            (_minShortTokenAmt * (10000 - slippage)) / 10000
        );
    }

    /* ================== MUTATIVE FUNCTIONS =================== */

    /**
     * @notice Borrow tokens from lending vaults
     * @param self GMXTypes.Store
     * @param borrowTokenAAmt Amount of tokenA to borrow in token decimals
     * @param borrowTokenBAmt Amount of tokenB to borrow in token decimals
     */
    function borrow(
        GMXTypes.Store storage self,
        uint256 borrowTokenAAmt,
        uint256 borrowTokenBAmt
    ) public {
        if (borrowTokenAAmt > 0) {
            self.tokenALendingVault.borrow(borrowTokenAAmt);
        }
        if (borrowTokenBAmt > 0) {
            self.tokenBLendingVault.borrow(borrowTokenBAmt);
        }
    }

    /**
     * @notice Repay tokens to lending vaults
     * @param self GMXTypes.Store
     * @param repayTokenAAmt Amount of tokenA to repay in token decimals
     * @param repayTokenBAmt Amount of tokenB to repay in token decimals
     */
    function repay(
        GMXTypes.Store storage self,
        uint256 repayTokenAAmt,
        uint256 repayTokenBAmt
    ) public {
        if (repayTokenAAmt > 0) {
            self.tokenALendingVault.repay(repayTokenAAmt);
        }
        if (repayTokenBAmt > 0) {
            self.tokenBLendingVault.repay(repayTokenBAmt);
        }
    }

    /**
     * @notice Add liquidity to yield source
     * @param self GMXTypes.Store
     * @param alp GMXTypes.AddLiquidityParams
     * @return depositKey
     */
    function addLiquidity(
        // alp: A struct GMXTypes.AddLiquidityParams containing information about the liquidity to be added.
        GMXTypes.Store storage self,
        GMXTypes.AddLiquidityParams memory alp
    ) public returns (bytes32) {
        return GMXWorker.addLiquidity(self, alp);
    }

    /**
     * @notice Remove liquidity from yield source
     * @param self GMXTypes.Store
     * @param rlp GMXTypes.RemoveLiquidityParams
     * @return withdrawKey
     */
    function removeLiquidity(
        GMXTypes.Store storage self,
        GMXTypes.RemoveLiquidityParams memory rlp
    ) public returns (bytes32) {
        return GMXWorker.removeLiquidity(self, rlp);
    }

    /**
     * @notice Swap exact amount of tokenIn for as many possible amount of tokenOut
     * @param self GMXTypes.Store
     * @param sp ISwap.SwapParams
     * @return amountOut in token decimals
     */
    function swapExactTokensForTokens(
        GMXTypes.Store storage self,
        ISwap.SwapParams memory sp
    ) external returns (uint256) {
        if (sp.amountIn > 0) {
            return GMXWorker.swapExactTokensForTokens(self, sp);
        } else {
            return 0;
        }
    }

    /**
     * @notice Swap as little posible tokenIn for exact amount of tokenOut
     * @param self GMXTypes.Store
     * @param sp ISwap.SwapParams
     * @return amountIn in token decimals
     */
    function swapTokensForExactTokens(
        // A struct ISwap.SwapParams containing information about the swap
        GMXTypes.Store storage self,
        ISwap.SwapParams memory sp
    ) external returns (uint256) {
        if (sp.amountIn > 0) {
            return GMXWorker.swapTokensForExactTokens(self, sp);
        } else {
            return 0;
        }
    }
}

// If the situation is such that swapping tokenB to tokenA is not enough to repay the debt, you would need to implement a more complex logic that considers multiple possible swaps.

// Here's a modified version of the calcSwapForRepay function that takes into account the possibility of multiple swaps:

// solidity
// Copy code
// 

event FundsShortage(address account, uint256 amount);

function calcSwapForRepay(
    GMXTypes.Store storage self,
    GMXTypes.RepayParams memory rp
) external view returns (bool, address, address, uint256) {
    address _tokenFrom;
    address _tokenTo;
    uint256 _tokenToAmt;

    uint256 tokenABalance = self.tokenA.balanceOf(address(this));
    uint256 tokenBBalance = self.tokenB.balanceOf(address(this));

    // Check if swapping tokenB to tokenA is enough to repay
    if (rp.repayTokenAAmt <= tokenABalance && rp.repayTokenBAmt <= tokenBBalance) {
        return (false, address(0), address(0), 0); // No swap needed
    }

    // Check if swapping tokenB to tokenA could cover the shortfall in tokenA
    if (rp.repayTokenAAmt > tokenABalance) {
        uint256 swapAmountBtoA = rp.repayTokenAAmt - tokenABalance;
        uint256 swapAmountAtoB = swapAmountBtoA * self.tokenAtoBPrice() / self.tokenBtoAPrice();

        if (swapAmountAtoB <= tokenBBalance) {
            return (true, address(self.tokenB), address(self.tokenA), swapAmountBtoA);
        } else {
            emit FundsShortage(address(this), swapAmountAtoB);
        }
    }

    // Check if swapping tokenA to tokenB could cover the shortfall in tokenB
    if (rp.repayTokenBAmt > tokenBBalance) {
        uint256 swapAmountAtoB = rp.repayTokenBAmt - tokenBBalance;
        uint256 swapAmountBtoA = swapAmountAtoB * self.tokenBtoAPrice() / self.tokenAtoBPrice();

        if (swapAmountBtoA <= tokenABalance) {
            return (true, address(self.tokenA), address(self.tokenB), swapAmountAtoB);
        } else {
            emit FundsShortage(address(this), swapAmountBtoA);
        }
    }

//     return (false, address(0), address(0), 0); // Unable to find a suitable swap
// }
// In this modified version, the function first checks if there is enough of both tokenA and tokenB to cover the repayment without needing a swap. If so, it returns (false, address(0), address(0), 0) to indicate that no swap is needed.

// If either tokenA or tokenB is insufficient for repayment, it then considers the possibility of a swap. It calculates the amount to swap (swapAmountBtoA or swapAmountAtoB) and checks if there is enough balance in the other token (tokenB or tokenA) to perform the swap. If a suitable swap is found, it returns the necessary information.

// If none of the swap scenarios are successful, it returns (false, address(0), address(0), 0) to indicate that no suitable swap was found.
