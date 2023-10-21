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

import "contracts/cash/interfaces/IKYCRegistry.sol";
import "contracts/cash/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "contracts/cash/external/chainalysis/ISanctionsList.sol";
import "contracts/cash/external/openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "contracts/cash/external/openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title KYCRegistry
 * @author Ondo Finance
 * @notice This contract manages KYC status for addresses that interact with
 *         Ondo products.
 * 项目总结： CASH允许经过实名认证的用户通过持有Cash代币来持有对现实世界资产（Real World Assets，RWAs），
 *          Flux是一个支持不同资产借贷的协议, 基于Compound V2, 用户可以向这些市场提供DAI和OUSG作为抵押，但只能借出DAI。
 * 本合约总结： KYCRegistry 用于记录用户的KYC状态，即是否已经完成了实名认证（添加、删除用户的 KYC）。
 *            1）KYC状态记录方式： 通过映射（mapping）来记录用户的KYC状态。
 *            2）合约管理员 REGISTRY_ADMIN： 有权限添加/删除与KYC相关的角色。
 *            3）链上罚单名单：sanctionsList 机制，用于检查用户是否出现在链上的违规名单中。
 *            4）函数：
 *                 - KYC：addKYCAddressViaSignature 允许用户通过提供一个由特定角色签名的签名，将自己添加到KYC注册表中。
 *                 - 检查 KYC 状态：getKYCStatus 函数用于检查某个地址的 KYC 状态，并确保该地址不在违规名单上。
 *                 - 更改 KYC：assignRoletoKYCGroup 函数用于将特定的角色分配给某个KYC等级，以控制对该等级KYC状态的更改。
 *                 - 添加、删除 KYC： addKYCAddresses 和 removeKYCAddresses 这两个函数用于批量添加或删除用户的KYC状态。
 *            5）事件：角色分配、地址的添加或删除等 *
 */
