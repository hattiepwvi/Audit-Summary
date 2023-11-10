/**
 *Submitted for verification at Etherscan.io on 2023-09-28
*/

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IERC20 {
    
    /**
     * @dev Interface for the ERC20 standard as defined in the EIP.
     * @notice transfer and transferFrom have been removed to prevent usage with non-compliant tokens.
     * @notice Use BoringERC20 with `using BoringERC20 for IERC20` and call `safeTransfer`, `safeTransferFrom`, etc instead.
     */

    /// @return The total number of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @return The amount of tokens owned by the `account`.
    function balanceOf(address account) external view returns (uint256);
        
    /// @return The remaining number of tokens that `spender` will be allowed to spend on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @return A boolean value indicating whether the operation succeeded.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set by a call to `approve`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice EIP 2612
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

    /**
     * @title IStrictERC20
     * @dev Interface for a strictly compliant ERC20 token.
     * @notice Use with caution, only if you control the ERC20 token implementation.
     */
interface IStrictERC20 {
    /// @return The name of the token.
    function name() external view returns (string memory);

    /// @return The symbol of the token.
    function symbol() external view returns (string memory);

    /// @return The number of decimals the token uses.
    function decimals() external view returns (uint8);

    /// @return The total number of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @return balance of owner
    function balanceOf(address _owner) external view returns (uint256 balance);
    
    /// @notice Moves `_value` tokens from the caller's account to `_to`.
    /// @return success value indicating whether the operation succeeded.
    function transfer(address _to, uint256 _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function approve(address _spender, uint256 _value) external returns (bool success);
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice EIP 2612
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

struct Rebase {
    uint128 elastic;
    uint128 base;
}

/// @notice A rebasing library using overflow-/underflow-safe math.
library RebaseLibrary {
    /// @notice Calculates the base value in relationship to `elastic` and `total`.
    function toBase(
        Rebase memory total,
        uint256 elastic,
        bool roundUp
    ) internal pure returns (uint256 base) {
        if (total.elastic == 0) {
            base = elastic;
        } else {
            base = (elastic * total.base) / total.elastic;
            if (roundUp && (base * total.elastic) / total.base < elastic) {
                base++;
            }
        }
    }

    /// @notice Calculates the elastic value in relationship to `base` and `total`.
    function toElastic(
        Rebase memory total,
        uint256 base,
        bool roundUp
    ) internal pure returns (uint256 elastic) {
        if (total.base == 0) {
            elastic = base;
        } else {
            elastic = (base * total.elastic) / total.base;
            if (roundUp && (elastic * total.base) / total.elastic < base) {
                elastic++;
            }
        }
    }

    /// @notice Add `elastic` to `total` and doubles `total.base`.
    /// @return (Rebase) The new total.
    /// @return base in relationship to `elastic`.
    function add(
        Rebase memory total,
        uint256 elastic,
        bool roundUp
    ) internal pure returns (Rebase memory, uint256 base) {
        base = toBase(total, elastic, roundUp);
        total.elastic += uint128(elastic);
        total.base += uint128(base);
        return (total, base);
    }

    /// @notice Sub `base` from `total` and update `total.elastic`.
    /// @return (Rebase) The new total.
    /// @return elastic in relationship to `base`.
    function sub(
        Rebase memory total,
        uint256 base,
        bool roundUp
    ) internal pure returns (Rebase memory, uint256 elastic) {
        elastic = toElastic(total, base, roundUp);
        total.elastic -= uint128(elastic);
        total.base -= uint128(base);
        return (total, elastic);
    }

    /// @notice Add `elastic` and `base` to `total`.
    function add(
        Rebase memory total,
        uint256 elastic,
        uint256 base
    ) internal pure returns (Rebase memory) {
        total.elastic += uint128(elastic);
        total.base += uint128(base);
        return total;
    }

    /// @notice Subtract `elastic` and `base` to `total`.
    function sub(
        Rebase memory total,
        uint256 elastic,
        uint256 base
    ) internal pure returns (Rebase memory) {
        total.elastic -= uint128(elastic);
        total.base -= uint128(base);
        return total;
    }

    /// @notice Add `elastic` to `total` and update storage.
    /// @return newElastic Returns updated `elastic`.
    function addElastic(Rebase storage total, uint256 elastic) internal returns (uint256 newElastic) {
        newElastic = total.elastic += uint128(elastic);
    }

    /// @notice Subtract `elastic` from `total` and update storage.
    /// @return newElastic Returns updated `elastic`.
    function subElastic(Rebase storage total, uint256 elastic) internal returns (uint256 newElastic) {
        newElastic = total.elastic -= uint128(elastic);
    }
}

interface IStrategy {
    /// @notice Send the assets to the Strategy and call skim to invest them.
    /// @param amount The amount of tokens to invest.
    function skim(uint256 amount) external;

    /// @notice Harvest any profits made converted to the asset and pass them to the caller.
    /// @param balance The amount of tokens the caller thinks it has invested.
    /// @param sender The address of the initiator of this transaction. Can be used for reimbursements, etc.
    /// @return amountAdded The delta (+profit or -loss) that occured in contrast to `balance`.
    function harvest(uint256 balance, address sender) external returns (int256 amountAdded);

    /// @notice Withdraw assets. The returned amount can differ from the requested amount due to rounding.
    /// @dev The `actualAmount` should be very close to the amount.
    /// The difference should NOT be used to report a loss. That's what harvest is for.
    /// @param amount The requested amount the caller wants to withdraw.
    /// @return actualAmount The real amount that is withdrawn.
    function withdraw(uint256 amount) external returns (uint256 actualAmount);

    /// @notice Withdraw all assets in the safest way possible. This shouldn't fail.
    /// @param balance The amount of tokens the caller thinks it has invested.
    /// @return amountAdded The delta (+profit or -loss) that occured in contrast to `balance`.
    function exit(uint256 balance) external returns (int256 amountAdded);
}

interface IFlashBorrower {
    /// @notice The flashloan callback. `amount` + `fee` needs to repayed to msg.sender before this call returns.
    /// @param sender The address of the invoker of this flashloan.
    /// @param token The address of the token that is loaned.
    /// @param amount of the `token` that is loaned.
    /// @param fee The fee that needs to be paid on top for this loan. Needs to be the same as `token`.
    /// @param data Additional data that was passed to the flashloan function.
    function onFlashLoan(
        address sender,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

interface IBatchFlashBorrower {
    /// @notice The callback for batched flashloans. Every amount + fee needs to repayed to msg.sender before this call returns.
    /// @param sender The address of the invoker of this flashloan.
    /// @param tokens Array of addresses for ERC-20 tokens that is loaned.
    /// @param amounts A one-to-one map to `tokens` that is loaned.
    /// @param fees A one-to-one map to `tokens` that needs to be paid on top for each loan. Needs to be the same token.
    /// @param data Additional data that was passed to the flashloan function.
    function onBatchFlashLoan(
        address sender,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        bytes calldata data
    ) external;
}

/**
 * @title IBentoBoxV1
 * @dev Interface for BentoBox V1 which is a token vault that allows for batch transactions and flash loans.
 */
interface IBentoBoxV1 {
    
    function balanceOf(IERC20, address) external view returns (uint256);

    /**
     * @notice Allows batch calls to BentoBox and interaction with other contracts in one transaction.
     * @param calls An array of call data to be executed.
     * @param revertOnFail Decides whether to revert the whole transaction when one of the calls fails.
     * @return successes An array indicating the success status of each call.
     * @return results The data returned from each call.
     */
    function batch(bytes[] calldata calls, bool revertOnFail) external payable returns (bool[] memory successes, bytes[] memory results);

    /**
     * @notice Performs a flash loan with the ability to execute a batch of flash loans.
     * @param borrower The contract that receives the flash loan amounts.
     * @param receivers The addresses receiving the flash loan.
     * @param tokens The tokens to flash loan.
     * @param amounts The amounts of each token to loan.
     * @param data Arbitrary data passed to the borrower.
     */
    function batchFlashLoan(
        IBatchFlashBorrower borrower,
        address[] calldata receivers,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    /**
     * @notice Claims ownership of the BentoBox contract.
     */
    function claimOwnership() external;

    /**
     * @notice Performs a flash loan. BentoBox's flash loan feature allows for a new type of arbitrage.
     * @param borrower The contract that receives the flash loan amount.
     * @param receiver The address receiving the flash loan.
     * @param token The token to flash loan.
     * @param amount The amount to loan.
     * @param data Arbitrary data passed to the borrower.
     */
    function flashLoan(
        IFlashBorrower borrower,
        address receiver,
        IERC20 token,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @notice Deploys a new contract using a master contract.
     * @param masterContract The address of the master contract.
     * @param data Initialization data for the clone contract.
     * @param useCreate2 A boolean to decide whether to use create2 for deploying.
     * @return The address of the new deployed contract.
     */
    function deploy(
        address masterContract,
        bytes calldata data,
        bool useCreate2
    ) external payable returns (address);

    /**
     * @notice Allows depositing tokens into BentoBox.
     * @param token_ The ERC20 token to deposit.
     * @param from The address to pull the tokens from.
     * @param to The address that will receive the shares.
     * @param amount The amount of tokens to deposit.
     * @param share The amount of shares to receive for the tokens.
     * @return amountOut The amount of tokens deposited.
     * @return shareOut The amount of shares minted.
     */
    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    /**
     * @notice Harvests yields from the strategy associated with the token.
     * @param token The token for which the strategy is being harvested.
     * @param balance Should be true to harvest to BentoBox balance, false to harvest to strategy balance.
     * @param maxChangeAmount The maximum amount that the strategy is allowed to increase or decrease the balance by.
     */
    function harvest(
        IERC20 token,
        bool balance,
        uint256 maxChangeAmount
    ) external;

    /**
     * @notice Returns if a masterContract has been approved by a user.
     * @dev user The user to check for approval of a master contract.
     * @dev masterContract The master contract to check for approval.
     * @dev returns True if the master contract has been approved, false otherwise.
     */
    function masterContractApproved(address, address) external view returns (bool);

    /**
     * @notice Returns the address of the master contract for a specific clone contract.
     * @dev The clone contract to query for its master contract.
     * @return The address of the master contract.
     */
    function masterContractOf(address) external view returns (address);

    /**
     * @notice Returns the nonce for a given address. Nonces are used for permissioned actions.
     * @dev The address to query the nonce of.
     * @return The nonce of the given address.
     */
    function nonces(address) external view returns (uint256);

    /**
     * @notice Returns the address of the current owner of the contract.
     * @return The address of the owner.
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the address of the pending owner of the contract.
     * @return The address of the pending owner.
     */
    function pendingOwner() external view returns (address);

    /**
     * @notice Returns the strategy that is pending approval for a given token.
     * @dev The token to query for a pending strategy.
     * @return The strategy contract that is pending approval.
     */
    function pendingStrategy(IERC20) external view returns (IStrategy);

    /**
     * @notice Allows users to permit the spending of their tokens via signatures.
     * @param token The token for which spending is being permitted.
     * @param from The owner of the tokens.
     * @param to The spender of the tokens.
     * @param amount The amount of tokens to permit the spender to use.
     * @param deadline The time until which the permit is valid.
     * @param v, r, s Components of the signature.
     */
    function permitToken(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Registers the calling contract as a protocol that uses BentoBox.
     */
    function registerProtocol() external;

    /**
     * @notice Sets the approval status of a master contract for a user, with a signature.
     * @param user The user setting the approval status.
     * @param masterContract The master contract being approved or disapproved.
     * @param approved Whether the master contract is approved.
     * @param v, r, s Components of the signature.
     */
    function setMasterContractApproval(
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Sets a new strategy for a token.
     * @param token The token to set the strategy for.
     * @param newStrategy The new strategy contract.
     */
    function setStrategy(IERC20 token, IStrategy newStrategy) external;

    /**
     * @notice Sets the target percentage of the strategy for a given token.
     * @param token The token to set the strategy target percentage for.
     * @param targetPercentage_ The new target percentage.
     */
    function setStrategyTargetPercentage(IERC20 token, uint64 targetPercentage_) external;

    /**
     * @notice Returns the strategy for a given token.
     * @dev The token to query the strategy of.
     * @return The strategy contract for the given token.
     */
    function strategy(IERC20) external view returns (IStrategy);

    /**
     * @notice Returns strategy data for a given token.
     * @dev The token to query the strategy data of.
     * @return strategyStartDate The start date of the strategy.
     * @return targetPercentage The target percentage of the strategy.
     * @return balance The balance of the strategy.
     */
    function strategyData(IERC20)
        external
        view
        returns (
            uint64 strategyStartDate,
            uint64 targetPercentage,
            uint128 balance
        );


    /**
     * @notice Converts shares to the equivalent amount of a given token.
     * @param token The token to convert shares to amount.
     * @param share The number of shares to convert.
     * @param roundUp If true, rounds up to the nearest whole number.
     * @return amount equivelant to share.
     */
    function toAmount(
        IERC20 token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);

    /**
     * @notice Converts an amount of a token to the equivalent shares in the BentoBox.
     * @param token The token to convert the amount to shares.
     * @param amount The amount of the token to convert.
     * @param roundUp If true, the conversion will round up, resulting in potentially more shares.
     * @return share The number of shares equivalent to the given amount of the token.
     */
    function toShare(
        IERC20 token,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256 share);

    /**
     * @notice Returns the total supply and share supply for a token in the BentoBox.
     * @dev The token to query the total supplies of.
     * @return totals_ The total supplies struct containing the elastic and base supplies.
     */
    function totals(IERC20) external view returns (Rebase memory totals_);

    /**
     * @notice Transfers shares of a token from one address to another.
     * @param token The token of which shares will be transferred.
     * @param from The address to transfer the shares from.
     * @param to The address to transfer the shares to.
     * @param share The number of shares to transfer.
     */
    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) external;

    /**
     * @notice Transfers shares of a token from one address to multiple addresses.
     * @param token The token of which shares will be transferred.
     * @param from The address to transfer the shares from.
     * @param tos An array of addresses to transfer the shares to.
     * @param shares An array of the number of shares to transfer to each address.
     */
    function transferMultiple(
        IERC20 token,
        address from,
        address[] calldata tos,
        uint256[] calldata shares
    ) external;

    /**
     * @notice Initiates the transfer of the BentoBox ownership to a new address.
     * @param newOwner The address proposed as the new owner of BentoBox.
     * @param direct If true, the ownership will transfer immediately.
     * @param renounce If true, the current owner will renounce ownership, making the BentoBox ownerless.
     */
    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) external;

    /**
     * @notice Adds or removes a master contract to the whitelist of master contracts.
     * @param masterContract The master contract to whitelist or remove from the whitelist.
     * @param approved The approval status for the master contract.
     */
    function whitelistMasterContract(address masterContract, bool approved) external;

    /**
     * @notice Checks if a master contract is whitelisted.
     * @dev The master contract to check the whitelist status of.
     * @return True if the master contract is whitelisted, false otherwise.
     */
    function whitelistedMasterContracts(address) external view returns (bool);

    /**
     * @notice Withdraws a token from the BentoBox.
     * @param token_ The token to withdraw.
     * @param from The address to withdraw the tokens from.
     * @param to The address to send the withdrawn tokens to.
     * @param amount The amount of the token to withdraw.
     * @param share The number of shares to burn for the withdrawal.
     * @return amountOut The amount of tokens withdrawn.
     * @return shareOut The number of shares burned for the withdrawal.
     */
    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
}

interface IOracle {
    /// @notice Get the decimals of the oracle.
    /// @return decimals The decimals.
    function decimals() external view returns (uint8);

    /// @notice Get the latest exchange rate.
    /// @param data Usually abi encoded, implementation specific data that contains information and arguments to & about the oracle.
    /// For example:
    /// (string memory collateralSymbol, string memory assetSymbol, uint256 division) = abi.decode(data, (string, string, uint256));
    /// @return success if no valid (recent) rate is available, return false else true.
    /// @return rate The rate of the requested asset / pair / pool.
    function get(bytes calldata data) external returns (bool success, uint256 rate);

    /// @notice Check the last exchange rate without any state changes.
    /// @param data Usually abi encoded, implementation specific data that contains information and arguments to & about the oracle.
    /// For example:
    /// (string memory collateralSymbol, string memory assetSymbol, uint256 division) = abi.decode(data, (string, string, uint256));
    /// @return success if no valid (recent) rate is available, return false else true.
    /// @return rate The rate of the requested asset / pair / pool.
    function peek(bytes calldata data) external view returns (bool success, uint256 rate);

    /// @notice Check the current spot exchange rate without any state changes. For oracles like TWAP this will be different from peek().
    /// @param data Usually abi encoded, implementation specific data that contains information and arguments to & about the oracle.
    /// For example:
    /// (string memory collateralSymbol, string memory assetSymbol, uint256 division) = abi.decode(data, (string, string, uint256));
    /// @return rate The rate of the requested asset / pair / pool.
    function peekSpot(bytes calldata data) external view returns (uint256 rate);

    /// @notice Returns a human readable (short) name about this oracle.
    /// @param data Usually abi encoded, implementation specific data that contains information and arguments to & about the oracle.
    /// For example:
    /// (string memory collateralSymbol, string memory assetSymbol, uint256 division) = abi.decode(data, (string, string, uint256));
    /// @return (string) A human readable symbol name about this oracle.
    function symbol(bytes calldata data) external view returns (string memory);

    /// @notice Returns a human readable name about this oracle.
    /// @param data Usually abi encoded, implementation specific data that contains information and arguments to & about the oracle.
    /// For example:
    /// (string memory collateralSymbol, string memory assetSymbol, uint256 division) = abi.decode(data, (string, string, uint256));
    /// @return (string) A human readable name about this oracle.
    function name(bytes calldata data) external view returns (string memory);
}

interface IChamber {
    /**
     * @notice Gets the oracle contract associated with this Chamber.
     * @return IOracle The oracle contract interface.
     */
    function oracle() external view returns (IOracle);

    /**
     * @notice Gets the data used by the oracle for determining prices.
     * @return bytes The oracle data.
     */
    function oracleData() external view returns (bytes memory);

    /**
     * @notice Returns the accrue information including lastAccrueTime, feesEarned, and interestPerSecond.
     * @return uint64 The last time the accrue was called.
     * @return uint128 The total fees earned.
     * @return uint64 The interest charged per second.
     */
    function accrueInfo() external view returns (uint64, uint128, uint64);

    /**
     * @notice The fee taken when a borrow transaction is opened.
     * @return uint256 The opening fee for borrows.
     */
    function BORROW_OPENING_FEE() external view returns (uint256);

    /**
     * @notice The minimum rate at which collateral must exceed the borrowed amount.
     * @return uint256 The rate used to determine minimum collateralization.
     */
    function COLLATERIZATION_RATE() external view returns (uint256);

    /**
     * @notice The rate at which collateral is sold in a liquidation event.
     * @return uint256 The multiplier used when liquidating collateral.
     */
    function LIQUIDATION_MULTIPLIER() external view returns (uint256);

    /**
     * @notice The total amount of collateral shares within this Chamber.
     * @return uint256 The total collateral shares.
     */
    function totalCollateralShare() external view returns (uint256);

    /**
     * @notice The address of the BentoBox contract that the Chamber interacts with.
     * @return address The address of the BentoBox contract.
     */
    function bentoBox() external view returns (address);

    /**
     * @notice The address where fees collected by this Chamber are sent.
     * @return address The address that receives the fees.
     */
    function feeTo() external view returns (address);

    /**
     * @notice The master contract of this Chamber for the purpose of cloning.
     * @return IChamber The interface of the master contract.
     */
    function masterContract() external view returns (IChamber);

    /**
     * @notice The collateral token that is being used in the Chamber.
     * @return IERC20 The interface of the collateral token contract.
     */
    function collateral() external view returns (IERC20);

    /**
     * @notice Updates the address that receives the fees from the Chamber.
     * @param newFeeTo The new address that will receive the fees.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Accrues interest to outstanding borrows and fees to the Chamber.
     * It must be called periodically to update the interest rates and fees.
     */
    function accrue() external;

    function totalBorrow() external view returns (Rebase memory);

    function userBorrowPart(address account) external view returns (uint256);

    function userCollateralShare(address account) external view returns (uint256);

    function withdrawFees() external;

    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);

    function addCollateral(address to, bool skim, uint256 share) external;

    function removeCollateral(address to, uint256 share) external;

    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);

    function repay(address to, bool skim, uint256 part) external returns (uint256 amount);

    function reduceSupply(uint256 amount) external;

    function senUSD() external view returns (IERC20);

    function liquidate(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        address to,
        address swapper
    ) external;

    function updateExchangeRate() external returns (bool updated, uint256 rate);
}

library MathLib {
    function max(uint256[] memory values) internal pure returns (uint256) {
        uint256 maxValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] > maxValue) {
                maxValue = values[i];
            }
        }
        return maxValue;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256[] memory values) internal pure returns (uint256) {
        uint256 minValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] < minValue) {
                minValue = values[i];
            }
        }
        return minValue;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function subWithZeroFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}

