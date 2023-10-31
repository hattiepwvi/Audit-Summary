// SPDX-License-Identifier: MIT
// Disclaimer https://github.com/hats-finance/hats-contracts/blob/main/DISCLAIMER.md
/**
 * @title 总结：提供工厂模式用于创建支付分配器的实例
 *             - 支付分配器可以用于将收款转发到多个地址，并按照预先定义的份额分配给每个收款人。
 * @author
 * @notice
 */

pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./HATPaymentSplitter.sol";

contract HATPaymentSplitterFactory {
    address public immutable implementation;
    event HATPaymentSplitterCreated(address indexed _hatPaymentSplitter);

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function createHATPaymentSplitter(
        address[] memory _payees,
        uint256[] memory _shares
    ) external returns (address result) {
        result = Clones.cloneDeterministic(
            implementation,
            keccak256(abi.encodePacked(_payees, _shares))
        );
        HATPaymentSplitter(payable(result)).initialize(_payees, _shares);
        emit HATPaymentSplitterCreated(result);
    }

    function predictSplitterAddress(
        address[] memory _payees,
        uint256[] memory _shares
    ) public view returns (address) {
        return
            Clones.predictDeterministicAddress(
                implementation,
                keccak256(abi.encodePacked(_payees, _shares))
            );
    }
}
