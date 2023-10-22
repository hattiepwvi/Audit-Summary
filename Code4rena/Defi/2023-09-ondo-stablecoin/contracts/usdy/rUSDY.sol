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

 */
pragma solidity 0.8.16;

import "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "contracts/external/openzeppelin/contracts-upgradeable/token/ERC20/IERC20MetadataUpgradeable.sol";
import "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "contracts/external/openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "contracts/external/openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "contracts/usdy/blocklist/BlocklistClientUpgradeable.sol";
import "contracts/usdy/allowlist/AllowlistClientUpgradeable.sol";
import "contracts/sanctions/SanctionsListClientUpgradeable.sol";
import "contracts/interfaces/IUSDY.sol";
import "contracts/rwaOracles/IRWADynamicOracle.sol";

/**
 * @title Interest-bearing ERC20-like token for rUSDY.
 *
 * rUSDY balances are dynamic and represent the holder's share of the underlying USDY
 * controlled by the protocol. To calculate each account's balance, we do
 *
 *   shares[account] * usdyPrice
 *
 * For example, assume that we have:
 *
 *   usdyPrice = 1.05
 *   sharesOf(user1) -> 100
 *   sharesOf(user2) -> 400
 *
 * Therefore:
 *
 *   balanceOf(user1) -> 105 tokens which corresponds 105 rUSDY
 *   balanceOf(user2) -> 420 tokens which corresponds 420 rUSDY
 *
 * Since balances of all token holders change when the price of USDY changes, this
 * token cannot fully implement ERC20 standard: it only emits `Transfer` events
 * upon explicit transfer between holders. In contrast, when total amount of pooled
 * Cash increases, no `Transfer` events are generated: doing so would require emitting
 * an event for each token holder and thus running an unbounded loop.
 * 总结：rUSDY 稳定币及其背后的合约和机制，包括了它与 USDY 的关系、USDY 的背景、rUSDY 的工作原理以及与 Axelar 网关相关的合约。
 *      - 持有 Ondo 的 USDY 的个人可以将其 USDY 代币进行封装，然后获得与封装的 USD 价值成比例的 rUSDY 代币。
 *      - USDY 代表了通证化的银行存款。随着银行存款的利率变化，USDY 随时间变化的价格也会有所变化。
 *      - rUSDY 是 USDY 代币的再平衡变体，类似于其他再平衡代币（如 stETH）。
 *        - 用户可以通过调用合约上的 wrap(uint256) 函数来获取 rUSDY 代币。可以调用 unwrap(uint256) 函数，将他们的 rUSDY 转换为 USDY。
 *        - 单个 USDY 代币的价格随时间变化，而单个 rUSDY 代币的价格始终保持在 1 美元，额外的 rUSDY 代币以利息的形式累积。
 *      - RWADynamicRateOracle 合约用于在链上发布 USDY 的价格演变。
 *      - SourceBridge 和 DestinationBridge 两个合约是用于处理通过 Axelar 网关进行 USDY 或 RWA 代币的桥接的调用的。
 *        - SourceBridge（源链桥接器）： 部署在源链（例如以太坊）上，它将燃烧/销毁支持的桥接代币，并将燃烧后的资产和有效载荷转发到 Axelar 的燃料服务和 Axelar 网关。
 *        - DestinationBridge（目标链桥接器）：部署在目标链上（另一个区块链，比如币安智能链），它要求发起 Axelar 消息传递的地址（源链上的地址）已在接收者合约中注册。一旦通过 Axelar 网关接收到消息，它将被排队，并在获得所需数量的批准后进行处理。
 *          - 根据源链和桥接金额的不同，源链和目标链之间的桥接交易可能需要不同数量的批准（也就是授权）。
 *          - DestinationBridge 合约还实施了一个速率限制，在一段特定的时间内，接收者合约只能铸造一定数量的代币。
 *        - Axelar Gateway（阿克塞勒网关/跨链桥）是一个用于在不同区块链之间进行资产传输和信息传递的工具，它是 Axelar 网络生态系统的一部分。
 *
 * 本合约总结：管理 rUSDY 稳定币（铸造和销毁），实现了与 USDY 之间的兑换
 *       1）变量、事件等：
 *           - 合约继承：初始化合约（Initializable）、上下文合约（ContextUpgradeable）、暂停合约（PausableUpgradeable）等。
 *           - 变量和映射：存储账户的余额、授权信息等。
 *           - 事件：转账和代币铸造。
 *           - 角色权限：管理员、铸造者、暂停者等
 *       2）函数：
 *           - 初始化函数 initialize
 *           - 代币功能：合约实现了 ERC20 标准，包括转账、授权、转账From等功能。
 *           - 代币铸造与销毁：合约支持将 USDY 代币进行铸造（wrap）和销毁（unwrap）操作，实现了 rUSDY 与 USDY 之间的兑换。
 *       3）设计：
 *           - 权限控制：只有特定角色才能执行特定操作
 *           - 框架集成：OpenZeppelin 框架
 *           - 接口调用：合约中通过调用其他合约（如 IRWADynamicOracle 和 IUSDY）来获取价格信息和进行交互。
 */