// solhint-disable avoid-low-level-calls

library BoringERC20 {
    bytes4 private constant SIG_SYMBOL = 0x95d89b41; // symbol()
    bytes4 private constant SIG_NAME = 0x06fdde03; // name()
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()
    bytes4 private constant SIG_BALANCE_OF = 0x70a08231; // balanceOf(address)
    bytes4 private constant SIG_TOTALSUPPLY = 0x18160ddd; // balanceOf(address)
    bytes4 private constant SIG_TRANSFER = 0xa9059cbb; // transfer(address,uint256)
    bytes4 private constant SIG_TRANSFER_FROM = 0x23b872dd; // transferFrom(address,address,uint256)

    function returnDataToString(bytes memory data) internal pure returns (string memory) {
        if (data.length >= 64) {
            return abi.decode(data, (string));
        } else if (data.length == 32) {
            uint8 i = 0;
            while (i < 32 && data[i] != 0) {
                i++;
            }
            bytes memory bytesArray = new bytes(i);
            for (i = 0; i < 32 && data[i] != 0; i++) {
                bytesArray[i] = data[i];
            }
            return string(bytesArray);
        } else {
            return "???";
        }
    }

    /// @notice Provides a safe ERC20.symbol version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token symbol.
    function safeSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_SYMBOL));
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.name version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token name.
    function safeName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_NAME));
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
    /// @param token The address of the ERC-20 token contract.
    /// @return (uint8) Token decimals.
    function safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_DECIMALS));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    /// @notice Provides a gas-optimized balance check to avoid a redundant extcodesize check in addition to the returndatasize check.
    /// @param token The address of the ERC-20 token.
    /// @param to The address of the user to check.
    /// @return amount The token amount.
    function safeBalanceOf(IERC20 token, address to) internal view returns (uint256 amount) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_BALANCE_OF, to));
        require(success && data.length >= 32, "BoringERC20: BalanceOf failed");
        amount = abi.decode(data, (uint256));
    }

    /// @notice Provides a gas-optimized totalSupply to avoid a redundant extcodesize check in addition to the returndatasize check.
    /// @param token The address of the ERC-20 token.
    /// @return totalSupply The token totalSupply.
    function safeTotalSupply(IERC20 token) internal view returns (uint256 totalSupply) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_TOTALSUPPLY));
        require(success && data.length >= 32, "BoringERC20: totalSupply failed");
        totalSupply = abi.decode(data, (uint256));
    }

    /// @notice Provides a safe ERC20.transfer version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(SIG_TRANSFER, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "BoringERC20: Transfer failed");
    }

    /// @notice Provides a safe ERC20.transferFrom version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param from Transfer tokens from.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(SIG_TRANSFER_FROM, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "BoringERC20: TransferFrom failed");
    }
}

