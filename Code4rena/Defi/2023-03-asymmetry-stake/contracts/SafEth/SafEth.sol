// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/lido/IWStETH.sol";
import "../interfaces/lido/IstETH.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./SafEthStorage.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title Contract that mints/burns and provides owner functions for safETH
/// @author Asymmetry Finance
/**
 * 1、总结：SafEth合约的主要功能是将以太币（ETH）存入合约，并以safETH的形式发行给存款人。存款的ETH将被分配到不同的衍生品（derivatives）中，每个衍生品都有一个权重（weight）。
 * @author
 * @notice
 */
// Initializable 可升级合约
contract SafEth is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    SafEthStorage
{
    event ChangeMinAmount(uint256 indexed minAmount);
    event ChangeMaxAmount(uint256 indexed maxAmount);
    event StakingPaused(bool indexed paused);
    event UnstakingPaused(bool indexed paused);
    event SetMaxSlippage(uint256 indexed index, uint256 slippage);
    event Staked(address indexed recipient, uint ethIn, uint safEthOut);
    event Unstaked(address indexed recipient, uint ethOut, uint safEthIn);
    event WeightChange(uint indexed index, uint weight);
    event DerivativeAdded(
        address indexed contractAddress,
        uint weight,
        uint index
    );
    event Rebalanced();

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    // 使用 OpenZeppelin 的升级插件时，需要在合约中添加一个用于禁用合约的初始化函数（initializers）的特殊的构造函数。在合约升级时，就不会再次调用合约的初始化函数。
    // 总结：合约升级时禁止初始化函数
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _tokenName - name of erc20
        @param _tokenSymbol - symbol of erc20
        这个 initialize 函数用于初始化合约的状态和变量，替代了传统的构造函数。这样，在合约升级时，可以保留之前部署合约的状态和数据。
        总结：初始化就是设置代币的名称和符号、转移合约的所有权、可升级合约要保留之前的数据所以不用传统的构造函数。
    */
    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol
    ) external initializer {
        // 调用了 ERC20Upgradeable 合约的 __ERC20_init 函数，用于设置 ERC20 代币的名称和符号。
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);
        // 调用 _transferOwnership 函数，将合约的所有权转移给部署合约的地址
        _transferOwnership(msg.sender);
        minAmount = 5 * 10 ** 17; // initializing with .5 ETH as minimum
        maxAmount = 200 * 10 ** 18; // initializing with 200 ETH as maximum
    }

    /**
        @notice - Stake your ETH into safETH
        @dev - Deposits into each derivative based on its weight
        @dev - Mints safEth in a redeemable value which equals to the correct percentage of the total staked value
        总以太币价值 / 总供应量 = 每个价格  => 质押的总以太币价值 / 每个价格 = 质押的总供应量
        underlyingValue 包括了所有衍生品的价值，而 totalStakeValueEth 仅包括了用户在质押操作后所质押的衍生品的总价值。
        1）计算每种衍生品（derivative）的以太币价值，并将它们相加以得到总的以太币价值 underlyingValue。
        2）如果总供应量为零，将 每个safETH 的价格 preDepositPrice 设置为 1（表示每个 safETH 的价格为 1 以太币）；否则，计算 preDepositPrice = 总的以太币价值/供应量。
        3）根据衍生品的权重来确定每个衍生品应该存款的以太币数量。
        4）计算所有质押的衍生品总共价值多少以太币 totalStakeValueEth。
        5）计算用户应该获得的新的 safETH 数量 mintAmount


    */
    function stake() external payable {
        // 防止在暂停时进行质押操作
        require(pauseStaking == false, "staking is paused");
        require(msg.value >= minAmount, "amount too low");
        require(msg.value <= maxAmount, "amount too high");

        uint256 underlyingValue = 0;

        // Getting underlying value in terms of ETH for each derivative
        // 计算每种衍生品（derivative）的以太币价值，并将它们相加以得到总的以太币价值。
        for (uint i = 0; i < derivativeCount; i++)
            underlyingValue +=
                (derivatives[i].ethPerDerivative(derivatives[i].balance()) *
                    derivatives[i].balance()) /
                10 ** 18;

        // 计算当前 safETH 的总供应量。
        uint256 totalSupply = totalSupply();
        uint256 preDepositPrice; // Price of safETH in regards to ETH
        // 如果总供应量为零，将 preDepositPrice 设置为 1（表示每个 safETH 的价格为 1 以太币）；否则，计算 preDepositPrice。
        if (totalSupply == 0)
            preDepositPrice = 10 ** 18; // initializes with a price of 1
        else preDepositPrice = (10 ** 18 * underlyingValue) / totalSupply;

        uint256 totalStakeValueEth = 0; // total amount of derivatives worth of ETH in system
        for (uint i = 0; i < derivativeCount; i++) {
            uint256 weight = weights[i];
            IDerivative derivative = derivatives[i];
            // 如果条件为真，即weight等于0，那么跳过当前循环的剩余代码，继续下一个循环。
            if (weight == 0) continue;
            // 根据衍生品的权重来确定每个衍生品应该存款的以太币数量。
            uint256 ethAmount = (msg.value * weight) / totalWeight;

            // This is slightly less than ethAmount because slippage
            // 计算系统中所有衍生品的总价值 totalStakeValueEth
            // 计算过程中，会根据权重分配质押金额，并调用 derivative.deposit() 函数进行质押。
            // 将以太币存入衍生品合约，并返回存款的数量。
            uint256 depositAmount = derivative.deposit{value: ethAmount}();
            // 根据每个衍生品的以太币价值和存款数量来确定实际接收到的以太币价值。
            // 计算每种衍生品需要质押的以太币数量
            uint derivativeReceivedEthValue = (derivative.ethPerDerivative(
                depositAmount
            ) * depositAmount) / 10 ** 18;
            // 所有衍生品存款的总以太币价值。
            totalStakeValueEth += derivativeReceivedEthValue;
        }
        // mintAmount represents a percentage of the total assets in the system
        // mintAmount 即质押者将获得的代币数量 = 总的以太币价值 / 每个衍生品的预存价格
        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;
        // 调用 _mint() 函数，将质押者获得的代币数量 mintAmount 分配给质押者
        _mint(msg.sender, mintAmount);
        // 触发 Staked 事件，记录质押者的地址、质押的金额和获得的代币数量。
        emit Staked(msg.sender, msg.value, mintAmount);
    }

    /**
        @notice - Unstake your safETH into ETH
        @dev - unstakes a percentage of safEth based on its total value
        @param _safEthAmount - amount of safETH to unstake into ETH
        目的：解压的衍生品总数 => 解压的每个衍生品的总数：转回以太币，销毁衍生品
        1）根据用户希望解质押的 safETH 数量 _safEthAmount，计算出相应的每个衍生品数量 derivativeAmount
        2）对每种衍生品进行解质押操作，将相应的数量转回以太币。
        3）从用户账户中销毁相应的 safETH 数量 _safEthAmount。
    */
    function unstake(uint256 _safEthAmount) external {
        require(pauseUnstaking == false, "unstaking is paused");
        uint256 safEthTotalSupply = totalSupply();
        uint256 ethAmountBefore = address(this).balance;

        // 根据用户希望解质押的 safETH 数量 _safEthAmount，计算出相应的衍生品数量 derivativeAmount
        for (uint256 i = 0; i < derivativeCount; i++) {
            // withdraw a percentage of each asset based on the amount of safETH
            // （衍生品合约的余额 * _safEthAmount）/ safEthTotalSupply。
            // 这个计算的结果是根据每个衍生品在总safETH供应中所占的比例，确定应该提取的衍生品数量。
            uint256 derivativeAmount = (derivatives[i].balance() *
                _safEthAmount) / safEthTotalSupply;
            if (derivativeAmount == 0) continue; // if derivative empty ignore
            // 对每种衍生品进行解质押操作，将相应的数量转回以太币。
            derivatives[i].withdraw(derivativeAmount);
        }
        _burn(msg.sender, _safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        require(sent, "Failed to send Ether");
        emit Unstaked(msg.sender, ethAmountToWithdraw, _safEthAmount);
    }

    /**
        @notice - Rebalance each derivative to resemble the weight set for it
        @dev - Withdraws all derivative and re-deposit them to have the correct weights
        @dev - Depending on the balance of the derivative this could cause bad slippage
        @dev - If weights are updated then it will slowly change over time to the correct weight distribution
        @dev - Probably not going to be used often, if at all
        合约所有者可以通过调用rebalanceToWeights()函数重新平衡各个衍生品的权重。
        总结：把所有的衍生品的余额都取出来了之后，再按照事先约定的权重给每个衍生品存入相应权重的 eth
    */
    function rebalanceToWeights() external onlyOwner {
        uint256 ethAmountBefore = address(this).balance;
        for (uint i = 0; i < derivativeCount; i++) {
            if (derivatives[i].balance() > 0)
                derivatives[i].withdraw(derivatives[i].balance());
        }
        uint256 ethAmountAfter = address(this).balance;
        // 需要重新平衡的以太币数量 == 提取的该衍生品的全部余额
        // 当某个衍生品的余额大于零时，说明该衍生品的价值超过了预设的权重比例（为什么不是提取一部分？）
        uint256 ethAmountToRebalance = ethAmountAfter - ethAmountBefore;

        for (uint i = 0; i < derivativeCount; i++) {
            if (weights[i] == 0 || ethAmountToRebalance == 0) continue;
            uint256 ethAmount = (ethAmountToRebalance * weights[i]) /
                totalWeight;
            // Price will change due to slippage
            derivatives[i].deposit{value: ethAmount}();
        }
        emit Rebalanced();
    }

    /**
        @notice - Adds new derivative to the index fund
        @dev - Weights are only in regards to each other, total weight changes with this function
        @dev - If you want exact weights either do the math off chain or reset all existing derivates to the weights you want
        @dev - Weights are approximate as it will slowly change as people stake
        @param _derivativeIndex - index of the derivative you want to update the weight
        @param _weight - new weight for this derivative.
        合约所有者还可以通过调用adjustWeight()函数调整每个衍生品的权重
    */
    function adjustWeight(
        uint256 _derivativeIndex,
        uint256 _weight
    ) external onlyOwner {
        weights[_derivativeIndex] = _weight;
        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit WeightChange(_derivativeIndex, _weight);
    }

    /**
        @notice - Adds new derivative to the index fund
        @param _contractAddress - Address of the derivative contract launched by AF
        @param _weight - new weight for this derivative. 
    */
    function addDerivative(
        address _contractAddress,
        uint256 _weight
    ) external onlyOwner {
        // 将衍生品的合约地址转换为IDerivative接口，并将其存储在derivatives数组中的索引位置derivativeCount处
        derivatives[derivativeCount] = IDerivative(_contractAddress);
        weights[derivativeCount] = _weight;
        derivativeCount++;

        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit DerivativeAdded(_contractAddress, _weight, derivativeCount);
    }

    /**
        @notice - Sets the max slippage for a certain derivative index
        @param _derivativeIndex - index of the derivative you want to update the slippage
        @param _slippage - new slippage amount in wei
        设置最大滑点（setMaxSlippage()）、设置最小存款金额（setMinAmount()）、设置最大存款金额（setMaxAmount()）等。
    */
    function setMaxSlippage(
        uint _derivativeIndex,
        uint _slippage
    ) external onlyOwner {
        // 滑点（Slippage）是指在进行交易时，实际成交价格与预期价格之间的差异。这种差异可能是由于市场流动性不足、交易量较大或市场波动等因素引起的。
        derivatives[_derivativeIndex].setMaxSlippage(_slippage);
        emit SetMaxSlippage(_derivativeIndex, _slippage);
    }

    /**
        @notice - Sets the minimum amount a user is allowed to stake
        @param _minAmount - amount to set as minimum stake value
    */
    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
        emit ChangeMinAmount(minAmount);
    }

    /**
        @notice - Owner only function that sets the maximum amount a user is allowed to stake
        @param _maxAmount - amount to set as maximum stake value
    */
    function setMaxAmount(uint256 _maxAmount) external onlyOwner {
        maxAmount = _maxAmount;
        emit ChangeMaxAmount(maxAmount);
    }

    /**
        @notice - Owner only function that Enables/Disables the stake function
        @param _pause - true disables staking / false enables staking
    */
    // 用于暂停或恢复质押（staking）功能
    function setPauseStaking(bool _pause) external onlyOwner {
        pauseStaking = _pause;
        emit StakingPaused(pauseStaking);
    }

    /**
        @notice - Owner only function that enables/disables the unstake function
        @param _pause - true disables unstaking / false enables unstaking
    */
    function setPauseUnstaking(bool _pause) external onlyOwner {
        pauseUnstaking = _pause;
        emit UnstakingPaused(pauseUnstaking);
    }

    receive() external payable {}
}
