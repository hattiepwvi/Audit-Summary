// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

/**
 * solhint-disable private-vars-leading-underscore
 */

import "./SingleAdminAccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IUSDe.sol";
import "./interfaces/IEthenaMinting.sol";

/**
 * @title Ethena Minting
 * @notice This contract mints and redeems USDe in a single, atomic, trustless transaction
 * 总结：EthenaMinting 的智能合约在单个交易中铸造（mint）和赎回（redeem）稳定币 USDe
 *      1）角色：铸币者（MINTER_ROLE）、赎回者（REDEEMER_ROLE）和门卫（GATEKEEPER_ROLE）。
 *      2）继承关系：
 * #audit   - SingleAdminAccessControl：提供了单一管理员访问控制功能。
 *          - ReentrancyGuard：用于避免重入攻击的保护机制。
 *          -  SafeERC20 和 ECDSA
 *      3) 状态变量：
 *          - usde: 一个代表 USDe 稳定币的合约地址。
 *          - _supportedAssets: 一个存储支持的资产地址的集合。
 *          - _custodianAddresses: 一个存储托管地址的集合。
 *          - _chainId 和 _domainSeparator: 用于 EIP712 域的计算。
 *          - _orderBitmaps: 用于用户订单去重的映射。
 *      4) 函数：
 *          - 构造函数：usde 合约地址、资产地址、托管地址、管理员地址以及最大铸造和最大赎回限额。
 *          - external:
 *              - mint: 铸造稳定币，通过验证订单和签名，并将资产转移给铸造者。
 *              - redeem: 赎回稳定币，通过验证订单和签名，并将资产转移给赎回者。
 *          - public:
 *              - addSupportedAsset、addCustodianAddress：添加支持的资产和托管地址。
 *              - removeSupportedAsset、removeCustodianAddress：移除支持的资产和托管地址。
 *              - 其他函数用于设置最大铸造/赎回限额、禁用铸造和赎回等。
 *          - internal:
 *              _deduplicateOrder：防止订单的重复处理。
 *              _transferToBeneficiary、_transferCollateral：资产转移的辅助函数。
 *      5) 事件：
 *          - 铸造、赎回、资产转移等。
 *
 */
