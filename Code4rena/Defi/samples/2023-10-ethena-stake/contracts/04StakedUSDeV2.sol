// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./StakedUSDe.sol";
import "./interfaces/IStakedUSDeCooldown.sol";
import "./USDeSilo.sol";

/**
 * @title StakedUSDeV2
 * @notice The StakedUSDeV2 contract allows users to stake USDe tokens and earn a portion of protocol LST and perpetual yield that is allocated
 * to stakers by the Ethena DAO governance voted yield distribution algorithm.  The algorithm seeks to balance the stability of the protocol by funding
 * the protocol's insurance fund, DAO activities, and rewarding stakers with a portion of the protocol's yield.
 * @dev If cooldown duration is set to zero, the StakedUSDeV2 behavior changes to follow ERC4626 standard and disables cooldownShares and cooldownAssets methods. If cooldown duration is greater than zero, the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626 standard, and enabling the cooldownShares and the cooldownAssets functions.
 * 总结： 用户可以将USDe代币进行质押（锁仓机制），并通过协议的收益分配算法来获得协议代币（LST）和永续收益的一部分。
 *         - 冷却期的概念允许用户在取回质押资产之前等待一段时间，以确保协议的稳定性。
 *      1） 继承：
 *             - IStakedUSDeCooldown 是一个接口（interface）
 *             - StakedUSDe 是一个已实现的合约。
 *      2）变量：
 *             - MAX_COOLDOWN_DURATION：一个设定的最大冷却期的时长，以秒为单位。
 *             - cooldownDuration：用来设定冷却期时长的变量。
 *             - ensureCooldownOff 和 ensureCooldownOn：两个修饰器，用于确保冷却期的开关状态。
 *      3）函数：
 *             - 构造函数三个参数：_asset（USDe代币的地址）、initialRewarder（初始奖励者的地址）和owner（管理员的地址）。
 *             - withdraw 和 redeem：这两个函数实现了 ERC4626 标准定义的方法，但根据冷却期的状态进行了一些修改。
 *             - unstake：当冷却期结束后，用户可以调用此函数来取回质押的资产。
 *             - cooldownAssets 和 cooldownShares：这两个函数分别允许用户将资产或份额冷却，以便在冷却期结束后取回对应的底层资产。
 *             - setCooldownDuration：用于设置冷却期的时长。如果时长设置为零，将遵循ERC4626标准；否则，将禁用ERC4626的提取和赎回功能，启用冷却方法。
 *      4）区别：
 *             - StakedUSDeV2 相对于 StakedUSDe 在功能上可能有一些额外的特性，例如引入了冷却期机制，同时也引入了 USDeSilo 这样的新合约。
 */
