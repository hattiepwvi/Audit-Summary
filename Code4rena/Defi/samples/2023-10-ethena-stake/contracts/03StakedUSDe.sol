// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

/**
 * solhint-disable private-vars-leading-underscore
 */

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./SingleAdminAccessControl.sol";
import "./interfaces/IStakedUSDe.sol";

/**
 * @title StakedUSDe
 * @notice The StakedUSDe contract allows users to stake USDe tokens and earn a portion of protocol LST and perpetual yield that is allocated
 * to stakers by the Ethena DAO governance voted yield distribution algorithm.  The algorithm seeks to balance the stability of the protocol by funding
 * the protocol's insurance fund, DAO activities, and rewarding stakers with a portion of the protocol's yield.
 * 总结：StakedUSDe 合约用于质押USDe代币并从协议的收益中获得奖励
 *       - 还提供了一些角色和机制，用于管理黑名单、分发奖励等。同时，
 *       - 以防止潜在的攻击。
 *     1）继承：
 *         - ERC20: 基本的代币功能，如转账、余额查询等。
 *         - SafeERC20: 用于安全地处理ERC20代币的转账操作。
 *         - ReentrancyGuard: 用于防止重入攻击的合约。
 *         - ERC20Permit: 允许通过签名进行授权的ERC20代币合约。
 *         - SingleAdminAccessControl: 自定义的权限控制合约，用于控制合约的访问权限。
 *         - IStakedUSDe: 接口，定义了StakedUSDe合约的一些方法。
 *     2）角色：
 *         - REWARDER_ROLE: 允许向合约分发奖励的角色。
 *         - BLACKLIST_MANAGER_ROLE: 允许管理黑名单的角色。
 *         - SOFT_RESTRICTED_STAKER_ROLE: 部分受限制的质押者角色，可以限制质押和转账。
 *         - FULL_RESTRICTED_STAKER_ROLE: 完全受限制的质押者角色，可以完全限制质押、转账和解质押。
 *     3）常量和状态变量：
 *         - vestingAmount: 上一次从控制合约分发到这个合约的资产的金额（包括未解锁的部分）。
 *         - lastDistributionTimestamp: 上一次分发奖励的时间戳。
 *         - VESTING_PERIOD: 上述vestingAmount的解锁周期，这里是8小时。
 *         - MIN_SHARES: 最小的非零份额，用于防止捐赠攻击。
 *     4）函数：
 *         - 构造函数：初始化USDe代币地址、初始奖励分发者和合约的所有者。
 *         - transferInRewards: 允许奖励分发者将奖励从控制合约转移到这个合约中。
 * #audit  - addToBlacklist和removeFromBlacklist: 允许管理员和黑名单管理者将地址添加到或从黑名单中移除。
 *         - rescueTokens: 允许所有者从合约中救回意外发送的代币，但不能救回USDe代币。
 *         - redistributeLockedAmount: 用于从一个完全受限制的地址转移质押的资产到另一个地址。
 *         - totalAssets: 获取合约中总的资产（USDe代币）数量。
 *         - getUnvestedAmount: 获取未解锁的奖励数量。
 *         - _checkMinShares: 检查份额数量，以防止捐赠攻击。
 *         - _deposit和_withdraw: 存款和提现的内部函数。
 *         - _beforeTokenTransfer: 在代币转账之前执行的钩子函数，用于检查转账的有效性。
 *         - renounceRole: 从AccessControl中移除放弃角色的访问权限。
Regenerate

 */
