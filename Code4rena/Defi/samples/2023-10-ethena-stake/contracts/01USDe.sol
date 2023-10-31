// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./interfaces/IUSDeDefinitions.sol";

/**
 * @title USDe
 * @notice Stable Coin Contract
 * @dev Only a single approved minter can mint new tokens
 * 总结：USDe 稳定币合约
 *     #audit 1） 只有一个经过批准的铸币者（minter）可以铸造新的代币。
 *            2) 继承关系：
 *                - ERC20
 *                - ERC20Burnable：提供了销毁（烧毁）代币的功能。
 *                - ERC20Permit：提供了符合许可（permit）功能的 ERC20 接口。
 *                - 拥有者管理：Ownable2Step 合约
 *            3）函数：
 *                - 构造函数：参数 admin，在部署合约时会将调用者设为拥有者，符号为 "USDe"，并开启许可功能。
 *                - setMinter 函数：设置铸造者
 *                   - 只有拥有者（onlyOwner）可以调用此函数。
 *                   - 函数用于更新 minter 地址，即可以铸造新代币的地址。
 *                - mint 函数：铸造代币并发送到指定地址
 *                   - 只有当前的 minter 地址可以调用此函数。
 *     #audit     - renounceOwnership 函数：
 *                   - 这个函数被覆盖了，并在其中抛出了一个异常，意味着拥有者无法放弃所有权。
 */
contract USDe is Ownable2Step, ERC20Burnable, ERC20Permit, IUSDeDefinitions {
    address public minter;

    constructor(address admin) ERC20("USDe", "USDe") ERC20Permit("USDe") {
        if (admin == address(0)) revert ZeroAddressException();
        // 将合约的所有权转移给了 admin 地址。
        _transferOwnership(admin);
    }

    function setMinter(address newMinter) external onlyOwner {
        // 用于设置可以进行铸造操作的新地址。只有合约所有者才能调用此函数。
        emit MinterUpdated(newMinter, minter);
        minter = newMinter;
    }

    function mint(address to, uint256 amount) external {
        // 用于铸造新的代币并将其发送到指定地址。
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    function renounceOwnership() public view override onlyOwner {
        // 重写了基类的函数。它禁止了合约所有者放弃所有权的操作。
        revert CantRenounceOwnership();
    }
}