library ChamberLib {
    using BoringERC20 for IERC20;
    using RebaseLibrary for Rebase;

    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 internal constant BPS_PRECISION = 1e4;
    uint256 internal constant COLLATERIZATION_RATE_PRECISION = 1e5;
    uint256 internal constant LIQUIDATION_MULTIPLIER_PRECISION = 1e5;
    uint256 internal constant DISTRIBUTION_PART = 10;
    uint256 internal constant DISTRIBUTION_PRECISION = 100;

    /// @dev example: 200 is 2% interests
    function getInterestPerSecond(uint256 interestBips) internal pure returns (uint64 interestsPerSecond) {
        return uint64((interestBips * 316880878) / 100); // 316880878 is the precomputed integral part of 1e18 / (36525 * 3600 * 24)
    }

    function getInterestPerYearFromInterestPerSecond(uint64 interestPerSecond) internal pure returns (uint64 interestPerYearBips) {
        return (interestPerSecond * 100) / 316880878;
    }

    function getUserBorrowAmount(IChamber chamber, address user) internal view returns (uint256 borrowAmount) {
        Rebase memory totalBorrow = getTotalBorrowWithAccruedInterests(chamber);
        return (chamber.userBorrowPart(user) * totalBorrow.elastic) / totalBorrow.base;
    }

    // total borrow with on-fly accrued interests
    function getTotalBorrowWithAccruedInterests(IChamber chamber) internal view returns (Rebase memory totalBorrow) {
        totalBorrow = chamber.totalBorrow();
        (uint64 lastAccrued, , uint64 INTEREST_PER_SECOND) = chamber.accrueInfo();
        uint256 elapsedTime = block.timestamp - lastAccrued;

        if (elapsedTime != 0 && totalBorrow.base != 0) {
            totalBorrow.elastic = totalBorrow.elastic + uint128((uint256(totalBorrow.elastic) * INTEREST_PER_SECOND * elapsedTime) / 1e18);
        }
    }

    function getOracleExchangeRate(IChamber chamber) internal view returns (uint256) {
        IOracle oracle = IOracle(chamber.oracle());
        bytes memory oracleData = chamber.oracleData();
        return oracle.peekSpot(oracleData);
    }

    function getUserCollateral(IChamber chamber, address account) internal view returns (uint256 amount, uint256 value) {
        IBentoBoxV1 bentoBox = IBentoBoxV1(chamber.bentoBox());
        uint256 share = chamber.userCollateralShare(account);

        amount = bentoBox.toAmount(chamber.collateral(), share, false);
        value = (amount * EXCHANGE_RATE_PRECISION) / getOracleExchangeRate(chamber);
    }

    function getUserPositionInfo(
        IChamber chamber,
        address account
    )
        internal
        view
        returns (
            uint256 ltvBps,
            uint256 healthFactor,
            uint256 borrowValue,
            uint256 collateralValue,
            uint256 liquidationPrice,
            uint256 collateralAmount
        )
    {
        (collateralAmount, collateralValue) = getUserCollateral(chamber, account);

        borrowValue = getUserBorrowAmount(chamber, account);

        if (collateralValue > 0) {
            ltvBps = (borrowValue * BPS_PRECISION) / collateralValue;
            uint256 COLLATERALIZATION_RATE = chamber.COLLATERIZATION_RATE(); // 1e5 precision

            // example with WBTC (8 decimals)
            // 18 + 8 + 5 - 5 - 8 - 10 = 8 decimals
            IERC20 collateral = chamber.collateral();
            uint256 collateralPrecision = 10 ** collateral.safeDecimals();

            liquidationPrice =
                (borrowValue * collateralPrecision ** 2 * 1e5) /
                COLLATERALIZATION_RATE /
                collateralAmount /
                EXCHANGE_RATE_PRECISION;

            healthFactor = MathLib.subWithZeroFloor(
                EXCHANGE_RATE_PRECISION,
                (EXCHANGE_RATE_PRECISION * liquidationPrice * getOracleExchangeRate(chamber)) / collateralPrecision ** 2
            );
        }
    }

    /// @notice the liquidator will get "senUSD borrowPart" worth of collateral + liquidation fee incentive but borrowPart needs to be adjusted to take in account
    /// the borrowPart give less collateral than it should.
    /// @param chamber Chamber contract
    /// @param account Account to liquidate
    /// @param borrowPart Amount of senUSD debt to liquidate
    /// @return collateralAmount Amount of collateral that the liquidator will receive
    /// @return adjustedBorrowPart Adjusted borrowPart to take in account position with bad debt where the
    ///                            borrowPart give out more collateral than what the user has.
    /// @return requiredSenUSD senUSD amount that the liquidator will need to pay back to get the collateralShare
    function getLiquidationCollateralAndBorrowAmount(
        IChamber chamber,
        address account,
        uint256 borrowPart
    ) internal view returns (uint256 collateralAmount, uint256 adjustedBorrowPart, uint256 requiredSenUSD) {
        uint256 exchangeRate = getOracleExchangeRate(chamber);
        Rebase memory totalBorrow = getTotalBorrowWithAccruedInterests(chamber);
        IBentoBoxV1 box = IBentoBoxV1(chamber.bentoBox());
        uint256 collateralShare = chamber.userCollateralShare(account);
        IERC20 collateral = chamber.collateral();

        // cap to the maximum amount of debt that can be liquidated in case the chamber has bad debt
        {
            Rebase memory bentoBoxTotals = box.totals(collateral);

            // how much debt can be liquidated
            uint256 maxBorrowPart = (bentoBoxTotals.toElastic(collateralShare, false) * 1e23) /
                (chamber.LIQUIDATION_MULTIPLIER() * exchangeRate);
            maxBorrowPart = totalBorrow.toBase(maxBorrowPart, false);

            if (borrowPart > maxBorrowPart) {
                borrowPart = maxBorrowPart;
            }
        }

        // convert borrowPart to debt
        requiredSenUSD = totalBorrow.toElastic(borrowPart, false);

        // convert borrowPart to collateralShare
        {
            Rebase memory bentoBoxTotals = box.totals(collateral);

            // how much collateral share the liquidator will get from the given borrow amount
            collateralShare = bentoBoxTotals.toBase(
                (requiredSenUSD * chamber.LIQUIDATION_MULTIPLIER() * exchangeRate) /
                    (LIQUIDATION_MULTIPLIER_PRECISION * EXCHANGE_RATE_PRECISION),
                false
            );
            collateralAmount = box.toAmount(collateral, collateralShare, false);
        }

        {
            requiredSenUSD +=
                ((((requiredSenUSD * chamber.LIQUIDATION_MULTIPLIER()) / LIQUIDATION_MULTIPLIER_PRECISION) - requiredSenUSD) *
                    DISTRIBUTION_PART) /
                DISTRIBUTION_PRECISION;

            IERC20 senUSD = chamber.senUSD();

            // convert back and forth to amount to compensate for rounded up toShare conversion inside `liquidate`
            requiredSenUSD = box.toAmount(senUSD, box.toShare(senUSD, requiredSenUSD, true), true);
        }

        adjustedBorrowPart = borrowPart;
    }

    function isSolvent(IChamber chamber, address account) internal view returns (bool) {
        IBentoBoxV1 bentoBox = IBentoBoxV1(chamber.bentoBox());
        Rebase memory totalBorrow = getTotalBorrowWithAccruedInterests(chamber);
        uint256 exchangeRate = getOracleExchangeRate(chamber);
        IERC20 collateral = chamber.collateral();
        uint256 COLLATERIZATION_RATE = chamber.COLLATERIZATION_RATE();
        uint256 collateralShare = chamber.userCollateralShare(account);
        uint256 borrowPart = chamber.userBorrowPart(account);

        if (borrowPart == 0) {
            return true;
        } else if (collateralShare == 0) {
            return false;
        } else {
            return
                bentoBox.toAmount(
                    collateral,
                    (collateralShare * (EXCHANGE_RATE_PRECISION / COLLATERIZATION_RATE_PRECISION)) * COLLATERIZATION_RATE,
                    false
                ) >= (borrowPart * totalBorrow.elastic * exchangeRate) / totalBorrow.base;
        }
    }

    function getCollateralPrice(IChamber chamber) internal view returns (uint256) {
        IERC20 collateral = chamber.collateral();
        uint256 collateralPrecision = 10 ** collateral.safeDecimals();
        return (EXCHANGE_RATE_PRECISION * collateralPrecision) / getOracleExchangeRate(chamber);
    }

    function decodeInitData(
        bytes calldata data
    )
        internal
        pure
        returns (
            address collateral,
            address oracle,
            bytes memory oracleData,
            uint64 INTEREST_PER_SECOND,
            uint256 LIQUIDATION_MULTIPLIER,
            uint256 COLLATERIZATION_RATE,
            uint256 BORROW_OPENING_FEE
        )
    {
        (collateral, oracle, oracleData, INTEREST_PER_SECOND, LIQUIDATION_MULTIPLIER, COLLATERIZATION_RATE, BORROW_OPENING_FEE) = abi
            .decode(data, (address, address, bytes, uint64, uint256, uint256, uint256));
    }
}

