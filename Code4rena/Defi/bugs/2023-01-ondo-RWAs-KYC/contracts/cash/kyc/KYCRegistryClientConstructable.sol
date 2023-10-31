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

import "contracts/cash/kyc/KYCRegistryClient.sol";

pragma solidity 0.8.16;

import "contracts/cash/kyc/KYCRegistryClient.sol";

/**
 * @title KYCRegistryClientConstructable
 * @author Ondo Finance
 * @notice This abstract contract allows inheritors to access the KYC list
 *         maintained by the registry
 * 总结： KYCRegistryClientConstructable 的抽象合约继承了 KYCRegistryClient 合约
 *       1）_setKYCRegistry(_kycRegistry) 将传入的 _kycRegistry 地址设置为合约中的 KYC 注册地址。
 *       2）_setKYCRequirementGroup(_kycRequirementGroup) 将传入的 _kycRequirementGroup 设置为合约中的 KYC 要求组标识。
 */
abstract contract KYCRegistryClientConstructable is KYCRegistryClient {
    /**
     * @notice Constructor
     *
     * @param _kycRegistry         Address of the registry contract
     * @param _kycRequirementGroup KYCLevel of the contract.
     */
    constructor(address _kycRegistry, uint256 _kycRequirementGroup) {
        _setKYCRegistry(_kycRegistry);
        _setKYCRequirementGroup(_kycRequirementGroup);
    }
}
