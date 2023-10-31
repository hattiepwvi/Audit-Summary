// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC5313.sol";
import "./interfaces/ISingleAdminAccessControl.sol";

/**
 * @title SingleAdminAccessControl
 * @notice SingleAdminAccessControl is a contract that provides a single admin role
 * @notice This contract is a simplified alternative to OpenZeppelin's AccessControlDefaultAdminRules
 * 总结：SingleAdminAccessControl 的Solidity智能合约，它提供了一种简化的管理员角色控制机制，允许合约拥有一个单一的管理员
 *      - 管理员可以进行一些重要操作，如授权和撤销角色、转让管理员角色等。
 *      1）继承：IERC5313 接口和 ISingleAdminAccessControl 抽象合约
 *      2）变量：
 *            - _currentDefaultAdmin：当前的默认管理员地址。
 *            - _pendingDefaultAdmin：正在等待成为默认管理员的地址。
 *            - 修饰器：notAdmin：确保调用者不是默认管理员，用于限制某些操作的执行。
 *      3）函数：
 *            - transferAdmin：用于将管理员角色转让给新的地址，只能由当前管理员调用。
 *            - acceptAdmin：用于接受成为新的默认管理员。
 *            - grantRole 和 revokeRole：授权和撤销角色的操作，但只能由当前的默认管理员执行。
 *            - renounceRole：放弃某个角色，但不能放弃默认管理员角色。
 *            - owner 函数：返回当前的默认管理员地址。
 *            - _grantRole 函数：在授权角色时进行了扩展，用于处理默认管理员角色的转让。
 */

// 继承了 IERC5313、ISingleAdminAccessControl 和 AccessControl。
abstract contract SingleAdminAccessControl is
    IERC5313,
    ISingleAdminAccessControl,
    AccessControl
{
    // 两个私有的地址变量 _currentDefaultAdmin 和 _pendingDefaultAdmin。
    address private _currentDefaultAdmin;
    address private _pendingDefaultAdmin;

    // 在指定的 role 不是默认管理员时才执行函数。
    modifier notAdmin(bytes32 role) {
        if (role == DEFAULT_ADMIN_ROLE) revert InvalidAdminChange();
        _;
    }

    /// @notice Transfer the admin role to a new address
    /// @notice This can ONLY be executed by the current admin
    /// @param newAdmin address
    function transferAdmin(
        address newAdmin
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 只能由当前的默认管理员调用，将管理员角色转移给一个新的地址。
        if (newAdmin == msg.sender) revert InvalidAdminChange();
        _pendingDefaultAdmin = newAdmin;
        emit AdminTransferRequested(_currentDefaultAdmin, newAdmin);
    }

    // 由待定的新管理员调用，接受管理员职责。
    function acceptAdmin() external {
        if (msg.sender != _pendingDefaultAdmin) revert NotPendingAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice grant a role
    /// @notice can only be executed by the current single admin
    /// @notice admin role cannot be granted externally
    /// @param role bytes32
    /// @param account address
    // 用于授予某个角色给指定的账户。它只能由当前的默认管理员调用，并且不能用于授予管理员角色。
    function grantRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _grantRole(role, account);
    }

    /// @notice revoke a role
    /// @notice can only be executed by the current admin
    /// @notice admin role cannot be revoked
    /// @param role bytes32
    /// @param account address
    // 撤销某个账户的某个角色。只能由当前的默认管理员调用，也不能用于撤销管理员角色。
    function revokeRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) notAdmin(role) {
        _revokeRole(role, account);
    }

    /// @notice renounce the role of msg.sender
    /// @notice admin role cannot be renounced
    /// @param role bytes32
    /// @param account address
    // 允许一个账户放弃特定的角色（#audit 放弃调用者自己的角色？）。不能用于放弃管理员角色。
    function renounceRole(
        bytes32 role,
        address account
    ) public virtual override notAdmin(role) {
        super.renounceRole(role, account);
    }

    /**
     * @dev See {IERC5313-owner}.
     * // 返回当前的默认管理员的地址。
     */
    function owner() public view virtual returns (address) {
        return _currentDefaultAdmin;
    }

    /**
     * // 用于授予角色、转让管理员角色
     * @notice no way to change admin without removing old admin first
     *
     */
    function _grantRole(bytes32 role, address account) internal override {
        if (role == DEFAULT_ADMIN_ROLE) {
            // 触发一个事件 AdminTransferred，表示管理员角色已经转移。
            emit AdminTransferred(_currentDefaultAdmin, account);
            // 调用 _revokeRole 函数来撤销之前的管理员角色。
            _revokeRole(DEFAULT_ADMIN_ROLE, _currentDefaultAdmin);
            // 将 _currentDefaultAdmin 更新为新的管理员账户 account。
            _currentDefaultAdmin = account;
            // 删除 _pendingDefaultAdmin，
            delete _pendingDefaultAdmin;
        }
        super._grantRole(role, account);
    }
}