contract MarketLens {
    struct UserPosition {
        address chamber;
        address account;
        uint256 ltvBps;
        uint256 healthFactor;
        uint256 borrowValue;
        AmountValue collateral;
        uint256 liquidationPrice;
    }

    struct MarketInfo {
        address chamber;
        uint256 borrowFee;
        uint256 maximumCollateralRatio;
        uint256 liquidationFee;
        uint256 interestPerYear;
        uint256 marketMaxBorrow;
        uint256 userMaxBorrow;
        uint256 totalBorrowed;
        uint256 oracleExchangeRate;
        uint256 collateralPrice;
        AmountValue totalCollateral;
    }

    struct AmountValue {
        uint256 amount;
        uint256 value;
    }

    uint256 constant PRECISION = 1e18;
    uint256 constant TENK_PRECISION = 1e5;
    uint256 constant BPS_PRECISION = 1e4;

    function getBorrowFee(IChamber chamber) public view returns (uint256) {
        return (chamber.BORROW_OPENING_FEE() * BPS_PRECISION) / TENK_PRECISION;
    }

    function getMaximumCollateralRatio(IChamber chamber) public view returns (uint256) {
        return (chamber.COLLATERIZATION_RATE() * BPS_PRECISION) / TENK_PRECISION;
    }

    function getLiquidationFee(IChamber chamber) public view returns (uint256) {
        uint256 liquidationFee = chamber.LIQUIDATION_MULTIPLIER() - 100_000;
        return (liquidationFee * BPS_PRECISION) / TENK_PRECISION;
    }

    function getInterestPerYear(IChamber chamber) public view returns (uint64) {
        (, , uint64 interestPerSecond) = chamber.accrueInfo();
        return ChamberLib.getInterestPerYearFromInterestPerSecond(interestPerSecond);
    }

    function getsenUSDInBentoBox(IChamber chamber) private view returns (uint256 senUSDInBentoBox) {
        IBentoBoxV1 bentoBox = IBentoBoxV1(chamber.bentoBox());
        IERC20 senUSD = IERC20(chamber.senUSD());
        uint256 poolBalance = bentoBox.balanceOf(senUSD, address(chamber));
        senUSDInBentoBox = bentoBox.toAmount(senUSD, poolBalance, false);
    }

    function getTokenInBentoBox(IBentoBoxV1 bentoBox, IERC20 token, address account) public view returns (uint256 share, uint256 amount) {
        return (bentoBox.balanceOf(token, account), bentoBox.toAmount(token, share, false));
    }

    function getMaxMarketBorrowForChamber(IChamber chamber) public view returns (uint256) {
        return getsenUSDInBentoBox(chamber);
    }

    function getMaxUserBorrowForChamber(IChamber chamber) public view returns (uint256) {
        return getsenUSDInBentoBox(chamber);
    }
    
    function getTotalBorrowed(IChamber chamber) public view returns (uint256) {
        return ChamberLib.getTotalBorrowWithAccruedInterests(chamber).elastic;
    }

    function getOracleExchangeRate(IChamber chamber) public view returns (uint256) {
        return ChamberLib.getOracleExchangeRate(chamber);
    }

    function getCollateralPrice(IChamber chamber) public view returns (uint256) {
        return ChamberLib.getCollateralPrice(chamber);
    }

    function getTotalCollateral(IChamber chamber) public view returns (AmountValue memory) {
        IBentoBoxV1 bentoBox = IBentoBoxV1(chamber.bentoBox());
        uint256 amount = bentoBox.toAmount(chamber.collateral(), chamber.totalCollateralShare(), false);
        uint256 value = (amount * PRECISION) / getOracleExchangeRate(chamber);
        return AmountValue(amount, value);
    }

    function getUserBorrow(IChamber chamber, address account) public view returns (uint256) {
        return ChamberLib.getUserBorrowAmount(chamber, account);
    }

    function getUserMaxBorrow(IChamber chamber, address account) public view returns (uint256) {
        (, uint256 value) = ChamberLib.getUserCollateral(chamber, account);
        return (value * getMaximumCollateralRatio(chamber)) / TENK_PRECISION;
    }

    function getUserCollateral(IChamber chamber, address account) public view returns (AmountValue memory) {
        (uint256 amount, uint256 value) = ChamberLib.getUserCollateral(chamber, account);
        return AmountValue(amount, value);
    }

    function getUserLtv(IChamber chamber, address account) public view returns (uint256 ltvBps) {
        (ltvBps, , , , , ) = ChamberLib.getUserPositionInfo(chamber, account);
    }

    function getHealthFactor(IChamber chamber, address account, bool isStable) public view returns (uint256) {
        (, uint256 healthFactor, , , , ) = ChamberLib.getUserPositionInfo(chamber, account);
        return isStable ? healthFactor * 10 : healthFactor;
    }

    function getUserLiquidationPrice(IChamber chamber, address account) public view returns (uint256 liquidationPrice) {
        (, , , , liquidationPrice, ) = ChamberLib.getUserPositionInfo(chamber, account);
    }

    function getUserPosition(IChamber chamber, address account) public view returns (UserPosition memory) {
        (
            uint256 ltvBps,
            uint256 healthFactor,
            uint256 borrowValue,
            uint256 collateralValue,
            uint256 liquidationPrice,
            uint256 collateralAmount
        ) = ChamberLib.getUserPositionInfo(chamber, account);

        return
            UserPosition(
                address(chamber),
                address(account),
                ltvBps,
                healthFactor,
                borrowValue,
                AmountValue({amount: collateralAmount, value: collateralValue}),
                liquidationPrice
            );
    }

    // Get many user position information at once.
    // Beware of hitting RPC `eth_call` gas limit
    function getUserPositions(IChamber chamber, address[] calldata accounts) public view returns (UserPosition[] memory positions) {
        positions = new UserPosition[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            positions[i] = getUserPosition(chamber, accounts[i]);
        }
    }

    function getMarketInfoChamber(IChamber chamber) public view returns (MarketInfo memory) {
        return
            MarketInfo({
                chamber: address(chamber),
                borrowFee: getBorrowFee(chamber),
                maximumCollateralRatio: getMaximumCollateralRatio(chamber),
                liquidationFee: getLiquidationFee(chamber),
                interestPerYear: getInterestPerYear(chamber),
                marketMaxBorrow: getMaxMarketBorrowForChamber(chamber),
                userMaxBorrow: getMaxUserBorrowForChamber(chamber),
                totalBorrowed: getTotalBorrowed(chamber),
                oracleExchangeRate: getOracleExchangeRate(chamber),
                collateralPrice: getCollateralPrice(chamber),
                totalCollateral: getTotalCollateral(chamber)
            });
    }
}