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

import "contracts/cash/interfaces/IKYCRegistry.sol";
import "contracts/cash/interfaces/IKYCRegistryClient.sol";

pragma solidity 0.8.16;

/**
 * @title KYCRegistryClientInitializable
 * @author Ondo Finance
 * @notice This abstract contract manages state required for clients
 *         of the KYC registry.
 * 总结： 合约是 KYC 注册的客户端
 *       1）_setKYCRegistry 函数检查传入的地址是否有效。
 *       2）_setKYCRequirementGroup 设置客户端要检查 KYC 状态的要求组。
 *       3）_getKYCStatus 检查一个地址是否通过了 KYC
 */
abstract contract KYCRegistryClient is IKYCRegistryClient {
    // KYC Registry address
    IKYCRegistry public override kycRegistry;
    // KYC requirement group
    uint256 public override kycRequirementGroup;

    /**
     * @notice Sets the KYC registry address for this client
     *
     * @param _kycRegistry The new KYC registry address
     */
    function _setKYCRegistry(address _kycRegistry) internal {
        if (_kycRegistry == address(0)) {
            revert RegistryZeroAddress();
        }
        address oldKYCRegistry = address(kycRegistry);
        kycRegistry = IKYCRegistry(_kycRegistry);
        emit KYCRegistrySet(oldKYCRegistry, _kycRegistry);
    }

    /**
     * @notice Sets the KYC registry requirement group for this
     *         client to check kyc status for
     *
     * @param _kycRequirementGroup The new KYC group
     */
    function _setKYCRequirementGroup(uint256 _kycRequirementGroup) internal {
        uint256 oldKYCLevel = kycRequirementGroup;
        kycRequirementGroup = _kycRequirementGroup;
        emit KYCRequirementGroupSet(oldKYCLevel, _kycRequirementGroup);
    }

    /**
     * @notice Checks whether an address has been KYC'd
     *
     * @param account The address to check
     */
    function _getKYCStatus(address account) internal view returns (bool) {
        return kycRegistry.getKYCStatus(kycRequirementGroup, account);
    }
}