// 继承： 接口合约、控制访问权限的合约、避免重入攻击的合约库
contract EthenaMinting is
    IEthenaMinting,
    SingleAdminAccessControl,
    ReentrancyGuard
{
    // SafeERC20 库用于安全地处理 ERC20 代币的转账和操作
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* --------------- CONSTANTS --------------- */

    /// @notice EIP712 domain
    bytes32 private constant EIP712_DOMAIN =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// @notice route type
    bytes32 private constant ROUTE_TYPE =
        keccak256("Route(address[] addresses,uint256[] ratios)");

    /// @notice order type
    bytes32 private constant ORDER_TYPE =
        keccak256(
            "Order(uint8 order_type,uint256 expiry,uint256 nonce,address benefactor,address beneficiary,address collateral_asset,uint256 collateral_amount,uint256 usde_amount)"
        );

    // minter铸币、redeemer赎回、gatekeeper紧急情况禁用铸币和赎回，以及移除铸币者和赎回者。
    /// @notice role enabling to invoke mint
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice role enabling to invoke redeem
    bytes32 private constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");

    /// @notice role enabling to disable mint and redeem and remove minters and redeemers in an emergency
    bytes32 private constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice EIP712 domain hash
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256(abi.encodePacked(EIP712_DOMAIN));

    /// @notice address denoting native ether
    address private constant NATIVE_TOKEN =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice EIP712 name
    bytes32 private constant EIP_712_NAME = keccak256("EthenaMinting");

    /// @notice holds EIP712 revision
    bytes32 private constant EIP712_REVISION = keccak256("1");

    /* --------------- STATE VARIABLES --------------- */

    /// @notice usde stablecoin
    // 稳定币的合约地址。
    IUSDe public usde;

    /// @notice Supported assets
    // 支持的资产集合，使用 EnumerableSet 库来管理。
    EnumerableSet.AddressSet internal _supportedAssets;

    // 托管地址集合，也使用 EnumerableSet 库来管理。
    // @notice custodian addresses
    EnumerableSet.AddressSet internal _custodianAddresses;

    /// @notice holds computable chain id
    // 存储当前链的 ID。
    uint256 private immutable _chainId;

    /// @notice holds computable domain separator
    // 用于 EIP712 签名的域分隔符。
    bytes32 private immutable _domainSeparator;

    /// @notice user deduplication
    // 用于记录用户在合约中的某种状态或者授权信息。
    mapping(address => mapping(uint256 => uint256)) private _orderBitmaps;

    /// @notice USDe minted per block
    // 用于记录每个区块中产生的某种代币（可能是 USDe）的数量。
    mapping(uint256 => uint256) public mintedPerBlock;
    // 用于记录每个区块中赎回（兑换）的代币数量。
    /// @notice USDe redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    // 允许一个智能合约代理另一个地址进行签名的情况。
    /// @notice For smart contracts to delegate signing to EOA address
    mapping(address => mapping(address => bool)) public delegatedSigner;

    /// @notice max minted USDe allowed per block
    // 每个区块内允许最大的产生（铸造）代币数量。
    uint256 public maxMintPerBlock;
    /// @notice max redeemed USDe allowed per block
    // 每个区块内允许最大的赎回（兑换）代币数量。
    uint256 public maxRedeemPerBlock;

    /* --------------- MODIFIERS --------------- */

    /// @notice ensure that the already minted USDe in the actual block plus the amount to be minted is below the maxMintPerBlock var
    /// @param mintAmount The USDe amount to be minted
    modifier belowMaxMintPerBlock(uint256 mintAmount) {
        // #audit 当前区块内产生的 USDe 数量 + 即将产生的数量 不超过 maxMintPerBlock（每个区块内最大允许产生的 USDe 数量）。
        if (mintedPerBlock[block.number] + mintAmount > maxMintPerBlock)
            revert MaxMintPerBlockExceeded();
        _;
    }

    /// @notice ensure that the already redeemed USDe in the actual block plus the amount to be redeemed is below the maxRedeemPerBlock var
    /// @param redeemAmount The USDe amount to be redeemed
    modifier belowMaxRedeemPerBlock(uint256 redeemAmount) {
        // #audit 当前区块内赎回的 USDe 数量 + 即将赎回的数量 不超过 maxRedeemPerBlock（每个区块内最大允许赎回的 USDe 数量）。
        if (redeemedPerBlock[block.number] + redeemAmount > maxRedeemPerBlock)
            revert MaxRedeemPerBlockExceeded();
        _;
    }

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        // _used 合约地址、资产动态数组、保管人动态数组、管理员、每个区块内最大允许产生、赎回的 USDe 数量
        IUSDe _usde,
        address[] memory _assets,
        address[] memory _custodians,
        address _admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    ) {
        // _usde 的地址是零地址、资产数组长度为零、管理员地址是零地址、
        if (address(_usde) == address(0)) revert InvalidUSDeAddress();
        if (_assets.length == 0) revert NoAssetsProvided();
        if (_admin == address(0)) revert InvalidZeroAddress();
        usde = _usde;

        // 授予调用者（部署合约的账户）默认管理员角色（DEFAULT_ADMIN_ROLE）
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < _assets.length; i++) {
            // #audit(函数写在这个里面，如果合约升级的话会不会有影响) 循环遍历提供的资产数组，并将每个资产添加到支持的资产列表中。
            addSupportedAsset(_assets[i]);
        }

        for (uint256 j = 0; j < _custodians.length; j++) {
            // 循环遍历提供的保管人地址数组，并将每个地址添加到保管人地址列表中。
            addCustodianAddress(_custodians[j]);
        }

        // Set the max mint/redeem limits per block
        // 用提供的 _maxMintPerBlock 参数设置每个区块内最大允许产生的 USDe 数量。
        _setMaxMintPerBlock(_maxMintPerBlock);
        // 用提供的 _maxRedeemPerBlock 参数设置每个区块内最大允许赎回的 USDe 数量。
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);

        // 如果部署合约的账户不是管理员账户，则将 _admin 赋予默认管理员角色。
        if (msg.sender != _admin) {
            _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        }

        _chainId = block.chainid;
        // _computeDomainSeparator 函数来计算域分隔符（domain separator）
        _domainSeparator = _computeDomainSeparator();

        // 发射一个事件（event）USDeSet，将 _usde 的地址作为参数传递。
        emit USDeSet(address(_usde));
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Fallback function to receive ether
     */
    receive() external payable {
        // 回退函数（fallback function），当合约接收到以太币时会自动执行。
        // 事件 Received，记录发送者地址和接收到的以太币数量。
        emit Received(msg.sender, msg.value);
    }

    /**
     * @notice Mint stablecoins from assets
     * @param order struct containing order details and confirmation from server
     * @param signature signature of the taker
     */
    function mint(
        // 三个输入参数：order、route 和 signature，都是结构体类型（Order、Route 和 Signature）。
        // 避免重入攻击。
        // belowMaxMintPerBlock(order.usde_amount) 确保每个区块内产生的 USDe 数量不超过预先设定的最大值。
        Order calldata order,
        Route calldata route,
        Signature calldata signature
    )
        external
        override
        nonReentrant
        onlyRole(MINTER_ROLE)
        belowMaxMintPerBlock(order.usde_amount)
    {
        // 检查订单类型，如果不是铸造（MINT）类型的订单，就抛出一个异常 InvalidOrder()。
        if (order.order_type != OrderType.MINT) revert InvalidOrder();
        // 调用 verifyOrder 函数来验证订单的合法性。
        verifyOrder(order, signature);
        // 验证交易路径的合法性。
        if (!verifyRoute(route, order.order_type)) revert InvalidRoute();
        // 调用 _deduplicateOrder 函数来确保订单不会被重复处理
        if (!_deduplicateOrder(order.benefactor, order.nonce))
            revert Duplicate();
        // Add to the minted amount in this block
        // 将产生的 USDe 数量加到当前区块的产生总量中。
        mintedPerBlock[block.number] += order.usde_amount;
        // 调用 _transferCollateral 函数来处理资产的转移。
        _transferCollateral(
            order.collateral_amount,
            order.collateral_asset,
            order.benefactor,
            route.addresses,
            route.ratios
        );
        // 调用 usde 合约的 mint 函数来铸造稳定币，并将铸造的 USDe 发送给接收者。
        usde.mint(order.beneficiary, order.usde_amount);
        // 发射一个名为 Mint 的事件，记录铸造的相关信息。
        emit Mint(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.usde_amount
        );
    }

    /**
     * @notice Redeem stablecoins for assets
     * @param order struct containing order details and confirmation from server
     * @param signature signature of the taker
     */
    function redeem(
        Order calldata order,
        Signature calldata signature
    )
        external
        override
        nonReentrant
        onlyRole(REDEEMER_ROLE)
        belowMaxRedeemPerBlock(order.usde_amount)
    {
        // 不是赎回（REDEEM）类型的订单，就抛出一个异常
        if (order.order_type != OrderType.REDEEM) revert InvalidOrder();
        // verifyOrder 函数来验证订单的合法性。
        verifyOrder(order, signature);
        // 确保订单不会被重复处理
        if (!_deduplicateOrder(order.benefactor, order.nonce))
            revert Duplicate();
        // Add to the redeemed amount in this block
        // 将赎回的 USDe 数量加到当前区块的赎回总量中。
        redeemedPerBlock[block.number] += order.usde_amount;
        // 调用 usde 合约的 burnFrom 函数来销毁相应数量的 USDe 代币。
        usde.burnFrom(order.benefactor, order.usde_amount);
        // 调用 _transferToBeneficiary 函数来将相应的资产转移到接收者的地址。
        _transferToBeneficiary(
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount
        );
        // 发射一个名为 Redeem 的事件，记录赎回的相关信息。
        emit Redeem(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.usde_amount
        );
    }

    /// @notice Sets the max mintPerBlock limit
    // 设置每个区块内最大允许产生（铸造）的 USDe 数量。
    function setMaxMintPerBlock(
        uint256 _maxMintPerBlock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxMintPerBlock(_maxMintPerBlock);
    }

    // 设置每个区块内最大允许产生（赎回）的 USDe 数量。
    /// @notice Sets the max redeemPerBlock limit
    function setMaxRedeemPerBlock(
        uint256 _maxRedeemPerBlock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /// @notice Disables the mint and redeem
    // 禁用铸造（Mint）和赎回（Redeem）功能，将最大铸造和赎回限额都设置为零。
    function disableMintRedeem() external onlyRole(GATEKEEPER_ROLE) {
        _setMaxMintPerBlock(0);
        _setMaxRedeemPerBlock(0);
    }

    /// @notice Enables smart contracts to delegate an address for signing
    // 讲签名委托给另一个地址，_delegateTo 表示委托的目标地址。
    function setDelegatedSigner(address _delegateTo) external {
        // 将_delegateTo地址下的msg.sender（调用此函数的账户）设置为可代理签名的状态
        // 换句话说，允许msg.sender代表_delegateTo进行签名操作。
        delegatedSigner[_delegateTo][msg.sender] = true;
        // 一个地址已经被授权代表另一个地址进行签名操作。事件参数包括被授权的地址_delegateTo和执行此操作的地址msg.sender。
        emit DelegatedSignerAdded(_delegateTo, msg.sender);
    }

    /// @notice Enables smart contracts to undelegate an address for signing
    // 取消委托给另一个地址进行签名。
    function removeDelegatedSigner(address _removedSigner) external {
        // 将_removedSigner地址下的msg.sender（调用此函数的账户）的代理签名状态设置为false
        // 换句话说，不再允许msg.sender代表_removedSigner进行签名操作。
        delegatedSigner[_removedSigner][msg.sender] = false;
        // 一个地址不再被授权代表另一个地址进行签名操作。事件参数包括被取消授权的地址_removedSigner和执行此操作的地址msg.sender。
        emit DelegatedSignerRemoved(_removedSigner, msg.sender);
    }

    /// @notice transfers an asset to a custody wallet
    // 将资产转移到一个托管钱包
    function transferToCustody(
        // 托管钱包的地址、资产地址、要转移的资产数量
        address wallet,
        address asset,
        uint256 amount
    ) external nonReentrant onlyRole(MINTER_ROLE) {
        // 检查 wallet 是否是有效地址
        if (wallet == address(0) || !_custodianAddresses.contains(wallet))
            revert InvalidAddress();
        // 如果 asset 是本地代币（原生代币），则使用 call 函数将指定数量的以太币转移到 wallet 地址
        if (asset == NATIVE_TOKEN) {
            (bool success, ) = wallet.call{value: amount}("");
            //如果转移失败，抛出异常。
            if (!success) revert TransferFailed();
        } else {
            // 如果 asset 不是本地代币，它将使用 IERC20 接口调用 safeTransfer 函数将相应数量的代币转移到 wallet 地址。
            IERC20(asset).safeTransfer(wallet, amount);
        }
        // CustodyTransfer 的事件，它通知区块链网络有资产转移到了托管钱包。
        // 事件包括了托管钱包的地址 wallet、资产的地址 asset 和转移的数量 amount。
        emit CustodyTransfer(wallet, asset, amount);
    }

    /// @notice Removes an asset from the supported assets list
    // 从支持的资产列表中移除一个资产。
    // asset：要移除的资产的地址。
    function removeSupportedAsset(
        address asset
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 检查调用者是否有 DEFAULT_ADMIN_ROLE 角色，如果没有则抛出异常。
        // #audit 尝试从支持的资产列表中移除指定的 asset。
        // 如果移除操作失败，抛出异常。
        if (!_supportedAssets.remove(asset)) revert InvalidAssetAddress();
        // 通知区块链网络某个资产已经从支持列表中移除。事件参数包括被移除的资产地址 asset。
        emit AssetRemoved(asset);
    }

    /// @notice Checks if an asset is supported.
    // 检查一个资产是否在支持的资产列表中。
    // asset：要检查的资产的地址。
    function isSupportedAsset(address asset) external view returns (bool) {
        return _supportedAssets.contains(asset);
    }

    /// @notice Removes an custodian from the custodian address list
    // 从托管地址列表中移除一个托管者。
    // custodian：要移除的托管者的地址。
    function removeCustodianAddress(
        address custodian
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // #audit 这里有移除的操作吗？同理前面有添加的操作吗？
        if (!_custodianAddresses.remove(custodian))
            revert InvalidCustodianAddress();
        // 通知区块链网络某个托管者已经从托管地址列表中移除。事件参数包括被移除的托管者地址 custodian。
        emit CustodianAddressRemoved(custodian);
    }

    /// @notice Removes the minter role from an account, this can ONLY be executed by the gatekeeper role
    /// @param minter The address to remove the minter role from
    // 从 MINTER_ROLE 中移除一个账户的 minter 角色。
    // 确保调用者拥有 GATEKEEPER_ROLE 角色
    function removeMinterRole(
        address minter
    ) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
    }

    /// @notice Removes the redeemer role from an account, this can ONLY be executed by the gatekeeper role
    /// @param redeemer The address to remove the redeemer role from
    // 从 REDEEMER_ROLE 中移除 redeemer
    function removeRedeemerRole(
        address redeemer
    ) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(REDEEMER_ROLE, redeemer);
    }

    /* --------------- PUBLIC --------------- */

    /// @notice Adds an asset to the supported assets list.
    // 将 asset 资产添加到支持列表
    function addSupportedAsset(
        address asset
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // 如果资产是零地址或者已经存在于列表中，或者 _supportedAssets.add(asset) 操作失败，就会抛出异常。
        // AssetAdded 的事件，通知区块链网络某个资产已经被添加到支持列表中。
        if (
            asset == address(0) ||
            asset == address(usde) ||
            !_supportedAssets.add(asset)
        ) {
            revert InvalidAssetAddress();
        }
        emit AssetAdded(asset);
    }

    /// @notice Adds an custodian to the supported custodians list.
    // 将托管者地址添加到支持的托管者列表中。
    function addCustodianAddress(
        address custodian
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // 如果地址是零地址或者已经存在于列表中，或者 _custodianAddresses.add(custodian) 操作失败，就会抛出异常。
        if (
            custodian == address(0) ||
            custodian == address(usde) ||
            !_custodianAddresses.add(custodian)
        ) {
            revert InvalidCustodianAddress();
        }
        emit CustodianAddressAdded(custodian);
    }

    /// @notice Get the domain separator for the token
    /// @dev Return cached value if chainId matches cache, otherwise recomputes separator, to prevent replay attack across forks
    /// @return The domain separator of the token at current chain
    // 获取代币的域分隔符（Domain Separator）。
    function getDomainSeparator() public view returns (bytes32) {
        // 如果当前块的链ID（block.chainid）等于缓存的链ID（_chainId），则返回缓存的域分隔符。否则，重新计算域分隔符并返回。
        if (block.chainid == _chainId) {
            return _domainSeparator;
        }
        return _computeDomainSeparator();
    }

    /// @notice hash an Order struct
    // 计算一个订单结构的哈希值。
    function hashOrder(
        Order calldata order
    ) public view override returns (bytes32) {
        return
            ECDSA.toTypedDataHash(
                getDomainSeparator(),
                keccak256(encodeOrder(order))
            );
    }

    // 将一个订单结构编码为字节数组。
    // order 是一个 Order 结构体，而后面的成员是该结构体中的属性。
    // 如果 order 的属性依次为 1, 1000000, 12345, 0x123..., 0x456..., 0x789..., 1000, 5000, 2000，那么 encodeOrder 函数会将这些参数编码成一个字节数组，并将其作为返回值。
    function encodeOrder(
        Order calldata order
    ) public pure returns (bytes memory) {
        return
            abi.encode(
                ORDER_TYPE,
                order.order_type,
                order.expiry,
                order.nonce,
                order.benefactor,
                order.beneficiary,
                order.collateral_asset,
                order.collateral_amount,
                order.usde_amount
            );
    }

    // 将一个名为 Route 的数据结构编码成一个字节数组。
    // route.addresses 和 route.ratios 分别是 Route 结构体中的两个属性。
    // 这个编码后的字节数组可以用于在合约中传递和存储路由信息。
    function encodeRoute(
        Route calldata route
    ) public pure returns (bytes memory) {
        return abi.encode(ROUTE_TYPE, route.addresses, route.ratios);
    }

    /// @notice assert validity of signed order
    // 验证一个已签名的订单的有效性： 订单、签名
    function verifyOrder(
        Order calldata order,
        Signature calldata signature
    ) public view override returns (bool, bytes32) {
        // 将订单信息转化成一个唯一的哈希值。
        bytes32 taker_order_hash = hashOrder(order);
        // 使用 ECDSA 签名恢复函数，根据哈希值和签名数据，得到签名者的地址。
        address signer = ECDSA.recover(
            taker_order_hash,
            signature.signature_bytes
        );
        // 检查签名者是否是订单的 benefactor（受益者）或者是否被允许代表 benefactor 进行签名。
        if (
            !(signer == order.benefactor ||
                delegatedSigner[signer][order.benefactor])
        ) revert InvalidSignature();
        // 检查订单的抵押物数量是否为零
        if (order.beneficiary == address(0)) revert InvalidAmount();
        // 检查订单的受益者是否为空地址
        if (order.collateral_amount == 0) revert InvalidAmount();
        // 检查订单的USDE数量是否为零
        if (order.usde_amount == 0) revert InvalidAmount();
        // 检查当前时间是否超过订单的截止日期
        if (block.timestamp > order.expiry) revert SignatureExpired();
        return (true, taker_order_hash);
    }

    /// @notice assert validity of route object per type
    // 验证一个名为 Route 的数据结构在特定类型 orderType 的订单中是否有效。
    // route：一个名为 Route 的数据结构，包含了一系列的地址和比例。
    // orderType：一个表示订单类型的枚举值，可能是 OrderType.MINT 或 OrderType.REDEEM。
    function verifyRoute(
        Route calldata route,
        OrderType orderType
    ) public view override returns (bool) {
        // routes only used to mint
        // 如果订单类型是 REDEEM，则无需验证，直接返回 true。
        if (orderType == OrderType.REDEEM) {
            return true;
        }
        // 声明一个名为 totalRatio 的整数变量，并初始化为零。
        uint256 totalRatio = 0;
        // 检查地址和比例数组的长度是否相等，如果不相等，返回 false。
        if (route.addresses.length != route.ratios.length) {
            return false;
        }
        // 检查地址数组的长度是否为零，如果是，返回 false。
        if (route.addresses.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < route.addresses.length; ++i) {
            // 每次迭代中，检查当前地址是否在托管地址列表中，且不为零地址，同时检查对应的比例是否大于零。
            if (
                !_custodianAddresses.contains(route.addresses[i]) ||
                route.addresses[i] == address(0) ||
                route.ratios[i] == 0
            ) {
                return false;
            }
            // 累加当前比例到 totalRatio 中。
            totalRatio += route.ratios[i];
        }
        // 检查累加的比例总和是否等于 10000（这里假设比例是以整数表示的百分比）。
        if (totalRatio != 10_000) {
            return false;
        }
        return true;
    }

    /// @notice verify validity of nonce by checking its presence
    // 验证一个 nonce（用于识别唯一订单的数字） 是否有效；sender 调用者地址
    // 返回一个布尔值和三个整数。
    function verifyNonce(
        address sender,
        uint256 nonce
    ) public view override returns (bool, uint256, uint256, uint256) {
        // 零通常被用于表示一个无效的 nonce。
        if (nonce == 0) revert InvalidNonce();
        // 通过将 nonce 向右移动8位，获取一个 invalidatorSlot，这将被用于在 _orderBitmaps 中查找相应的无效标记。
        uint256 invalidatorSlot = uint64(nonce) >> 8;
        // 将1左移 nonce 的最低8位，得到一个用于标记特定 nonce 的比特位。
        uint256 invalidatorBit = 1 << uint8(nonce);
        // 获取 _orderBitmaps 中与调用者地址相关的映射，该映射用于存储订单的无效标记。
        mapping(uint256 => uint256) storage invalidatorStorage = _orderBitmaps[
            sender
        ];
        // 从映射中获取与当前 nonce 相关的无效标记。
        uint256 invalidator = invalidatorStorage[invalidatorSlot];
        // 检查是否已经在存储中标记了相应的 nonce。如果已经标记了，抛出 InvalidNonce 异常。
        if (invalidator & invalidatorBit != 0) revert InvalidNonce();

        return (true, invalidatorSlot, invalidator, invalidatorBit);
    }

    /* --------------- PRIVATE --------------- */

    /// @notice deduplication of taker order
    // 用于确保订单的 nonce 是唯一的，以避免订单的重放攻击。
    function _deduplicateOrder(
        address sender,
        uint256 nonce
    ) private returns (bool) {
        (
            // 调用名为 verifyNonce 的函数来验证 nonce 的有效性，并同时获取一些与 nonce 相关的信息。
            bool valid,
            uint256 invalidatorSlot,
            uint256 invalidator,
            uint256 invalidatorBit
        ) = verifyNonce(sender, nonce);
        // 获取 _orderBitmaps 映射中与调用者地址相关的映射，该映射用于存储订单的无效标记。
        mapping(uint256 => uint256) storage invalidatorStorage = _orderBitmaps[
            sender
        ];
        // #audit 什么是按位或运算？
        // 在 invalidatorStorage 中更新相应的无效标记，将之前的标记与当前订单的 nonce 位进行按位或运算，以记录已经使用过的 nonce。
        invalidatorStorage[invalidatorSlot] = invalidator | invalidatorBit;
        // 函数返回 valid，表示 nonce 是否验证通过。
        return valid;
    }

    /* --------------- INTERNAL --------------- */

    /// @notice transfer supported asset to beneficiary address
    // 将支持的资产（可能是以太币或其他代币）转移给指定的受益人地址。
    function _transferToBeneficiary(
        address beneficiary,
        address asset,
        uint256 amount
    ) internal {
        // 首先检查资产是否是本地的原生代币（例如以太币）。
        if (asset == NATIVE_TOKEN) {
            // 如果是原生代币，合约会检查自身的余额是否足够支付指定的数量，如果不足，将抛出 InvalidAmount 异常。
            if (address(this).balance < amount) revert InvalidAmount();
            // 通过 call{value: amount}("") 语句将指定数量的原生代币发送给受益人地址。这里使用了 call 来执行这个操作。
            (bool success, ) = (beneficiary).call{value: amount}("");
            // 如果发送过程中失败（success 不为 true），将抛出 TransferFailed 异常。
            if (!success) revert TransferFailed();
        } else {
            // 如果资产不是原生代币，表示它是一个 ERC20 代币。
            // 函数将检查该资产是否被合约支持，如果不支持，将抛出 UnsupportedAsset 异常。
            if (!_supportedAssets.contains(asset)) revert UnsupportedAsset();
            // 通过 IERC20(asset).safeTransfer(beneficiary, amount) 语句将指定数量的 ERC20 代币发送给受益人地址。
            IERC20(asset).safeTransfer(beneficiary, amount);
        }
    }

    /// @notice transfer supported asset to array of custody addresses per defined ratio
    // 按照事先定义的比例，将支持的资产转移给一组托管地址。
    // 资产的数量、地址、提供者地址、托管地址的数组、与托管地址对应的转移比例数组
    function _transferCollateral(
        uint256 amount,
        address asset,
        address benefactor,
        address[] calldata addresses,
        uint256[] calldata ratios
    ) internal {
        // cannot mint using unsupported asset or native ETH even if it is supported for redemptions
        // 检查资产是否受合约支持，并且不是原生代币（ETH）。
        if (!_supportedAssets.contains(asset) || asset == NATIVE_TOKEN)
            revert UnsupportedAsset();
        // 创建一个指向资产的 ERC20 接口的实例，以便进行后续的 ERC20 操作。
        IERC20 token = IERC20(asset);
        // 总共转移的资产数量。
        uint256 totalTransferred = 0;
        for (uint256 i = 0; i < addresses.length; ++i) {
            // 计算要转移给当前地址的资产数量，根据定义的比例计算。
            uint256 amountToTransfer = (amount * ratios[i]) / 10_000;
            // 从提供者地址将资产安全地转移到当前托管地址。
            token.safeTransferFrom(benefactor, addresses[i], amountToTransfer);
            // 累加已转移的资产数量。
            totalTransferred += amountToTransfer;
        }
        // 计算剩余的资产数量。
        uint256 remainingBalance = amount - totalTransferred;
        // 如果还有剩余的资产，将其转移到托管地址数组中的最后一个地址。
        if (remainingBalance > 0) {
            token.safeTransferFrom(
                benefactor,
                addresses[addresses.length - 1],
                remainingBalance
            );
        }
    }

    /// @notice Sets the max mintPerBlock limit
    // #audit: 手动输入数据靠谱吗？，先事件再赋值？
    function _setMaxMintPerBlock(uint256 _maxMintPerBlock) internal {
        // 先将旧的最大铸造限额保存在变量 oldMaxMintPerBlock 中
        uint256 oldMaxMintPerBlock = maxMintPerBlock;
        // 然后将新的限额 _maxMintPerBlock 赋值给 maxMintPerBlock。
        maxMintPerBlock = _maxMintPerBlock;
        // MaxMintPerBlockChanged 的事件，记录了最大铸造限额的变化。
        emit MaxMintPerBlockChanged(oldMaxMintPerBlock, maxMintPerBlock);
    }

    /// @notice Sets the max redeemPerBlock limit
    // 设置最大每区块赎回限制。
    function _setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) internal {
        uint256 oldMaxRedeemPerBlock = maxRedeemPerBlock;
        maxRedeemPerBlock = _maxRedeemPerBlock;
        // 事件通知，表示最大赎回限制已经被更改，并提供了旧值和新值。
        emit MaxRedeemPerBlockChanged(oldMaxRedeemPerBlock, maxRedeemPerBlock);
    }

    /// @notice Compute the current domain separator
    /// @return The domain separator for the token
    // EIP712_DOMAIN 是 EIP-712标准中的域、合约的名称、合约的版本号、当前区块的链ID（用于确保计算的domain separator在不同链上是唯一的。）、当前合约的地址
    // 将这些数据编码为一个字节数组，并将其作为输入传递给keccak256函数 => 得到一个唯一的domain separator值。
    function _computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN,
                    EIP_712_NAME,
                    EIP712_REVISION,
                    block.chainid,
                    address(this)
                )
            );
    }
}
