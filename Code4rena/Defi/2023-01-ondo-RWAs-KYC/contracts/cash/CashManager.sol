/**SPDX-License-Identifier: BUSL-1.1

      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 *   总结： 管理代币铸造和赎回的合约
 *         1）状态变量： 代币合约、资产接收者、费用接收者、最小存款金额、最小赎回金额、铸造费用等
 *         2）结构体和映射，用于存储铸造和赎回请求的信息
 *         3）函数: 用于处理铸造和赎回请求(检查请求的金额是否符合要求，并更新相应的状态变量)
 *            - requestMint函数用于提交铸造请求
 *            - requestRedemption函数用于提交赎回请求
 *            - 辅助函数: 用于计算铸造和赎回的金额，以及处理KYC（了解您的客户）验证
 *            - 管理函数: 用于设置合约的参数和权限。
 */
pragma solidity 0.8.16;

import "contracts/cash/interfaces/ICashManager.sol";
import "contracts/cash/interfaces/IMulticall.sol";
import "contracts/cash/token/Cash.sol";
import "contracts/cash/kyc/KYCRegistryClientConstructable.sol";
import "contracts/cash/external/openzeppelin/contracts/security/Pausable.sol";
import "contracts/cash/external/openzeppelin/contracts/token/IERC20.sol";
import "contracts/cash/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import "contracts/cash/external/openzeppelin/contracts/token/SafeERC20.sol";
import "contracts/cash/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "contracts/cash/external/openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CashManager is
    ICashManager,
    IMulticall,
    AccessControlEnumerable,
    KYCRegistryClientConstructable,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    /// @dev Tokens
    // ERC20 token used to Mint CASH with
    IERC20 public immutable collateral;

    // CASH contract
    Cash public immutable cash;

    /// @dev Collateral Recipients
    // The address to which the `collateral` is sent
    address public assetRecipient;

    // The address to which fees are sent
    address public feeRecipient;

    // The address from which redemptions are processed
    address public assetSender;

    /// @dev Mint/Redeem Parameters
    // Minimum amount that must be deposited to mint CASH
    // Denoted in decimals of `collateral`
    uint256 public minimumDepositAmount = 10_000;

    // Minimum amount that must be redeemed for a withdraw request
    uint256 public minimumRedeemAmount;

    // Minting fee specified in basis points
    uint256 public mintFee = 0;

    // Limit for how far `exchangeRate` can stray from
    // `lastSetMintExchangeRate` within an epoch (in basis points)
    uint256 public exchangeRateDeltaLimit = 100;

    // Struct representing all redemption requests in an epoch
    struct RedemptionRequests {
        // Total CASH burned in the epoch
        uint256 totalBurned;
        // Mapping from address to amount of CASH address burned
        mapping(address => uint256) addressToBurnAmt;
    }

    // Mapping from epoch to redemption info struct for that epoch
    mapping(uint256 => RedemptionRequests) public redemptionInfoPerEpoch;

    // Mapping used for getting the exchange rate during a given epoch
    mapping(uint256 => uint256) public epochToExchangeRate;

    // Nested mapping containing mint requests for an epoch
    // { <epoch> : {<user> : <collateralAmount> }
    mapping(uint256 => mapping(address => uint256)) public mintRequestsPerEpoch;

    // Helper constant that allows us to specify basis points in calculations
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // Decimal multiplier representing the difference between `CASH` decimals
    // In `collateral` token decimals
    uint256 public immutable decimalsMultiplier;

    /// @dev Epoch Parameters
    // Epoch that contract is currently in
    uint256 public currentEpoch;

    // Duration of an epoch in seconds
    uint256 public epochDuration;

    // Timestamp of the start of `currentEpoch`
    uint256 public currentEpochStartTimestamp;

    // `exchangeRate` at start of `currentEpoch`
    uint256 public lastSetMintExchangeRate = 1e6;

    /// @dev Mint/Redeem Limit Parameters
    // Maximum amount that can be minted during an epoch
    uint256 public mintLimit;

    // Amount already minted during the `currentEpoch`
    uint256 public currentMintAmount;

    // Maximum amount that can be redeemed during an epoch
    uint256 public redeemLimit;

    // Amount already redeemed during the `currentEpoch`
    uint256 public currentRedeemAmount;

    /// @dev Role Based Access control members
    bytes32 public constant MANAGER_ADMIN = keccak256("MANAGER_ADMIN");
    bytes32 public constant PAUSER_ADMIN = keccak256("PAUSER_ADMIN");
    bytes32 public constant SETTER_ADMIN = keccak256("SETTER_ADMIN");

    /// @notice constructor
    constructor(
        address _collateral,
        address _cash,
        address managerAdmin,
        address pauser,
        address _assetRecipient,
        address _assetSender,
        address _feeRecipient,
        uint256 _mintLimit,
        uint256 _redeemLimit,
        uint256 _epochDuration,
        address _kycRegistry,
        uint256 _kycRequirementGroup
    ) KYCRegistryClientConstructable(_kycRegistry, _kycRequirementGroup) {
        if (_collateral == address(0)) {
            revert CollateralZeroAddress();
        }
        if (_cash == address(0)) {
            revert CashZeroAddress();
        }
        if (_assetRecipient == address(0)) {
            revert AssetRecipientZeroAddress();
        }
        if (_assetSender == address(0)) {
            revert AssetSenderZeroAddress();
        }
        if (_feeRecipient == address(0)) {
            revert FeeRecipientZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, managerAdmin);
        _grantRole(MANAGER_ADMIN, managerAdmin);
        _setRoleAdmin(PAUSER_ADMIN, MANAGER_ADMIN);
        _setRoleAdmin(SETTER_ADMIN, MANAGER_ADMIN);
        _grantRole(PAUSER_ADMIN, pauser);

        collateral = IERC20(_collateral);
        cash = Cash(_cash);
        feeRecipient = _feeRecipient;
        assetRecipient = _assetRecipient;
        assetSender = _assetSender;
        currentEpoch = currentEpoch;

        mintLimit = _mintLimit;
        redeemLimit = _redeemLimit;
        epochDuration = _epochDuration;

        currentEpochStartTimestamp =
            block.timestamp -
            (block.timestamp % epochDuration);

        // Implicit constraint: cash decimals >= collateral decimals.
        decimalsMultiplier =
            10 **
                (IERC20Metadata(_cash).decimals() -
                    IERC20Metadata(_collateral).decimals());
    }

    /*//////////////////////////////////////////////////////////////
                            Mint Logic
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Function used by users to submit a request to mint
     *
     * @param collateralAmountIn The amount of collateral one wishes to deposit
     *                           to mint CASH tokens
     * 总结：提交一个铸造请求。用户需要提供一定数量的抵押品（collateral）以铸造CASH代币。在此过程中会收取一定比例的手续费。
     */
    function requestMint(
        uint256 collateralAmountIn
    )
        external
        override
        updateEpoch
        nonReentrant
        whenNotPaused
        checkKYC(msg.sender)
    {
        if (collateralAmountIn < minimumDepositAmount) {
            revert MintRequestAmountTooSmall();
        }

        uint256 feesInCollateral = _getMintFees(collateralAmountIn);
        uint256 depositValueAfterFees = collateralAmountIn - feesInCollateral;

        _checkAndUpdateMintLimit(depositValueAfterFees);

        collateral.safeTransferFrom(msg.sender, feeRecipient, feesInCollateral);
        collateral.safeTransferFrom(
            msg.sender,
            assetRecipient,
            depositValueAfterFees
        );

        mintRequestsPerEpoch[currentEpoch][msg.sender] += depositValueAfterFees;

        emit MintRequested(
            msg.sender,
            currentEpoch,
            collateralAmountIn,
            depositValueAfterFees,
            feesInCollateral
        );
    }

    /**
     * @notice Function used by users to claim an airdrop for a given epoch
     *
     * @param user       The user who requested to mint
     * @param epochToClaim The epoch in which the mint was requested
     *
     * @dev We perform KYC check on the user destined to receive `cash`, not the
     *      msg.sender
     * 总结： 领取特定时期的铸造奖励（即提交铸造请求时锁定的抵押品所产生的CASH代币）
     */
    function claimMint(
        address user,
        uint256 epochToClaim
    ) external override updateEpoch nonReentrant whenNotPaused checkKYC(user) {
        uint256 collateralDeposited = mintRequestsPerEpoch[epochToClaim][user];
        if (collateralDeposited == 0) {
            revert NoCashToClaim();
        }
        if (epochToExchangeRate[epochToClaim] == 0) {
            revert ExchangeRateNotSet();
        }

        // Get the amount of CASH due at a given rate per epoch
        uint256 cashOwed = _getMintAmountForEpoch(
            collateralDeposited,
            epochToClaim
        );

        mintRequestsPerEpoch[epochToClaim][user] = 0;
        cash.mint(user, cashOwed);

        emit MintCompleted(
            user,
            cashOwed,
            collateralDeposited,
            epochToExchangeRate[epochToClaim],
            epochToClaim
        );
    }

    /**
     * @notice Sets mint exchange rate
     *
     * @param exchangeRate New mint exchange rate (in 6 decimals)
     * @param epochToSet   The epoch we want to set the exchange rate for
     *
     * @dev If the exchange rate differs more than `exchangeRateDeltaLimit`
     *      from the last exchange rate set, the entire contract will be paused.
     *      See `overrideExchangeRate` should this check need to be bypassed
     * 总结： 设置铸造的兑换率。铸造兑换率决定了每单位抵押品可以兑换多少CASH代币。
     *       如果新的兑换率与上次设置的兑换率相差过大，合约将会被暂停以防止价格波动。
     */
    function setMintExchangeRate(
        uint256 exchangeRate,
        uint256 epochToSet
    ) external override updateEpoch onlyRole(SETTER_ADMIN) {
        if (exchangeRate == 0) {
            revert ZeroExchangeRate();
        }
        if (epochToSet >= currentEpoch) {
            revert EpochNotElapsed();
        }
        if (epochToExchangeRate[epochToSet] != 0) {
            revert EpochExchangeRateAlreadySet();
        }

        uint256 rateDifference;
        if (exchangeRate > lastSetMintExchangeRate) {
            rateDifference = exchangeRate - lastSetMintExchangeRate;
        } else if (exchangeRate < lastSetMintExchangeRate) {
            rateDifference = lastSetMintExchangeRate - exchangeRate;
        }

        uint256 maxDifferenceThisEpoch = (lastSetMintExchangeRate *
            exchangeRateDeltaLimit) / BPS_DENOMINATOR;

        if (rateDifference > maxDifferenceThisEpoch) {
            epochToExchangeRate[epochToSet] = exchangeRate;
            _pause();
            emit MintExchangeRateCheckFailed(
                epochToSet,
                lastSetMintExchangeRate,
                exchangeRate
            );
        } else {
            uint256 oldExchangeRate = lastSetMintExchangeRate;
            epochToExchangeRate[epochToSet] = exchangeRate;
            lastSetMintExchangeRate = exchangeRate;
            emit MintExchangeRateSet(epochToSet, oldExchangeRate, exchangeRate);
        }
    }

    /**
     * @notice Override admin function for changing the representation of the
     *         amount of collateral a user has deposited to kick off minting
     *         process
     *
     * @param user       The user whose balance is being set
     * @param epoch      The epoch in which to set user balance for
     * @param oldBalance The user's previous balance
     * @param newBalance The user's new balance to set
     *
     * @dev The total burned amount for the epoch must be set appropriately
     *      in order to correctly calculate redemptions.
     * @dev `oldBalance` is provided to prevent front running attacks where a
     *      user could attempt to claim before and after this is set.
     */
    function setPendingMintBalance(
        address user,
        uint256 epoch,
        uint256 oldBalance,
        uint256 newBalance
    ) external updateEpoch onlyRole(MANAGER_ADMIN) {
        if (oldBalance != mintRequestsPerEpoch[epoch][user]) {
            revert UnexpectedMintBalance();
        }
        if (epoch > currentEpoch) {
            revert CannotServiceFutureEpoch();
        }
        mintRequestsPerEpoch[epoch][user] = newBalance;
        emit PendingMintBalanceSet(user, epoch, oldBalance, newBalance);
    }

    /**
     * @notice Allows for the `MANAGER_ADMIN` to arbitrarily set an exchange
     *         rate for a given epoch
     *
     * @param correctExchangeRate      The exchange rate we wish to update to
     * @param epochToSet               The epoch for which we want to set the rate
     * @param _lastSetMintExchangeRate Value to set `lastSetMintExchangeRate` to
     *                                 if not equal to 0
     *
     * @dev This function allows the caller to also update the
     *      `lastSetMintExchangeRate`, which is compared against
     *      when calling `setMintExchangeRate` to prevent large
     *      swings in prices.
     * 总结： 由管理员强制设置特定时期的铸造兑换率。
     */
    function overrideExchangeRate(
        uint256 correctExchangeRate,
        uint256 epochToSet,
        uint256 _lastSetMintExchangeRate
    ) external override updateEpoch onlyRole(MANAGER_ADMIN) {
        if (epochToSet >= currentEpoch) {
            revert MustServicePastEpoch();
        }
        uint256 incorrectRate = epochToExchangeRate[epochToSet];
        epochToExchangeRate[epochToSet] = correctExchangeRate;
        if (_lastSetMintExchangeRate != 0) {
            lastSetMintExchangeRate = _lastSetMintExchangeRate;
        }
        emit MintExchangeRateOverridden(
            epochToSet,
            incorrectRate,
            correctExchangeRate,
            lastSetMintExchangeRate
        );
    }

    /**
     * @notice Sets mint exchange rate delta limit
     *
     * @param _exchangeRateDeltaLimit New mint exchange rate delta limit (in bps)
     * 总结：设置铸造兑换率的变动限制。
     */
    function setMintExchangeRateDeltaLimit(
        uint256 _exchangeRateDeltaLimit
    ) external override onlyRole(MANAGER_ADMIN) {
        uint256 oldExchangeRateDeltaLimit = exchangeRateDeltaLimit;
        exchangeRateDeltaLimit = _exchangeRateDeltaLimit;
        emit ExchangeRateDeltaLimitSet(
            oldExchangeRateDeltaLimit,
            _exchangeRateDeltaLimit
        );
    }

    /**
     * @notice Sets mint fee
     *
     * @param _mintFee new mint fee specified in basis points
     *
     * @dev The maximum fee that can be set is 10_000 bps, or 100%
     * 总结： 设置铸造手续费
     */
    function setMintFee(
        uint256 _mintFee
    ) external override onlyRole(MANAGER_ADMIN) {
        if (_mintFee >= BPS_DENOMINATOR) {
            revert MintFeeTooLarge();
        }
        uint256 oldMintFee = mintFee;
        mintFee = _mintFee;
        emit MintFeeSet(oldMintFee, _mintFee);
    }

    /**
     * @notice Sets minimum deposit amount
     *
     * @param _minimumDepositAmount New minimum deposit amount
     *                              (in decimals specified by `collateral`)
     *
     * @dev Must be larger than BPS_DENOMINATOR due to keep our `_getMintFees`
     *      calculation correct. For example, if a deposit amount is less than
     *      BPS_DENOMINAOR (say 9999) and `mintFee` = 1,
     *      (collateralAmount * mintFee) / BPS_DENOMINATOR will incorrectly
     *      return 0.
     * 总结： 设置最小抵押品金额。
     */
    function setMinimumDepositAmount(
        uint256 _minimumDepositAmount
    ) external override onlyRole(MANAGER_ADMIN) {
        if (_minimumDepositAmount < BPS_DENOMINATOR) {
            revert MinimumDepositAmountTooSmall();
        }
        uint256 oldMinimumDepositAmount = minimumDepositAmount;
        minimumDepositAmount = _minimumDepositAmount;
        emit MinimumDepositAmountSet(
            oldMinimumDepositAmount,
            _minimumDepositAmount
        );
    }

    /**
     * @notice Sets fee recipient
     *
     * @param _feeRecipient New fee recipient address
     * 总结：设置手续费接收地址。
     */
    function setFeeRecipient(
        address _feeRecipient
    ) external override onlyRole(MANAGER_ADMIN) {
        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @notice Sets asset recipient
     *
     * @param _assetRecipient New asset recipient address
     * 总结：设置资产接收地址。
     */
    function setAssetRecipient(
        address _assetRecipient
    ) external override onlyRole(MANAGER_ADMIN) {
        address oldAssetRecipient = assetRecipient;
        assetRecipient = _assetRecipient;
        emit AssetRecipientSet(oldAssetRecipient, _assetRecipient);
    }

    /**
     * @notice Given amount of `collateral`, returns how much CASH should be
     *         minted
     *
     * @param collateralAmountIn Amount of `collateral` to exchange
     *                           (in 18 decimals)
     * @param epoch              The epoch we want to set the rate
     *                           for
     *
     * @return cashAmountOut The amount of cash to be returned
     *
     * @dev Scales to 24 decimals to divide by exchange rate in 6 decimals,
     *      bringing us down to 18 decimals of precision
     * 总结： 根据抵押品数量和时期返回应该铸造的CASH代币数量
     */
    function _getMintAmountForEpoch(
        uint256 collateralAmountIn,
        uint256 epoch
    ) private view returns (uint256 cashAmountOut) {
        uint256 amountE24 = _scaleUp(collateralAmountIn) * 1e6;
        cashAmountOut = amountE24 / epochToExchangeRate[epoch];
    }

    /**
     * @notice Given amount of `collateral`, returns how
     *
     *
     * @param collateralAmount Amount `collateral` to exchange
     *                         (in decimals of `collateral`)
     * 总结：根据抵押品数量返回应该支付的手续费。
     */
    function _getMintFees(
        uint256 collateralAmount
    ) private view returns (uint256) {
        return (collateralAmount * mintFee) / BPS_DENOMINATOR;
    }

    /**
     * @notice Scale provided amount up by `decimalsMultiplier`
     *
     * @dev This helper is used for converting the collateral's decimals
     *      representation to the CASH amount decimals representation.
     * 总结： 将提供的数量按照一个倍数进行放大。
     */
    function _scaleUp(uint256 amount) private view returns (uint256) {
        return amount * decimalsMultiplier;
    }

    /*//////////////////////////////////////////////////////////////
                            Pause Utils
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Will pause minting functionality of this contract
     *
     */
    function pause() external onlyRole(PAUSER_ADMIN) {
        _pause();
    }

    /**
     * @notice Will unpause minting functionality of this contract
     */
    function unpause() external onlyRole(MANAGER_ADMIN) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                    Epoch and Rate Limiting Logic
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the duration of one epoch
     *
     * @param _epochDuration The epoch duration in seconds
     * 总结：更新一个时期（epoch）的持续时间，输入参数 _epochDuration 是一个以秒为单位的时期持续时间。
     */
    function setEpochDuration(
        uint256 _epochDuration
    ) external onlyRole(MANAGER_ADMIN) {
        uint256 oldEpochDuration = epochDuration;
        epochDuration = _epochDuration;
        emit EpochDurationSet(oldEpochDuration, _epochDuration);
    }

    /**
     * @notice Modifier to transition epoch
     * 总结：先执行 transitionEpoch()的修饰符
     */
    modifier updateEpoch() {
        transitionEpoch();
        _;
    }

    /**
     * @notice Transition to another epoch
     *
     * @dev Should be called prior to `_checkAndUpdateRedeemLimit`
     *      and `_checkAndUpdateMintLimit`
     * @dev Epochs do not always have to be incremented by 1
     *
     * @notice If this function determines to transition the epoch
     *         1) The total supply at the end of the epoch is stored
     *         2) `currentRedeemAmount` & `currentMintAmount` are set to 0
     *         3) `currentEpoch` is incremented by number of epochs that
     *            have elapsed
     *         4) `currentEpochStartTimestamp` is set.
     * 总结： 检查已经过去了多少个时期epoch;
     *       执行相应的操作，包括记录当前时期的总供应量、将currentRedeemAmount和currentMintAmount置零、递增当前时期数以及更新当前时期的开始时间戳。
     */
    function transitionEpoch() public {
        uint256 epochDifference = (block.timestamp -
            currentEpochStartTimestamp) / epochDuration;
        if (epochDifference > 0) {
            currentRedeemAmount = 0;
            currentMintAmount = 0;
            currentEpoch += epochDifference;
            currentEpochStartTimestamp =
                block.timestamp -
                (block.timestamp % epochDuration);
        }
    }

    /**
     * @notice Update the amount of token that can be minted during one epoch
     *
     * @param _mintLimit The token amount
     *
     * @dev If a limit is zero, the relevant check always fails.
     * 总结： 更新一个时期 epoch 内可以铸造的代币数量上限
     */
    function setMintLimit(uint256 _mintLimit) external onlyRole(MANAGER_ADMIN) {
        uint256 oldMintLimit = mintLimit;
        mintLimit = _mintLimit;
        emit MintLimitSet(oldMintLimit, _mintLimit);
    }

    /**
     * @notice Update the amount of token that can be redeemed during one epoch
     *
     * @param _redeemLimit The token amount
     *
     * @dev If a limit is zero, the relevant check always fails.
     * 总结：更新一个时期 epoch 内可以赎回的代币数量上限。
     */
    function setRedeemLimit(
        uint256 _redeemLimit
    ) external onlyRole(MANAGER_ADMIN) {
        uint256 oldRedeemLimit = redeemLimit;
        redeemLimit = _redeemLimit;
        emit RedeemLimitSet(oldRedeemLimit, _redeemLimit);
    }

    /**
     * @notice Checks the requested mint amount against the rate limiter
     *
     * @param collateralAmountIn The requested mint amount
     *
     * @dev Reverts if the requested mint amount exceeds the current limit
     * @dev Should only be called w/n functions w/ `updateEpoch` modifier
     * 总结：用于检查用户请求的铸造金额是否超过了当前时期的铸造速率限制。
     */
    function _checkAndUpdateMintLimit(uint256 collateralAmountIn) private {
        if (collateralAmountIn > mintLimit - currentMintAmount) {
            revert MintExceedsRateLimit();
        }

        currentMintAmount += collateralAmountIn;
    }

    /**
     * @notice Checks the requested redeem amount against the rate limiter
     *
     * @param amount The requested redeem amount
     *
     * @dev Reverts if the requested redeem amount exceeds the current limit
     * @dev Should only be called w/n function w/ `updateEpoch` modifier
     * 总结： 检查用户请求的赎回金额是否超过了当前时期的赎回速率限制。
     */
    function _checkAndUpdateRedeemLimit(uint256 amount) private {
        if (amount == 0) {
            revert RedeemAmountCannotBeZero();
        }
        if (amount > redeemLimit - currentRedeemAmount) {
            revert RedeemExceedsRateLimit();
        }

        currentRedeemAmount += amount;
    }

    /*//////////////////////////////////////////////////////////////
                          Redeem Logic
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a RedemptionRequests member to the current epoch array &
     *         burns tokens
     *
     * @param amountCashToRedeem The requested redeem amount
     */
    function requestRedemption(
        uint256 amountCashToRedeem
    )
        external
        override
        updateEpoch
        nonReentrant
        whenNotPaused
        checkKYC(msg.sender)
    {
        if (amountCashToRedeem < minimumRedeemAmount) {
            revert WithdrawRequestAmountTooSmall();
        }

        _checkAndUpdateRedeemLimit(amountCashToRedeem);

        redemptionInfoPerEpoch[currentEpoch].addressToBurnAmt[
                msg.sender
            ] += amountCashToRedeem;
        redemptionInfoPerEpoch[currentEpoch].totalBurned += amountCashToRedeem;

        cash.burnFrom(msg.sender, amountCashToRedeem);

        emit RedemptionRequested(msg.sender, amountCashToRedeem, currentEpoch);
    }

    /**
     * @notice Allows for an admin account to distribute collateral to users
     *         based off of the total amount of cash tokens burned w/n a given
     *         epoch. This function also allows for an admin to refund redemption
     *         requests w/n an epoch provided that the redemption cannot be
     *         serviced
     *
     * @param redeemers              List of addresses to which we want to
     *                               issue redemptions to
     * @param refundees              List of addresses to which we want to issue
     *                               refunds to in the form of cash tokens
     * @param collateralAmountToDist The total amount to distribute for redemptions
     *                               including fees to accrue to Ondo
     *                               (In units of collateral)
     * @param epochToService         The epoch number we wish to issue redemptions/
     *                               refunds for
     * @param fees                   The amount of fees to send to Ondo
     *                               (In units of collateral)
     * 总结： 管理员对用户进行抵押物的分发和现金代币的赎回（或退款），并且在执行这些操作之前会进行一些验证和计算。
     */
    function completeRedemptions(
        // 表示请求赎回的用户列表
        address[] calldata redeemers,
        // 请求退款的用户列表（现金形式）
        address[] calldata refundees,
        // 用于赎回（抵押物的分发）的总抵押物数量
        uint256 collateralAmountToDist,
        // 要进行赎回（抵押物的分发）或退款的时期编号。
        uint256 epochToService,
        // 要发送给 Ondo 的费用数量，以抵押物单位计量。
        uint256 fees
    ) external override updateEpoch onlyRole(MANAGER_ADMIN) {
        // 验证赎回者和退款者的地址是否符合KYC
        _checkAddressesKYC(redeemers);
        _checkAddressesKYC(refundees);
        // 检查要处理的时期是否大于或等于当前时期（currentEpoch）。
        if (epochToService >= currentEpoch) {
            revert MustServicePastEpoch();
        }
        // Calculate the total quantity of shares tokens burned w/n an epoch
        // 在给定时期内退款的总额
        uint256 refundedAmt = _processRefund(refundees, epochToService);
        // 在给定时期内燃烧的股份数量，减去了退款的数量。
        uint256 quantityBurned = redemptionInfoPerEpoch[epochToService]
            .totalBurned - refundedAmt;
        // 计算实际用于赎回的抵押物数量，减去了用于手续费的数量。
        uint256 amountToDist = collateralAmountToDist - fees;
        // 处理赎回操作（参数：赎回者列表、赎回的抵押物数量、股份数量以及要处理的时期。）
        _processRedemption(
            redeemers,
            amountToDist,
            quantityBurned,
            epochToService
        );
        // 从 assetSender 地址中将手续费转移到 feeRecipient 地址中。
        collateral.safeTransferFrom(assetSender, feeRecipient, fees);
        // 发出了一个事件通知，表示手续费已经被收取。
        emit RedemptionFeesCollected(feeRecipient, fees, epochToService);
    }

    /**
     * @notice Will iterate over the array of `addressToWithdraw` calculate
     *         the proportion of burned tokens w/n a given epoch and will
     *         then distribute collateral based off this % of burned tokens
     *
     * @param redeemers      List of addresses we are issuing redemptions too
     * @param amountToDist   The amount to distribute to clients minus the
     *                       the fee amount taken by Ondo
     * @param quantityBurned The total amount of tokens burned in an epoch
     *                       minus those burned by users who are issued a
     *                       refund
     * @param epochToService The epoch we wish to service redemptions and
     *                       redemptions for
     * 总结： 处理赎回过程
     */
    function _processRedemption(
        address[] calldata redeemers,
        // 用于赎回的资金总量减去Ondo收取的费用
        uint256 amountToDist,
        // 在某个时间段内烧毁的总代币数量，减去那些因为退款而烧毁的代币数量
        uint256 quantityBurned,
        // 要处理的时间段
        uint256 epochToService
    ) private {
        uint256 size = redeemers.length;
        for (uint256 i = 0; i < size; ++i) {
            address redeemer = redeemers[i];
            // 获取该地址所烧毁的代币数量
            uint256 cashAmountReturned = redemptionInfoPerEpoch[epochToService]
                .addressToBurnAmt[redeemer];
            //  设置为 0，表示已经处理过。
            redemptionInfoPerEpoch[epochToService].addressToBurnAmt[
                redeemer
            ] = 0;
            // 计算出应该分配的资金数量 collateralAmountDue。
            uint256 collateralAmountDue = (amountToDist * cashAmountReturned) /
                quantityBurned;

            // 如果 collateralAmountDue 为 0，会抛出一个异常，表示赎回的资金量太小。
            if (collateralAmountDue == 0) {
                revert CollateralRedemptionTooSmall();
            }

            collateral.safeTransferFrom(
                assetSender,
                redeemer,
                collateralAmountDue
            );
            emit RedemptionCompleted(
                redeemer,
                cashAmountReturned,
                collateralAmountDue,
                epochToService
            );
        }
    }

    /**
     * @notice Iterates over the array of `addressToRefund` and mint them
     *         back the same quantity of cash tokens burned.
     *
     * @param refundees      List of addresses we are issuing refunds for
     * @param epochToService The epoch we wish to service redemptions for
     *
     * @return totalCashAmountRefunded The total amount of cash refunded for `epochToService`.
     */
    function _processRefund(
        address[] calldata refundees,
        uint256 epochToService
    ) private returns (uint256 totalCashAmountRefunded) {
        uint256 size = refundees.length;
        for (uint256 i = 0; i < size; ++i) {
            address refundee = refundees[i];
            uint256 cashAmountBurned = redemptionInfoPerEpoch[epochToService]
                .addressToBurnAmt[refundee];
            redemptionInfoPerEpoch[epochToService].addressToBurnAmt[
                refundee
            ] = 0;
            cash.mint(refundee, cashAmountBurned);
            totalCashAmountRefunded += cashAmountBurned;
            emit RefundIssued(refundee, cashAmountBurned, epochToService);
        }
        return totalCashAmountRefunded;
    }

    /**
     * @notice will change the `assetSender` variable
     *
     * @param newAssetSender The address we wish to change `assetSender` too
     */
    function setAssetSender(
        address newAssetSender
    ) external onlyRole(MANAGER_ADMIN) {
        address oldAssetSender = assetSender;
        assetSender = newAssetSender;
        emit AssetSenderSet(oldAssetSender, newAssetSender);
    }

    /**
     * @notice Allows for `MANAGER_ADMIN` to set a new `minimumRedeemAmount`
     *
     * @param newRedeemMinimum The new minimum redemption amount
     *                         in units of 1e18
     */
    function setRedeemMinimum(
        uint256 newRedeemMinimum
    ) external onlyRole(MANAGER_ADMIN) {
        uint256 oldRedeemMin = minimumRedeemAmount;
        minimumRedeemAmount = newRedeemMinimum;
        emit MinimumRedeemAmountSet(oldRedeemMin, minimumRedeemAmount);
    }

    /**
     * @notice Custom view function to return the quantity burned by
     *         an address w/n a given epoch.
     *
     * @param epoch The epoch we want to query
     * @param user  The user we want to know the burned quantity
     *              of cash tokens for in a given epoch
     */
    function getBurnedQuantity(
        uint256 epoch,
        address user
    ) external view returns (uint256) {
        return redemptionInfoPerEpoch[epoch].addressToBurnAmt[user];
    }

    /**
     * @notice Override admin function for changing the representation of the
     *         amount of CASH a user has burned to kick off redemption process
     *
     * @param user    The user whose balance is being set
     * @param epoch   The epoch in which to set user balance for
     * @param balance The user's new balance
     *
     * @dev The total burned amount for the epoch must be set appropriately
     *      in order to correctly calculate redemptions.
     * 总结：这个函数是一个管理员级别的操作，用于设定用户在特定纪元（epoch）中的待处理赎回余额。
     */
    function setPendingRedemptionBalance(
        address user,
        uint256 epoch,
        uint256 balance
    ) external updateEpoch onlyRole(MANAGER_ADMIN) {
        // 函数会检查传入的 epoch 是否大于当前纪元 currentEpoch，
        if (epoch > currentEpoch) {
            revert CannotServiceFutureEpoch();
        }
        // 获取用户在该纪元中之前的余额 previousBalance。
        uint256 previousBalance = redemptionInfoPerEpoch[epoch]
            .addressToBurnAmt[user];
        // Increment or decrement total burned for the epoch based on whether we
        // are increasing or decreasing the balance.
        // 函数会根据新旧余额的变化情况，来更新该纪元的总燃烧量 totalBurned。
        // 如果新余额小于旧余额，说明用户减少了燃烧，所以总燃烧量会相应减少；
        // 如果新余额大于旧余额，说明用户增加了燃烧，总燃烧量会相应增加。
        if (balance < previousBalance) {
            redemptionInfoPerEpoch[epoch].totalBurned -=
                previousBalance -
                balance;
        } else if (balance > previousBalance) {
            redemptionInfoPerEpoch[epoch].totalBurned +=
                balance -
                previousBalance;
        }
        redemptionInfoPerEpoch[epoch].addressToBurnAmt[user] = balance;
        // 函数会更新该纪元中用户的燃烧余额，并触发一个事件 PendingRedemptionBalanceSet，
        emit PendingRedemptionBalanceSet(
            user,
            epoch,
            balance,
            redemptionInfoPerEpoch[epoch].totalBurned
        );
    }

    /*//////////////////////////////////////////////////////////////
                           KYC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modifier to check KYC status of an account
     */
    modifier checkKYC(address account) {
        _checkKYC(account);
        _;
    }

    /**
     * @notice Update KYC group of the contract for which
     *         accounts are checked against
     *
     * @param _kycRequirementGroup The new KYC requirement group
     */
    function setKYCRequirementGroup(
        uint256 _kycRequirementGroup
    ) external override onlyRole(MANAGER_ADMIN) {
        _setKYCRequirementGroup(_kycRequirementGroup);
    }

    /**
     * @notice Update KYC registry address
     *
     * @param _kycRegistry The new KYC registry address
     */
    function setKYCRegistry(
        address _kycRegistry
    ) external override onlyRole(MANAGER_ADMIN) {
        _setKYCRegistry(_kycRegistry);
    }

    /**
     * @notice Private function to check KYC status
     *         of an address
     *
     * @param account The account to check KYC status for
     */
    function _checkKYC(address account) private view {
        if (!_getKYCStatus(account)) {
            revert KYCCheckFailed();
        }
    }

    /**
     * @notice Private function to check KYC status
     *         of an array of addresses
     *
     * @param accounts The accounts to check KYC status for
     */
    function _checkAddressesKYC(address[] calldata accounts) private view {
        uint256 size = accounts.length;
        for (uint256 i = 0; i < size; ++i) {
            _checkKYC(accounts[i]);
        }
    }

    /**
     * @notice Allows for arbitrary batched calls
     *
     * @dev All external calls made through this function will
     *      msg.sender == contract address
     *
     * @param exCallData Struct consisting of
     *       1) target - contract to call
     *       2) data - data to call target with
     *       3) value - eth value to call target with
     */
    function multiexcall(
        ExCallData[] calldata exCallData
    )
        external
        payable
        override
        nonReentrant
        onlyRole(MANAGER_ADMIN)
        whenPaused
        returns (bytes[] memory results)
    {
        results = new bytes[](exCallData.length);
        for (uint256 i = 0; i < exCallData.length; ++i) {
            (bool success, bytes memory ret) = address(exCallData[i].target)
                .call{value: exCallData[i].value}(exCallData[i].data);
            require(success, "Call Failed");
            results[i] = ret;
        }
    }
}