contract StakedUSDeV2 is IStakedUSDeCooldown, StakedUSDe {
    // 导入并使用了 SafeERC20 库，用于处理 IERC20 接口的安全交互，以防止常见的漏洞。
    using SafeERC20 for IERC20;

    // 定义了一个状态变量 cooldowns 映射，将地址与 UserCooldown 结构关联起来。
    // 这可能用于跟踪特定用户的冷却持续时间。
    mapping(address => UserCooldown) public cooldowns;

    // 对 USDeSilo 的合约的引用
    USDeSilo public silo;

    // 设定了一个最大的冷却持续时间为 90 天，，然后才能访问其锁仓的资产。
    // #audit 只设置最大不设置最小吗
    uint24 public MAX_COOLDOWN_DURATION = 90 days;

    // 存储当前的冷却持续时间（表示用户在可以提取其锁仓资产之前需要等待的时间。）
    uint24 public cooldownDuration;

    /// @notice ensure cooldownDuration is zero
    // 检查 cooldownDuration 是否为零，
    modifier ensureCooldownOff() {
        if (cooldownDuration != 0) revert OperationNotAllowed();
        _;
    }

    /// @notice ensure cooldownDuration is gt 0
    // 检查 cooldownDuration 是否大于零
    // #audit 不用检查小于零，下溢吗
    modifier ensureCooldownOn() {
        if (cooldownDuration == 0) revert OperationNotAllowed();
        _;
    }

    /// @notice Constructor for StakedUSDeV2 contract.
    /// @param _asset The address of the USDe token. 接口类型的参数，代表了代币 "USDe" 的地址。
    /// @param initialRewarder The address of the initial rewarder. 地址类型的参数，代表了初始奖励者的地址。
    /// @param owner The address of the admin role. 地址类型的参数，代表了管理员的地址。
    constructor(
        IERC20 _asset,
        address initialRewarder,
        address owner
    ) StakedUSDe(_asset, initialRewarder, owner) {
        // 创建了一个名为 USDeSilo 的新合约，并将当前合约的地址和代币 "USDe" 的地址作为参数传递给了 USDeSilo 合约的构造函数。
        silo = new USDeSilo(address(this), address(_asset));
        // 将 cooldownDuration 的值设为了 MAX_COOLDOWN_DURATION，也就是 90 天。
        cooldownDuration = MAX_COOLDOWN_DURATION;
    }

    /* ------------- EXTERNAL ------------- */

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(
        // 要提取的资产数量、接收提取资产的地址、提取资产的所有者地址。
        // ensureCooldownOff 的修饰器，这个修饰器确保冷却功能是关闭的
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override ensureCooldownOff returns (uint256) {
        // 调用了继承的合约 StakedUSDe 中的 withdraw 函数
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev See {IERC4626-redeem}. 赎回的份额等
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override ensureCooldownOff returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /// @notice Claim the staking amount after the cooldown has finished. The address can only retire the full amount of assets.
    // 用户可以在冷却期结束后领取抵押的资产，并且只能一次性领取全部资产。
    /// @dev unstake can be called after cooldown have been set to 0, to let accounts to be able to claim remaining assets locked at Silo
    // 将冷却期设置为 0 后可以调用 unstake 函数，以使帐户能够领取在 Silo 中锁定的剩余资产。
    /// @param receiver Address to send the assets by the staker
    // receiver，表示接收抵押资产的地址。
    function unstake(address receiver) external {
        // cooldowns 映射中以调用者地址 msg.sender 为键的值
        // 这个映射用于跟踪用户的冷却状态和相关资产。
        UserCooldown storage userCooldown = cooldowns[msg.sender];
        // 将 assets 设置为用户的抵押资产数量（这个数量存储在 userCooldown 结构体的 underlyingAmount 属性中。）
        uint256 assets = userCooldown.underlyingAmount;

        // 检查当前的时间戳是否大于或等于用户的冷却期结束时间。
        // #audit 使用属性还是方法
        // 用户只能在冷却期结束后才能领取抵押资产。
        if (block.timestamp >= userCooldown.cooldownEnd) {
            // 将用户的冷却期结束时间设置为 0，表示冷却已结束。
            // 将用户的抵押资产数量设置为 0，表示所有资产已领取。
            userCooldown.cooldownEnd = 0;
            userCooldown.underlyingAmount = 0;

            // 调用 silo 合约的 withdraw 函数，从 Silo 中将资产转移到指定的 receiver 地址。
            silo.withdraw(receiver, assets);
        } else {
            revert InvalidCooldown();
        }
    }

    // 用于赎回资产并开始冷却期的函数。在此期间，用户可以随时领取已转换的基础资产。
    /// @notice redeem assets and starts a cooldown to claim the converted underlying asset
    // 用户可以赎回资产，并开始一个冷却期以领取转换后的基础资产。
    /// @param assets assets to redeem 赎回的资产数量
    /// @param owner address to redeem and start cooldown, owner must allowed caller to perform this action
    // 赎回资产的地址，并开始冷却期，确保调用者被所有者授权执行此操作。
    function cooldownAssets(
        uint256 assets,
        address owner
    ) external ensureCooldownOn returns (uint256) {
        // 要赎回的资产数量是否超过了可以赎回的最大数量
        if (assets > maxWithdraw(owner)) revert ExcessiveWithdrawAmount();

        // #audit: 4626的这个函数应该没问题：previewWithdraw 的函数，用于计算赎回资产对应的份额数量
        uint256 shares = previewWithdraw(assets);

        // #audit: 将冷却期结束时间设置为当前时间加上预设的冷却期时长。
        cooldowns[owner].cooldownEnd =
            uint104(block.timestamp) +
            cooldownDuration;
        // 将用户的基础资产数量增加了要赎回的资产数量。
        cooldowns[owner].underlyingAmount += assets;

        // 调用者地址 _msgSender()，silo 合约的地址，owner 地址，要赎回的资产数量 assets，以及计算得到的份额数量 shares。
        _withdraw(_msgSender(), address(silo), owner, assets, shares);

        // 返回了赎回得到的份额数量。
        return shares;
    }

    /// @notice redeem shares into assets and starts a cooldown to claim the converted underlying asset
    // 用户可以将份额赎回为资产，并开始一个冷却期以领取转换后的基础资产。
    /// @param shares shares to redeem
    /// @param owner address to redeem and start cooldown, owner must allowed caller to perform this action
    function cooldownShares(
        uint256 shares,
        address owner
    ) external ensureCooldownOn returns (uint256) {
        // 检查用户要赎回的份额数量是否超过了可以赎回的最大数量。
        if (shares > maxRedeem(owner)) revert ExcessiveRedeemAmount();

        // 计算赎回份额对应的资产数量
        uint256 assets = previewRedeem(shares);

        // #audit：直接用变量，或调用函数
        // owner 的冷却期结束时间 = 当前时间 + 预设的冷却期时长。
        cooldowns[owner].cooldownEnd =
            uint104(block.timestamp) +
            cooldownDuration;
        // 用户的基础资产数量增加了要赎回的资产数量。
        cooldowns[owner].underlyingAmount += assets;

        // 调用者地址 _msgSender()，silo 合约的地址，owner 地址，要赎回的资产数量 assets，以及要赎回的份额数量 shares。
        _withdraw(_msgSender(), address(silo), owner, assets, shares);

        return assets;
    }

    /// @notice Set cooldown duration. If cooldown duration is set to zero, the StakedUSDeV2 behavior changes to follow ERC4626 standard and disables cooldownShares and cooldownAssets methods. If cooldown duration is greater than zero, the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626 standard, and enabling the cooldownShares and the cooldownAssets functions.
    // #audit 设置冷却期的时长
    // 如果将冷却期时长设置为零，StakedUSDeV2 的将遵循 ERC4626 标准，并禁用 cooldownShares 和 cooldownAssets 方法。如果冷却期时长大于零，将禁用 ERC4626 的 withdrawal 和 redeem 函数（违反 ERC4626 标准），并启用 cooldownShares 和 cooldownAssets 方法。
    /// @param duration Duration of the cooldown
    function setCooldownDuration(
        uint24 duration
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 传入的冷却期时长是否超过了预设的最大冷却期时长
        if (duration > MAX_COOLDOWN_DURATION) {
            revert InvalidCooldown();
        }

        // 将当前的冷却期时长保存在变量 previousDuration 中
        uint24 previousDuration = cooldownDuration;
        // 将传入的冷却期时长设置为新的冷却期时长。
        // #audit 新旧值
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
    }
}