contract rUSDY is
  Initializable,
  ContextUpgradeable,
  PausableUpgradeable,
  AccessControlEnumerableUpgradeable,
  BlocklistClientUpgradeable,
  AllowlistClientUpgradeable,
  SanctionsListClientUpgradeable,
  IERC20Upgradeable,
  IERC20MetadataUpgradeable
{
  /**
   * @dev rUSDY balances are dynamic and are calculated based on the accounts' shares (USDY)
   * and the the price of USDY. Account shares aren't
   * normalized, so the contract also stores the sum of all shares to calculate
   * each account's token balance which equals to:
   *
   *   shares[account] * usdyPrice
   */
  mapping(address => uint256) private shares;

  /// @dev Allowances are nominated in tokens, not token shares.
  mapping(address => mapping(address => uint256)) private allowances;

  // Total shares in existence
  uint256 private totalShares;

  // Address of the oracle that updates `usdyPrice`
  IRWADynamicOracle public oracle;

  // Address of the USDY token
  IUSDY public usdy;

  // Used to scale up usdy amount -> shares
  uint256 public constant BPS_DENOMINATOR = 10_000;

  // Error when redeeming shares < `BPS_DENOMINATOR`
  error UnwrapTooSmall();

  /// @dev Role based access control roles
  bytes32 public constant USDY_MANAGER_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURN_ROLE");
  bytes32 public constant LIST_CONFIGURER_ROLE =
    keccak256("LIST_CONFIGURER_ROLE");

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address blocklist,
    address allowlist,
    address sanctionsList,
    address _usdy,
    address guardian,
    address _oracle
  ) public virtual initializer {
    __rUSDY_init(blocklist, allowlist, sanctionsList, _usdy, guardian, _oracle);
  }

  function __rUSDY_init(
    address blocklist,
    address allowlist,
    address sanctionsList,
    address _usdy,
    address guardian,
    address _oracle
  ) internal onlyInitializing {
    __BlocklistClientInitializable_init(blocklist);
    __AllowlistClientInitializable_init(allowlist);
    __SanctionsListClientInitializable_init(sanctionsList);
    __rUSDY_init_unchained(_usdy, guardian, _oracle);
  }

  function __rUSDY_init_unchained(
    address _usdy,
    address guardian,
    address _oracle
  ) internal onlyInitializing {
    usdy = IUSDY(_usdy);
    oracle = IRWADynamicOracle(_oracle);
    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(USDY_MANAGER_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(MINTER_ROLE, guardian);
    _grantRole(BURNER_ROLE, guardian);
    _grantRole(LIST_CONFIGURER_ROLE, guardian);
  }

  /**
   * @notice An executed shares transfer from `sender` to `recipient`.
   *
   * @dev emitted in pair with an ERC20-defined `Transfer` event.
   */
  event TransferShares(
    address indexed from,
    address indexed to,
    uint256 sharesValue
  );

  /**
   * @notice An executed `burnShares` request
   *
   * @dev Reports simultaneously burnt shares amount
   * and corresponding rUSDY amount.
   * The shares amount is calculated twice: before and after the burning incurred rebase.
   *
   * @param account holder of the burnt shares
   * @param preRebaseTokenAmount amount of rUSDY the burnt shares (USDY) corresponded to before the burn
   * @param postRebaseTokenAmount amount of rUSDY the burnt shares (USDY) corresponded to after the burn
   * @param sharesAmount amount of burnt shares
   */
  event SharesBurnt(
    address indexed account,
    uint256 preRebaseTokenAmount,
    uint256 postRebaseTokenAmount,
    uint256 sharesAmount
  );

  /**
   * @notice An executed `burnShares` request
   *
   * @dev Reports simultaneously burnt shares amount
   * and corresponding rUSDY amount.
   * The rUSDY amount is calculated twice: before and after the burning incurred rebase.
   *
   * @param account holder of the burnt shares
   * @param tokensBurnt amount of burnt tokens
   */
  event TokensBurnt(address indexed account, uint256 tokensBurnt);

  /**
   * @return the name of the token.
   */
  function name() public pure returns (string memory) {
    return "Rebasing Ondo U.S. Dollar Yield";
  }

  /**
   * @return the symbol of the token, usually a shorter version of the
   * name.
   */
  function symbol() public pure returns (string memory) {
    return "rUSDY";
  }

  /**
   * @return the number of decimals for getting user representation of a token amount.
   */
  function decimals() public pure returns (uint8) {
    return 18;
  }

  /**
   * @return the amount of tokens in existence.
   */
  function totalSupply() public view returns (uint256) {
    return (totalShares * oracle.getPrice()) / (1e18 * BPS_DENOMINATOR);
  }

  /**
   * @return the amount of tokens owned by the `_account`.
   *
   * @dev Balances are dynamic and equal the `_account`'s USDY shares multiplied
   *      by the price of USDY
   */
  function balanceOf(address _account) public view returns (uint256) {
    return (_sharesOf(_account) * oracle.getPrice()) / (1e18 * BPS_DENOMINATOR);
  }

  /**
   * @notice Moves `_amount` tokens from the caller's account to the `_recipient` account.
   *
   * @return a boolean value indicating whether the operation succeeded.
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the caller must have a balance of at least `_amount`.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function transfer(address _recipient, uint256 _amount) public returns (bool) {
    _transfer(msg.sender, _recipient, _amount);
    return true;
  }

  /**
   * @return the remaining number of tokens that `_spender` is allowed to spend
   * on behalf of `_owner` through `transferFrom`. This is zero by default.
   *
   * @dev This value changes when `approve` or `transferFrom` is called.
   */
  function allowance(
    address _owner,
    address _spender
  ) public view returns (uint256) {
    return allowances[_owner][_spender];
  }

  /**
   * @notice Sets `_amount` as the allowance of `_spender` over the caller's tokens.
   *
   * @return a boolean value indicating whether the operation succeeded.
   * Emits an `Approval` event.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function approve(address _spender, uint256 _amount) public returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  /**
   * @notice Moves `_amount` tokens from `_sender` to `_recipient` using the
   * allowance mechanism. `_amount` is then deducted from the caller's
   * allowance.
   *
   * @return a boolean value indicating whether the operation succeeded.
   *
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_sender` and `_recipient` cannot be the zero addresses.
   * - `_sender` must have a balance of at least `_amount`.
   * - the caller must have allowance for `_sender`'s tokens of at least `_amount`.
   * - the contract must not be paused.
   *
   * @dev The `_amount` argument is the amount of tokens, not shares.
   */
  function transferFrom(
    address _sender,
    address _recipient,
    uint256 _amount
  ) public returns (bool) {
    uint256 currentAllowance = allowances[_sender][msg.sender];
    require(currentAllowance >= _amount, "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE");

    _transfer(_sender, _recipient, _amount);
    _approve(_sender, msg.sender, currentAllowance - _amount);
    return true;
  }

  /**
   * @notice Atomically increases the allowance granted to `_spender` by the caller by `_addedValue`.
   *
   * This is an alternative to `approve` that can be used as a mitigation for
   * problems described in:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the the zero address.
   * - the contract must not be paused.
   */
  function increaseAllowance(
    address _spender,
    uint256 _addedValue
  ) public returns (bool) {
    _approve(
      msg.sender,
      _spender,
      allowances[msg.sender][_spender] + _addedValue
    );
    return true;
  }

  /**
   * @notice Atomically decreases the allowance granted to `_spender` by the caller by `_subtractedValue`.
   *
   * This is an alternative to `approve` that can be used as a mitigation for
   * problems described in:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
   * Emits an `Approval` event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `_spender` cannot be the zero address.
   * - `_spender` must have allowance for the caller of at least `_subtractedValue`.
   * - the contract must not be paused.
   */
  function decreaseAllowance(
    address _spender,
    uint256 _subtractedValue
  ) public returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(
      currentAllowance >= _subtractedValue,
      "DECREASED_ALLOWANCE_BELOW_ZERO"
    );
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  /**
   * @return the total amount of shares in existence.
   *
   * @dev The sum of all accounts' shares can be an arbitrary number, therefore
   * it is necessary to store it in order to calculate each account's relative share.
   */
  function getTotalShares() public view returns (uint256) {
    return totalShares;
  }

  /**
   * @return the amount of shares owned by `_account`.
   *
   * @dev This is the equivalent to the amount of USDY wrapped by `_account`.
   */
  function sharesOf(address _account) public view returns (uint256) {
    return _sharesOf(_account);
  }

  /**
   * @return the amount of USDY that corresponds to `_rUSDYAmount` of rUSDY
   */
  function getSharesByRUSDY(
    uint256 _rUSDYAmount
  ) public view returns (uint256) {
    return (_rUSDYAmount * 1e18 * BPS_DENOMINATOR) / oracle.getPrice();
  }

  /**
   * @return the amount of rUSDY that corresponds to `_shares` of usdy.
   */
  function getRUSDYByShares(uint256 _shares) public view returns (uint256) {
    return (_shares * oracle.getPrice()) / (1e18 * BPS_DENOMINATOR);
  }

  /**
   * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
   *
   * @return amount of transferred tokens.
   * Emits a `TransferShares` event.
   * Emits a `Transfer` event.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the caller must have at least `_sharesAmount` shares.
   * - the contract must not be paused.
   *
   * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
   */
  function transferShares(
    address _recipient,
    uint256 _sharesAmount
  ) public returns (uint256) {
    _transferShares(msg.sender, _recipient, _sharesAmount);
    emit TransferShares(msg.sender, _recipient, _sharesAmount);
    uint256 tokensAmount = getRUSDYByShares(_sharesAmount);
    emit Transfer(msg.sender, _recipient, tokensAmount);
    return tokensAmount;
  }

  /**
   * @notice Function called by users to wrap their USDY tokens
   *
   * @param _USDYAmount The amount of USDY Tokens to wrap
   *
   * @dev Sanctions, Blocklist, and Allowlist checks implicit in USDY Transfer
   */
  function wrap(uint256 _USDYAmount) external whenNotPaused {
    require(_USDYAmount > 0, "rUSDY: can't wrap zero USDY tokens");
    _mintShares(msg.sender, _USDYAmount * BPS_DENOMINATOR);
    usdy.transferFrom(msg.sender, address(this), _USDYAmount);
    emit Transfer(address(0), msg.sender, getRUSDYByShares(_USDYAmount));
    emit TransferShares(address(0), msg.sender, _USDYAmount);
  }

  /**
   * @notice Function called by users to unwrap their rUSDY tokens
   *
   * @param _rUSDYAmount The amount of rUSDY to unwrap
   *
   * @dev Sanctions, Blocklist, and Allowlist checks implicit in USDY Transfer
   */
  function unwrap(uint256 _rUSDYAmount) external whenNotPaused {
    require(_rUSDYAmount > 0, "rUSDY: can't unwrap zero rUSDY tokens");
    uint256 usdyAmount = getSharesByRUSDY(_rUSDYAmount);
    if (usdyAmount < BPS_DENOMINATOR) revert UnwrapTooSmall();
    _burnShares(msg.sender, usdyAmount);
    usdy.transfer(msg.sender, usdyAmount / BPS_DENOMINATOR);
    emit TokensBurnt(msg.sender, _rUSDYAmount);
  }

  /**
   * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
   * Emits a `Transfer` event.
   * Emits a `TransferShares` event.
   */
  function _transfer(
    address _sender,
    address _recipient,
    uint256 _amount
  ) internal {
    uint256 _sharesToTransfer = getSharesByRUSDY(_amount);
    _transferShares(_sender, _recipient, _sharesToTransfer);
    emit Transfer(_sender, _recipient, _amount);
    emit TransferShares(_sender, _recipient, _sharesToTransfer);
  }

  /**
   * @notice Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
   *
   * Emits an `Approval` event.
   *
   * Requirements:
   *
   * - `_owner` cannot be the zero address.
   * - `_spender` cannot be the zero address.
   * - the contract must not be paused.
   */
  function _approve(
    address _owner,
    address _spender,
    uint256 _amount
  ) internal whenNotPaused {
    require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
    require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  /**
   * @return the amount of shares owned by `_account`.
   */
  function _sharesOf(address _account) internal view returns (uint256) {
    return shares[_account];
  }

  /**
   * @notice Moves `_sharesAmount` shares from `_sender` to `_recipient`.
   *
   * Requirements:
   *
   * - `_sender` cannot be the zero address.
   * - `_recipient` cannot be the zero address.
   * - `_sender` must hold at least `_sharesAmount` shares.
   * - the contract must not be paused.
   */
  function _transferShares(
    address _sender,
    address _recipient,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_sender != address(0), "TRANSFER_FROM_THE_ZERO_ADDRESS");
    require(_recipient != address(0), "TRANSFER_TO_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(_sender, _recipient, _sharesAmount);

    uint256 currentSenderShares = shares[_sender];
    require(
      _sharesAmount <= currentSenderShares,
      "TRANSFER_AMOUNT_EXCEEDS_BALANCE"
    );

    shares[_sender] = currentSenderShares - _sharesAmount;
    shares[_recipient] = shares[_recipient] + _sharesAmount;
  }

  /**
   * @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
   * @dev This doesn't increase the token total supply.
   *
   * Requirements:
   *
   * - `_recipient` cannot be the zero address.
   * - the contract must not be paused.
   */
  function _mintShares(
    address _recipient,
    uint256 _sharesAmount
  ) internal whenNotPaused returns (uint256) {
    require(_recipient != address(0), "MINT_TO_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(address(0), _recipient, _sharesAmount);

    totalShares += _sharesAmount;

    shares[_recipient] = shares[_recipient] + _sharesAmount;

    return totalShares;

    // Notice: we're not emitting a Transfer event from the zero address here since shares mint
    // works by taking the amount of tokens corresponding to the minted shares from all other
    // token holders, proportionally to their share. The total supply of the token doesn't change
    // as the result. This is equivalent to performing a send from each other token holder's
    // address to `address`, but we cannot reflect this as it would require sending an unbounded
    // number of events.
  }

  /**
   * @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
   * @dev This doesn't decrease the token total supply.
   *
   * Requirements:
   *
   * - `_account` cannot be the zero address.
   * - `_account` must hold at least `_sharesAmount` shares.
   * - the contract must not be paused.
   */
  function _burnShares(
    address _account,
    uint256 _sharesAmount
  ) internal whenNotPaused returns (uint256) {
    require(_account != address(0), "BURN_FROM_THE_ZERO_ADDRESS");

    _beforeTokenTransfer(_account, address(0), _sharesAmount);

    uint256 accountShares = shares[_account];
    require(_sharesAmount <= accountShares, "BURN_AMOUNT_EXCEEDS_BALANCE");

    uint256 preRebaseTokenAmount = getRUSDYByShares(_sharesAmount);

    totalShares -= _sharesAmount;

    shares[_account] = accountShares - _sharesAmount;

    uint256 postRebaseTokenAmount = getRUSDYByShares(_sharesAmount);

    emit SharesBurnt(
      _account,
      preRebaseTokenAmount,
      postRebaseTokenAmount,
      _sharesAmount
    );

    return totalShares;

    // Notice: we're not emitting a Transfer event to the zero address here since shares burn
    // works by redistributing the amount of tokens corresponding to the burned shares between
    // all other token holders. The total supply of the token doesn't change as the result.
    // This is equivalent to performing a send from `address` to each other token holder address,
    // but we cannot reflect this as it would require sending an unbounded number of events.

    // We're emitting `SharesBurnt` event to provide an explicit rebase log record nonetheless.
  }

  /**
   * @dev Hook that is called before any transfer of tokens. This includes
   * minting and burning.
   *
   * Calling conditions:
   *
   * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
   * will be transferred to `to`.
   * - when `from` is zero, `amount` tokens will be minted for `to`.
   * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
   * - `from` and `to` are never both zero.
   *
   * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256
  ) internal view {
    // Check constraints when `transferFrom` is called to facliitate
    // a transfer between two parties that are not `from` or `to`.
    if (from != msg.sender && to != msg.sender) {
      require(!_isBlocked(msg.sender), "rUSDY: 'sender' address blocked");
      require(!_isSanctioned(msg.sender), "rUSDY: 'sender' address sanctioned");
      require(
        _isAllowed(msg.sender),
        "rUSDY: 'sender' address not on allowlist"
      );
    }

    if (from != address(0)) {
      // If not minting
      require(!_isBlocked(from), "rUSDY: 'from' address blocked");
      require(!_isSanctioned(from), "rUSDY: 'from' address sanctioned");
      require(_isAllowed(from), "rUSDY: 'from' address not on allowlist");
    }

    if (to != address(0)) {
      // If not burning
      require(!_isBlocked(to), "rUSDY: 'to' address blocked");
      require(!_isSanctioned(to), "rUSDY: 'to' address sanctioned");
      require(_isAllowed(to), "rUSDY: 'to' address not on allowlist");
    }
  }

  /**
   * @notice Sets the Oracle address
   * @dev The new oracle must comply with the `IPricerReader` interface
   * @param _oracle Address of the new oracle
   */
  function setOracle(address _oracle) external onlyRole(USDY_MANAGER_ROLE) {
    oracle = IRWADynamicOracle(_oracle);
  }

  /**
   * @notice Admin burn function to burn rUSDY tokens from any account
   * @param _account The account to burn tokens from
   * @param _amount  The amount of rUSDY tokens to burn
   * @dev Transfers burned shares (USDY) to `msg.sender`
   */
  function burn(
    address _account,
    uint256 _amount
  ) external onlyRole(BURNER_ROLE) {
    uint256 sharesAmount = getSharesByRUSDY(_amount);

    _burnShares(_account, sharesAmount);

    usdy.transfer(msg.sender, sharesAmount / BPS_DENOMINATOR);

    emit TokensBurnt(_account, _amount);
  }

  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(USDY_MANAGER_ROLE) {
    _unpause();
  }

  /**
   * @notice Sets the blocklist address
   *
   * @param blocklist New blocklist address
   */
  function setBlocklist(
    address blocklist
  ) external override onlyRole(LIST_CONFIGURER_ROLE) {
    _setBlocklist(blocklist);
  }

  /**
   * @notice Sets the allowlist address
   *
   * @param allowlist New allowlist address
   */
  function setAllowlist(
    address allowlist
  ) external override onlyRole(LIST_CONFIGURER_ROLE) {
    _setAllowlist(allowlist);
  }

  /**
   * @notice Sets the sanctions list address
   *
   * @param sanctionsList New sanctions list address
   */
  function setSanctionsList(
    address sanctionsList
  ) external override onlyRole(LIST_CONFIGURER_ROLE) {
    _setSanctionsList(sanctionsList);
  }
}
