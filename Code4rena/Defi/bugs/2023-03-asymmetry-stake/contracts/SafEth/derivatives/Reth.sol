// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/rocketpool/RocketDAOProtocolSettingsDepositInterface.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/uniswap/IUniswapV3Factory.sol";
import "../../interfaces/uniswap/IUniswapV3Pool.sol";

/// @title Derivative contract for rETH
/// @author Asymmetry Finance
/**
 * 1、合约目的
 * 1）获取 pool 中目标代币的价格 Reth
 * 2）检查是否能像 pool 中存款/流动性质押: 能存款后获得 Reth, 或不能存款后兑换成 Reth
 * @author
 * @notice
 */
contract Reth is IDerivative, Initializable, OwnableUpgradeable {
    address public constant ROCKET_STORAGE_ADDRESS =
        0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    address public constant W_ETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant UNI_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which handles stake/unstake
    */
    function initialize(address _owner) external initializer {
        _transferOwnership(_owner);
        maxSlippage = (1 * 10 ** 16); // 1%
    }

    /**
        @notice - Return derivative name
    */
    function name() public pure returns (string memory) {
        return "RocketPool";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(uint256 _slippage) external onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Get rETH address
        @dev - per RocketPool Docs query addresses each time it is used
     */
    function rethAddress() private view returns (address) {
        // 从 RocketStorageInterface 合约中获取一个特定的地址，用于获取一个名为 "rocketTokenRETH" 的合约地址
        return
            RocketStorageInterface(ROCKET_STORAGE_ADDRESS).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
    }

    /**
        @notice - Swap tokens through Uniswap
        @param _tokenIn - token to swap from
        @param _tokenOut - token to swap to
        @param _poolFee - pool fee for particular swap
        @param _amountIn - amount of token to swap from
        @param _minOut - minimum amount of token to receive (slippage)
     */
    function swapExactInputSingleHop(
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amountIn,
        uint256 _minOut
    ) private returns (uint256 amountOut) {
        // 定义了一个名为 params 的结构体变量，用于存储交易的详细信息，包括输入代币、输出代币、手续费、接收者地址、输入代币数量、最小输出代币数量和价格限制。
        IERC20(_tokenIn).approve(UNISWAP_ROUTER, _amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _poolFee,
                recipient: address(this),
                amountIn: _amountIn,
                amountOutMinimum: _minOut,
                sqrtPriceLimitX96: 0
            });
        amountOut = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
    }

    /**
        @notice - Convert derivative into ETH
     */
    function withdraw(uint256 amount) external onlyOwner {
        RocketTokenRETHInterface(rethAddress()).burn(amount);
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    /**
        @notice - Check whether or not rETH deposit pool has room users amount
        @param _amount - amount that will be deposited
     */
    function poolCanDeposit(uint256 _amount) private view returns (bool) {
        // 通过 ROCKET_STORAGE_ADDRESS 地址获取 rocketDepositPoolAddress 地址后，实例化该地址的合约
        // 通过 ROCKET_STORAGE_ADDRESS 地址获取 rocketDAOProtocolSettingsDeposit 地址后，实例化该地址的合约
        // 存款池的余额加上用户尝试存入的 _amount 不能超过设定的最大存款池大小, 不能小于最小存款池的大小。

        address rocketDepositPoolAddress = RocketStorageInterface(
            ROCKET_STORAGE_ADDRESS
        ).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );

        address rocketProtocolSettingsAddress = RocketStorageInterface(
            ROCKET_STORAGE_ADDRESS
        ).getAddress(
                keccak256(
                    abi.encodePacked(
                        "contract.address",
                        "rocketDAOProtocolSettingsDeposit"
                    )
                )
            );
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(
                rocketProtocolSettingsAddress
            );

        return
            rocketDepositPool.getBalance() + _amount <=
            rocketDAOProtocolSettingsDeposit.getMaximumDepositPoolSize() &&
            _amount >= rocketDAOProtocolSettingsDeposit.getMinimumDeposit();
    }

    /**
        @notice - Deposit into derivative
        @dev - will either get rETH on exchange or deposit into contract depending on availability
        目的：如果能存款/流动性质押就将以太币存入rocketDepositPool 的合约，并兑换或者铸造 rETH； 如果不能存款就将以太币存入当前智能合约并进行交易兑换成 rETH 
     */
    function deposit() external payable onlyOwner returns (uint256) {
        // Per RocketPool Docs query addresses each time it is used
        address rocketDepositPoolAddress = RocketStorageInterface(
            ROCKET_STORAGE_ADDRESS
        ).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            );

        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );

        // 使用 poolCanDeposit 函数来检查是否可以将以太币存入池中。
        // 如果无法存款
        if (!poolCanDeposit(msg.value)) {
            // 计算 rETH 对 ETH 的兑换比率 rethPerEth。
            uint rethPerEth = (10 ** 36) / poolPrice();

            // 计算最小输出量 minOut，用于确保在进行兑换时不会超过最大滑点（maxSlippage）。
            uint256 minOut = ((((rethPerEth * msg.value) / 10 ** 18) *
                ((10 ** 18 - maxSlippage))) / 10 ** 18);

            // 使用 IWETH 接口的 deposit 函数将以太币存入合约，并获取相应的 WETH。
            IWETH(W_ETH_ADDRESS).deposit{value: msg.value}();
            // 使用 swapExactInputSingleHop 函数进行一次性兑换，将 WETH 兑换成 rETH。
            uint256 amountSwapped = swapExactInputSingleHop(
                W_ETH_ADDRESS,
                rethAddress(),
                500,
                msg.value,
                minOut
            );

            return amountSwapped;
            // 如果可以存款
        } else {
            address rocketTokenRETHAddress = RocketStorageInterface(
                ROCKET_STORAGE_ADDRESS
            ).getAddress(
                    keccak256(
                        abi.encodePacked("contract.address", "rocketTokenRETH")
                    )
                );
            RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
                rocketTokenRETHAddress
            );
            // 获取当前合约中持有的 rETH 余额 (rethBalance1)
            uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
            // 调用 rocketDepositPool 合约的 deposit 函数，将以太币存入合约
            rocketDepositPool.deposit{value: msg.value}();
            // 获取存款后当前合约中持有的 rETH 余额 (rethBalance2)。
            uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
            // 确保新的余额比旧的余额要大，以确保 rETH 已经被铸造。
            require(rethBalance2 > rethBalance1, "No rETH was minted");
            uint256 rethMinted = rethBalance2 - rethBalance1;
            return (rethMinted);
        }
    }

    /**
        @notice - Get price of derivative in terms of ETH
        @dev - we need to pass amount so that it gets price from the same source that it buys or mints the rEth
        @param _amount - amount to check for ETH price
        目的：如果能存款，将目标代币的价格转换为以太币的单位
     */
    function ethPerDerivative(uint256 _amount) public view returns (uint256) {
        // 如果可以存款，它将调用名为 rethAddress 的函数来获取 rocketTokenRETH 的合约地址。
        // 接着，它调用 RocketTokenRETHInterface 合约的 getEthValue 函数，传入 10 ** 18 作为参数，以将价格转换为以太币的单位。。
        if (poolCanDeposit(_amount))
            return
                RocketTokenRETHInterface(rethAddress()).getEthValue(10 ** 18);
        else return (poolPrice() * 10 ** 18) / (10 ** 18);
        // 如果不能存款，它会调用 poolPrice 函数来获取当前 Uniswap V3 池的价格。乘以 10 ** 18 以将价格转换为以太币的单位
    }

    /**
        @notice - Total derivative balance
     */
    function balance() public view returns (uint256) {
        return IERC20(rethAddress()).balanceOf(address(this));
    }

    /**
        @notice - Price of derivative in liquidity pool
        目的：获取池中目标代币的价格
        1）500是用来指定池子的特定权重，权重决定了价格在价格曲线上的分布情况。
           - Uniswap V3使用了一种称为集中定价器（Concentrated Liquidity）的机制来创建池子。这种机制允许用户在价格曲线的特定区域提供流动性，而不是整个价格范围。
           - 池子是Uniswap中的核心概念： 用户可以将两种不同的代币存入池子中，以便供其他用户进行交易。
        2）slot0函数返回一个包含池子的状态信息的结构体，其中包括当前的价格
        3）sqrtPriceX96乘以自身的无符号整数值，并乘以1e18（表示10的18次方）。然后，它将结果右移96 * 2位
           - 乘以其自身的无符号整数值，乘以1e18，即10的18次方。这样做的目的是将价格值进行放大，以便更好地表示较小的小数部分。
           - 移位操作是为了将结果恢复到原来的范围
     */
    function poolPrice() private view returns (uint256) {
        address rocketTokenRETHAddress = RocketStorageInterface(
            ROCKET_STORAGE_ADDRESS
        ).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
        IUniswapV3Factory factory = IUniswapV3Factory(UNI_V3_FACTORY);
        IUniswapV3Pool pool = IUniswapV3Pool(
            factory.getPool(rocketTokenRETHAddress, W_ETH_ADDRESS, 500)
        );
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        return (sqrtPriceX96 * (uint(sqrtPriceX96)) * (1e18)) >> (96 * 2);
    }

    receive() external payable {}
}
