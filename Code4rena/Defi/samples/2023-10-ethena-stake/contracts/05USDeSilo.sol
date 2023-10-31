// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/interfaces/IUSDeSiloDefinitions.sol";

/**
 * 总结：USDeSilo 的Solidity智能合约，用于在 USDe 代币的质押冷却过程中存储这些代币。
        - 在质押的冷却过程中提供一个临时存储机制，以便在冷却期结束后用户可以取回他们的质押资产。
 *    1）变量：
 *         - STAKING_VAULT 和 USDE：这两个变量都是不可变的地址，分别用于存储质押的合约地址和 USDe 代币的合约地址。
 *    2）函数：
 *         - 构造函数两个参数：stakingVault（用于存储质押的合约地址）和 usde（USDe代币的合约地址）。
 *         - onlyStakingVault 修饰器：确保只有 STAKING_VAULT 地址可以调用标记了该修饰器的函数。
 *         - withdraw 函数：允许 STAKING_VAULT 地址从 USDE 合约中提取指定数量的代币，并将它们发送到指定的地址。
 * @title USDeSilo
 * @notice The Silo allows to store USDe during the stake cooldown process.
 * // Silo 合约允许在质押冷却过程中存储 USDe。
 */
contract USDeSilo is IUSDeSiloDefinitions {
    using SafeERC20 for IERC20;

    // 用于存储质押的合约地址 和 USDe 代币的地址）
    address immutable STAKING_VAULT;
    IERC20 immutable USDE;

    constructor(address stakingVault, address usde) {
        STAKING_VAULT = stakingVault;
        USDE = IERC20(usde);
    }

    // 只有 STAKING_VAULT 地址才能调用
    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    // 将指定数量的 USDe 代币发送到指定地址。
    function withdraw(address to, uint256 amount) external onlyStakingVault {
        USDE.transfer(to, amount);
    }
}
