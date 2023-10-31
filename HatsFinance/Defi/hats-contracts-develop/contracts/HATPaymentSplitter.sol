// SPDX-License-Identifier: MIT
// Disclaimer https://github.com/hats-finance/hats-contracts/blob/main/DISCLAIMER.md

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "./tokenlock/ITokenLock.sol";

/**
 * @title 总结：分配支付的合约模板
 * @author    1）初始化后，合约就可以开始接收支付并按照设定的份额分发给收款人。
 *            2）释放 token => 提取多余的 token =>  清理意外发送的 token
 * @notice
 */

contract HATPaymentSplitter is PaymentSplitterUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _payees,
        uint256[] memory _shares
    ) external initializer {
        __PaymentSplitter_init(_payees, _shares);
    }

    /**
     * @notice Releases tokens from a tokenlock contract
     * @param _tokenLock The tokenlock to release from
     */
    function releaseFromTokenLock(ITokenLock _tokenLock) external {
        _tokenLock.release();
    }

    /**
     * @notice Withdraws surplus, unmanaged tokens from a tokenlock contract
     * @param _tokenLock The tokenlock to withdraw surplus from
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawSurplusFromTokenLock(
        ITokenLock _tokenLock,
        uint256 _amount
    ) external {
        _tokenLock.withdrawSurplus(_amount);
    }

    /**
     * @notice Sweeps out accidentally sent tokens from a tokenlock contract
     * @param _tokenLock The tokenlock to call sweepToken on
     * @param _token Address of token to sweep
     */
    function sweepTokenFromTokenLock(
        ITokenLock _tokenLock,
        IERC20 _token
    ) external {
        _tokenLock.sweepToken(_token);
    }
}