// 控制合约权限、防止重入攻击、 ERC20 支持许可（permit）功能的合约、StakedUSDe的接口
contract StakedUSDe is
    SingleAdminAccessControl,
    ReentrancyGuard,
    ERC20Permit,
    ERC4626,
    IStakedUSDe
{
    using SafeERC20 for IERC20;

    /* ------------- CONSTANTS ------------- */
    /// @notice The role that is allowed to distribute rewards to this contract
    // 分发奖励的角色 REWARDER_ROLE
    bytes32 private constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    /// @notice The role that is allowed to blacklist and un-blacklist addresses
    // 将地址列入黑名单或者移出黑名单的角色
    bytes32 private constant BLACKLIST_MANAGER_ROLE =
        keccak256("BLACKLIST_MANAGER_ROLE");
    /// @notice The role which prevents an address to stake
    // 防止地址进行质押的角色
    bytes32 private constant SOFT_RESTRICTED_STAKER_ROLE =
        keccak256("SOFT_RESTRICTED_STAKER_ROLE");
    /// @notice The role which prevents an address to transfer, stake, or unstake. The owner of the contract can redirect address staking balance if an address is in full restricting mode.
    // 防止地址进行转账、质押或解质押的角色
    bytes32 private constant FULL_RESTRICTED_STAKER_ROLE =
        keccak256("FULL_RESTRICTED_STAKER_ROLE");
    /// @notice The vesting period of lastDistributionAmount over which it increasingly becomes available to stakers
    // 表示 lastDistributionAmount 变量的释放时间的常量
    uint256 private constant VESTING_PERIOD = 8 hours;
    /// @notice Minimum non-zero shares amount to prevent donation attack
    // 防止“捐款攻击”（donation attack）的常量。这个值规定了最小非零份额数量。
    uint256 private constant MIN_SHARES = 1 ether;

    /* ------------- STATE VARIABLES ------------- */

    /// @notice The amount of the last asset distribution from the controller contract into this
    /// contract + any unvested remainder at that time
    // 用于存储来自控制合约的最后一次资产分配金额，以及在那个时候未解锁的剩余部分。
    uint256 public vestingAmount;

    /// @notice The timestamp of the last asset distribution from the controller contract into this contract
    // 用于记录从控制合约分配资产到此合约的最后一次时间戳。
    uint256 public lastDistributionTimestamp;

    /* ------------- MODIFIERS ------------- */

    /// @notice ensure input amount nonzero
    // 确保传入的 amount 参数非零。
    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /// @notice ensures blacklist target is not owner
    // 确保传入的 target 参数不是合约的所有者。
    modifier notOwner(address target) {
        if (target == owner()) revert CantBlacklistOwner();
        _;
    }

    /* ------------- CONSTRUCTOR ------------- */

    /**
     * @notice Constructor for StakedUSDe contract.
     * @param _asset The address of the USDe token. USDe代币的地址。
     * @param _initialRewarder The address of the initial rewarder. 初始奖励人发着的地址
     * @param _owner The address of the admin role. 管理员角色的地址
     *
     */
    constructor(
        // 合约地址、两个地址
        // 初始化 名为 "Staked USDe" 的ERC20代币，符号为 "stUSDe"。
        // _asset，也就是USDe代币的地址。
        // 参数是代币符号 "stUSDe"。
        IERC20 _asset,
        address _initialRewarder,
        address _owner
    ) ERC20("Staked USDe", "stUSDe") ERC4626(_asset) ERC20Permit("stUSDe") {
        // 查_owner、_initialRewarder或_asset是否为零地址
        if (
            _owner == address(0) ||
            _initialRewarder == address(0) ||
            address(_asset) == address(0)
        ) {
            revert InvalidZeroAddress();
        }

        // 授予地址_initialRewarder一个名为REWARDER_ROLE的角色。
        // 授予地址_owner一个名为DEFAULT_ADMIN_ROLE的角色。
        _grantRole(REWARDER_ROLE, _initialRewarder);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /* ------------- EXTERNAL ------------- */

    /**
     * @notice Allows the owner to transfer rewards from the controller contract into this contract.
     * @param amount The amount of rewards to transfer.
     * 允许合约的所有者从控制合约中转移奖励到当前合约中
     */
    function transferInRewards(
        // notZero 检查金额是否为 0
        uint256 amount
    ) external nonReentrant onlyRole(REWARDER_ROLE) notZero(amount) {
        // 检查是否有未归属的奖励。 如果是这样，它会恢复交易，并抛出一个名为 StillVesting 的异常。
        if (getUnvestedAmount() > 0) revert StillVesting();
        // 将提供的金额添加到未归属的金额来计算新的归属金额。
        uint256 newVestingAmount = amount + getUnvestedAmount();

        // 使用新计算的值更新 vestingAmount。
        vestingAmount = newVestingAmount;
        // 使用当前块的时间戳更新lastDistributionTimestamp。
        lastDistributionTimestamp = block.timestamp;
        // transfer assets from rewarder to this contract
        // 使用 IERC20 接口的 safeTransferFrom 函数将指定数量的资产从调用者 (msg.sender) 转移到此合约。
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        // 发出一个事件，指示已收到奖励以及金额和新的归属金额。
        emit RewardsReceived(amount, newVestingAmount);
    }

    /**
     * 所有者 (DEFAULT_ADMIN_ROLE) 和黑名单管理员将地址列入黑名单。
     * @notice Allows the owner (DEFAULT_ADMIN_ROLE) and blacklist managers to blacklist addresses.
     * 黑名单的地址。
     * @param target The address to blacklist. 要列入黑名单的地址
     * @param isFullBlacklisting Soft or full blacklisting level. 软或完全黑名单级别。
     * 检查目标地址是不是所有者
     */
    function addToBlacklist(
        address target,
        bool isFullBlacklisting
    ) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        // 根据条件 isFullBlacklisting 的值来选择不同的角色。
        bytes32 role = isFullBlacklisting
            ? FULL_RESTRICTED_STAKER_ROLE
            : SOFT_RESTRICTED_STAKER_ROLE;
        // 讲确定角色授予给目标地址
        _grantRole(role, target);
    }

    /**
     * @notice 解除黑名单 Allows the owner (DEFAULT_ADMIN_ROLE) and blacklist managers to un-blacklist addresses.
     * @param target  The address to un-blacklist. 要解除黑名单的地址。
     * @param isFullBlacklisting Soft or full blacklisting level. 是否为全面黑名单
     */
    function removeFromBlacklist(
        address target,
        bool isFullBlacklisting
    ) external onlyRole(BLACKLIST_MANAGER_ROLE) notOwner(target) {
        // 要取消黑名单的地址和isFullBlacklisting（指示是软取消黑名单还是完全取消黑名单）。
        bytes32 role = isFullBlacklisting
            ? FULL_RESTRICTED_STAKER_ROLE
            : SOFT_RESTRICTED_STAKER_ROLE;
        // 从目标地址撤销该角色。
        _revokeRole(role, target);
    }

    /**
     * @notice 允许所有者处理意外发送到合约的代币 Allows the owner to rescue tokens accidentally sent to the contract.
     * 处理的不是 应该在这个合约 USDe代币，而是不应该在这个合约里的质押的USDe代币
     * Note that the owner cannot rescue USDe tokens because they functionally sit here
     * and belong to stakers but can rescue staked USDe as they should never actually
     * sit in this contract and a staker may well transfer them here by accident.
     * 要处理的代币、数量、要发送的位置
     * @param token The token to be rescued.
     * @param amount The amount of tokens to be rescued.
     * @param to Where to send rescued tokens
     */
    function rescueTokens(
        address token,
        uint256 amount,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 检查救援的代币是否与合约的主代币相同，如果是，则恢复以防止救援主代币。
        // #audit 这里的 asset()是什么
        if (address(token) == asset()) revert InvalidToken();
        // 将指定数量的代币安全地转移到指定地址。
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Burns the full restricted user amount and mints to the desired owner address. 燃烧黑名单用户的金额并发送到所有者地址
     * @param from The address to burn the entire balance, with the FULL_RESTRICTED_STAKER_ROLE 黑名单地址
     * @param to The address to mint the entire balance of "from" parameter. 所有者地址
     * 销毁全部受限用户余额并将其铸造到所需的所有者地址。
     */
    function redistributeLockedAmount(
        address from,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 检查 from 是否具有 FULL_RESTRICTED_STAKER_ROLE 而 to 是否不具有。
        if (
            hasRole(FULL_RESTRICTED_STAKER_ROLE, from) &&
            !hasRole(FULL_RESTRICTED_STAKER_ROLE, to)
        ) {
            // 计算要分配的金额，销毁 from 的余额，并将其铸成 to 。
            uint256 amountToDistribute = balanceOf(from);
            _burn(from, amountToDistribute);
            // to address of address(0) enables burning
            if (to != address(0)) _mint(to, amountToDistribute);
            // 发出一个事件来记录重新分配。
            emit LockedAmountRedistributed(from, to, amountToDistribute);
        } else {
            revert OperationNotAllowed();
        }
    }

    /* ------------- PUBLIC ------------- */

    /**
     * @notice Returns the amount of USDe tokens that are vested in the contract.
     * 该函数返回了在合约中已经解锁（或者说已经归属于合约）的 USDe 代币总额。
     *    - 已经可以被合约使用或者转移，而不受到任何限制；
     *    - 它们已经经过了特定的锁定期，或者它们是合约创建时预先放入的代币。
     */
    function totalAssets() public view override returns (uint256) {
        // 合约持有的 USDe 代币总额减去尚未解锁的部分。
        return IERC20(asset()).balanceOf(address(this)) - getUnvestedAmount();
    }

    /**
     * @notice Returns the amount of USDe tokens that are unvested in the contract.
     * 计算尚未解锁的 USDe 代币数量
     */
    function getUnvestedAmount() public view returns (uint256) {
        // 上次分发的时间与当前时间的差异以及分发金额进行计算。
        uint256 timeSinceLastDistribution = block.timestamp -
            lastDistributionTimestamp;

        if (timeSinceLastDistribution >= VESTING_PERIOD) {
            return 0;
        }

        return
            ((VESTING_PERIOD - timeSinceLastDistribution) * vestingAmount) /
            VESTING_PERIOD;
    }

    /// @dev Necessary because both ERC20 (from ERC20Permit) and ERC4626 declare decimals()
    // 重写了两个接口中的 decimals() 函数，确定代币的小数位数。，这里是 18。
    function decimals() public pure override(ERC4626, ERC20) returns (uint8) {
        return 18;
    }

    /* ------------- INTERNAL ------------- */

    /// @notice ensures a small non-zero amount of shares does not remain, exposing to donation attack
    // 防止合约中非常少量的非零份额导致的潜在攻击
    function _checkMinShares() internal view {
        // totalSupply() 检索合约中股票的总供应量。
        uint256 _totalSupply = totalSupply();
        // 总供应量是否大于零且小于指定的最小份额 (MIN_SHARES)。
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES)
            revert MinSharesViolation();
    }

    /**
     * @dev Deposit/mint common workflow.
     * @param caller sender of assets
     * @param receiver where to send shares
     * @param assets assets to deposit
     * @param shares shares to mint
     */
    function _deposit(
        // 调用者、接受者、资产数量、股份数量
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        // 首先检查调用者或接收者是否具有 SOFT_RESTRICTED_STAKER_ROLE 角色。
        if (
            hasRole(SOFT_RESTRICTED_STAKER_ROLE, caller) ||
            hasRole(SOFT_RESTRICTED_STAKER_ROLE, receiver)
        ) {
            revert OperationNotAllowed();
        }
        //调用父函数_deposit(...)执行存款操作。
        super._deposit(caller, receiver, assets, shares);
        // 调用 _checkMinShares() 以确保存款后满足最低股份条件。
        _checkMinShares();
    }

    /**
     * @dev Withdraw/redeem common workflow. 提取或赎回资产
     * @param caller tx sender
     * @param receiver where to send assets
     * @param _owner where to burn shares from
     * @param assets asset amount to transfer out
     * @param shares shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        if (
            hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) ||
            hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)
        ) {
            revert OperationNotAllowed();
        }

        super._withdraw(caller, receiver, _owner, assets, shares);
        _checkMinShares();
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning. Disables transfers from or to of addresses with the FULL_RESTRICTED_STAKER_ROLE role.
     * 钩子函数，在执行任何代币转账（包括铸造和销毁）之前被调用。它的作用是禁止具有 FULL_RESTRICTED_STAKER_ROLE 角色的地址之间进行转账。
     */

    function _beforeTokenTransfer(
        // 转账的发起和接收地址
        address from,
        address to,
        uint256
    ) internal virtual override {
        // from 具有 FULL_RESTRICTED_STAKER_ROLE 角色并且 to 不是零地址，
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && to != address(0)) {
            revert OperationNotAllowed();
        }
        // #audit 为什么接收地址不检查是否是零地址
        if (hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
            revert OperationNotAllowed();
        }
    }

    /**
     * @dev Remove renounce role access from AccessControl, to prevent users to resign roles.
     * // 阻止任何地址放弃任何角色
     * #audit 需不需要double check 一下：无论调用者传入了什么参数，函数都会立即引发异常并中止交易。
     *    - 函数接受两个参数，但实际上在这里并没有使用到这两个参数。
     *    - 这是因为在这个实现中，无论传入了什么参数，函数都会按照固定的逻辑执行。
     */
    function renounceRole(bytes32, address) public virtual override {
        revert OperationNotAllowed();
    }
}
