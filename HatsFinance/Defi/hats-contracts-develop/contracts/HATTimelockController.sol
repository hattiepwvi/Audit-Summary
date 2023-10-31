// SPDX-License-Identifier: MIT
// Disclaimer https://github.com/hats-finance/hats-contracts/blob/main/DISCLAIMER.md

pragma solidity 0.8.16;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./HATGovernanceArbitrator.sol";

/**
 * @title  总结：时间锁
 * @author 1）初始化：最小延迟时间 (_minDelay)、提案发起者 (_proposers) 和 执行者 (_executors) 的地址数组
 *         2）提案发起者：批准、驳回索赔请求；设置委员会成员、设置 Vault 的描述信息、可见性；设置奖励控制器的分配点数、设置暂停、兑换资产并发送给受益人；
 * @notice
 */

contract HATTimelockController is TimelockController {
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    )
        // solhint-disable-next-line no-empty-blocks
        TimelockController(_minDelay, _proposers, _executors, address(0))
    {}

    // The following functions are not subject to the timelock

    function approveClaim(
        HATGovernanceArbitrator _arbitrator,
        IHATClaimsManager _claimsManager,
        bytes32 _claimId
    ) external onlyRole(PROPOSER_ROLE) {
        _arbitrator.approveClaim(_claimsManager, _claimId);
    }

    function dismissClaim(
        HATGovernanceArbitrator _arbitrator,
        IHATClaimsManager _claimsManager,
        bytes32 _claimId
    ) external onlyRole(PROPOSER_ROLE) {
        _arbitrator.dismissClaim(_claimsManager, _claimId);
    }

    function setCommittee(
        IHATClaimsManager _claimsManager,
        address _committee
    ) external onlyRole(PROPOSER_ROLE) {
        _claimsManager.setCommittee(_committee);
    }

    function setVaultDescription(
        IHATVault _vault,
        string memory _descriptionHash
    ) external onlyRole(PROPOSER_ROLE) {
        _vault.setVaultDescription(_descriptionHash);
    }

    function setDepositPause(
        IHATVault _vault,
        bool _depositPause
    ) external onlyRole(PROPOSER_ROLE) {
        _vault.setDepositPause(_depositPause);
    }

    function setVaultVisibility(
        IHATVault _vault,
        bool _visible
    ) external onlyRole(PROPOSER_ROLE) {
        _vault.registry().setVaultVisibility(address(_vault), _visible);
    }

    function setAllocPoint(
        IHATVault _vault,
        IRewardController _rewardController,
        uint256 _allocPoint
    ) external onlyRole(PROPOSER_ROLE) {
        _rewardController.setAllocPoint(address(_vault), _allocPoint);
    }

    function swapAndSend(
        IHATVaultsRegistry _registry,
        address _asset,
        address[] calldata _beneficiaries,
        uint256 _amountOutMinimum,
        address _routingContract,
        bytes calldata _routingPayload
    ) external onlyRole(PROPOSER_ROLE) {
        _registry.swapAndSend(
            _asset,
            _beneficiaries,
            _amountOutMinimum,
            _routingContract,
            _routingPayload
        );
    }

    function setEmergencyPaused(
        IHATVaultsRegistry _registry,
        bool _isEmergencyPaused
    ) external onlyRole(PROPOSER_ROLE) {
        _registry.setEmergencyPaused(_isEmergencyPaused);
    }
}