contract KYCRegistry is AccessControlEnumerable, IKYCRegistry, EIP712 {
    // KYCApproval 批准类型的哈希，包括KYC等级、用户地址和截止日期。
    bytes32 public constant _APPROVAL_TYPEHASH =
        keccak256(
            "KYCApproval(uint256 kycRequirementGroup,address user,uint256 deadline)"
        );
    // Admin role that has permission to add/remove KYC related roles
    // 注册表管理员的常量的哈希
    bytes32 public constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");

    // {<KYCLevel> => {<user account address> => is user KYC approved}
    // 将KYC等级映射到一个特定的角色（以bytes32的形式）：规定了谁有权修改该KYC等级下的KYC状态。
    mapping(uint256 => mapping(address => bool)) public kycState;

    // Represents which roles msg.sender must have in order to change
    // KYC state at that group.
    /// @dev Default admin role of 0x00... will be able to set all group roles
    ///      that are unset.
    mapping(uint256 => bytes32) public kycGroupRoles;

    // Chainalysis sanctions list
    // sanctionsList的接口
    ISanctionsList public immutable sanctionsList;

    /// @notice constructor
    constructor(
        address admin,
        address _sanctionsList
    ) EIP712("OndoKYCRegistry", "1") {
        // 授予了特定角色给指定的地址 admin
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN, admin);
        sanctionsList = ISanctionsList(_sanctionsList);
    }

    /**
     * @notice Add a provided user to the registry at a specified
     *         `kycRequirementGroup`. In order to sucessfully call this function,
     *         An external caller must provide a signature signed by an address
     *         with the role `kycGroupRoles[kycRequirementGroup]`.
     *
     * @param kycRequirementGroup KYC requirement group to modify `user`'s
     *                            KYC status for
     * @param user                User address to change KYC status for
     * @param deadline            Deadline for which the signature-auth based
     *                            operations with the signature become invalid
     * @param v                   Recovery ID (See EIP 155)
     * @param r                   Part of ECDSA signature representation
     * @param s                   Part of ECDSA signature representation
     *
     * @dev Please note that ecrecover (which the Registry uses) requires V be
     *      27 or 28, so a conversion must be applied before interacting with
     *      `addKYCAddressViaSignature`
     *      总结： 从签名中恢复出签名者的以太坊地址， 然后将获取到的签名者地址与白名单比对
     */
    function addKYCAddressViaSignature(
        uint256 kycRequirementGroup,
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // 以太坊中，签名的 v 值通常是 27 或 28。
        require(
            v == 27 || v == 28,
            "KYCRegistry: invalid v value in signature"
        );
        require(
            !kycState[kycRequirementGroup][user],
            "KYCRegistry: user already verified"
        );
        require(block.timestamp <= deadline, "KYCRegistry: signature expired");
        // 用于验证数字签名的有效性的 hash
        bytes32 structHash = keccak256(
            abi.encode(_APPROVAL_TYPEHASH, kycRequirementGroup, user, deadline)
        );
        // https://eips.ethereum.org/EIPS/eip-712 compliant
        bytes32 expectedMessage = _hashTypedDataV4(structHash);

        // `ECDSA.recover` reverts if signer is address(0)
        // 恢复（recover）出签名者的以太坊地址
        address signer = ECDSA.recover(expectedMessage, v, r, s);
        // 检查签名者是否拥有足够的权限来进行这次KYC认证。
        _checkRole(kycGroupRoles[kycRequirementGroup], signer);

        kycState[kycRequirementGroup][user] = true;

        emit KYCAddressAddViaSignature(
            msg.sender,
            user,
            signer,
            kycRequirementGroup,
            deadline
        );
    }

    /// @notice Getter for EIP 712 Domain separator.
    // 允许外部的人或其他智能合约获取合约中定义的一个名为 DOMAIN_SEPARATOR 的数值
    // DOMAIN_SEPARATOR 是一个用于签名验证的特殊值
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Get KYC status of `account` for the provided
     *         `kycRequirementGroup`. In order to return true, `account`'s state
     *         in this contract must be true and additionally pass a
     *         `sanctionsList` check.
     *
     * @param kycRequirementGroup KYC group to check KYC status for
     * @param account             Addresses to check KYC status for
     */
    function getKYCStatus(
        uint256 kycRequirementGroup,
        address account
    ) external view override returns (bool) {
        return
            kycState[kycRequirementGroup][account] &&
            !sanctionsList.isSanctioned(account);
    }

    /**
     * @notice Assigns a role to specified `kycRequirementGroup` to gate changes
     *         to that group's KYC state
     *
     * @param kycRequirementGroup KYC group to set role for
     * @param role                The role being assigned to a group
     */
    function assignRoletoKYCGroup(
        uint256 kycRequirementGroup,
        bytes32 role
    ) external onlyRole(REGISTRY_ADMIN) {
        kycGroupRoles[kycRequirementGroup] = role;
        emit RoleAssignedToKYCGroup(kycRequirementGroup, role);
    }

    /**
     * @notice Add addresses to KYC list for specified `kycRequirementGroup`
     *
     * @param kycRequirementGroup KYC group associated with `addresses`
     * @param addresses           List of addresses to grant KYC'd status
     */
    // 给特定的kycRequirement 组分配一个 role 角色，以控制对该组的KYC状态的更改。
    function addKYCAddresses(
        uint256 kycRequirementGroup,
        address[] calldata addresses
    ) external onlyRole(kycGroupRoles[kycRequirementGroup]) {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; i++) {
            kycState[kycRequirementGroup][addresses[i]] = true;
        }
        emit KYCAddressesAdded(msg.sender, kycRequirementGroup, addresses);
    }

    /**
     * @notice Remove addresses from KYC list
     *
     * @param kycRequirementGroup KYC group associated with `addresses`
     * @param addresses           List of addresses to revoke KYC'd status
     */
    function removeKYCAddresses(
        uint256 kycRequirementGroup,
        address[] calldata addresses
    ) external onlyRole(kycGroupRoles[kycRequirementGroup]) {
        uint256 length = addresses.length;
        for (uint256 i = 0; i < length; i++) {
            kycState[kycRequirementGroup][addresses[i]] = false;
        }
        emit KYCAddressesRemoved(msg.sender, kycRequirementGroup, addresses);
    }

    /*//////////////////////////////////////////////////////////////
                        Events
  //////////////////////////////////////////////////////////////*/
    /**
     * @dev Event emitted when a role is assigned to a KYC group
     *
     * @param kycRequirementGroup The KYC group
     * @param role                The role being assigned
     */
    event RoleAssignedToKYCGroup(
        uint256 indexed kycRequirementGroup,
        bytes32 indexed role
    );

    /**
     * @dev Event emitted when addresses are added to KYC requirement group
     *
     * @param sender              Sender of the transaction
     * @param kycRequirementGroup KYC requirement group being updated
     * @param addresses           Array of addresses being added as elligible
     */
    event KYCAddressesAdded(
        address indexed sender,
        uint256 indexed kycRequirementGroup,
        address[] addresses
    );

    /**
     * @dev Event emitted when a user is added to the KYCRegistry
     *      by an external caller through signature-auth
     *
     * @param sender              Sender of the transaction
     * @param user                User being added to registry
     * @param signer              Digest signer
     * @param kycRequirementGroup KYC requirement group being updated
     * @param deadline            Expiration constraint on signature
     */
    event KYCAddressAddViaSignature(
        address indexed sender,
        address indexed user,
        address indexed signer,
        uint256 kycRequirementGroup,
        uint256 deadline
    );

    /**
     * @dev Event emitted when addresses are removed from KYC requirement group
     *
     * @param sender              Sender of the transaction
     * @param kycRequirementGroup KYC requirement group being updated
     * @param addresses           Array of addresses being added as elligible
     */
    event KYCAddressesRemoved(
        address indexed sender,
        uint256 indexed kycRequirementGroup,
        address[] addresses
    );
}
