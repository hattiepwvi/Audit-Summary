// SPDX-License-Identifier: MIT

/**
 *  @authors: [@unknownunknown1]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity 0.8.16;

import "./interfaces/IHATArbitrator.sol";
import "./interfaces/IHATClaimsManager.sol";
import "./interfaces/IHATKlerosConnector.sol";
import {IArbitrable, IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";

/**
 *  @title HATKlerosV2Connector
 *  @dev This contract acts a connector between HatsFinance and Kleros court V2. The contract doesn't support appeals and evidence
 *  submisstion, since it'll be handled by the court.
 *  总结：该合约充当了 HatsFinance 和 Kleros 法庭之间的连接器，使得 HatsFinance 可以将争议提交给 Kleros 法庭，并接受来自法庭的裁决。
 *       1）结构体 DisputeStruct：HATVault 合约中的索赔ID、Kleros 法庭中创建的争议ID、裁决结果
 *       2）处理有争议的索赔
 */
contract HATKlerosV2Connector is IArbitrable, IHATKlerosConnector {
    // 仲裁者可以提供两个选择：支持和反对
    uint256 private constant RULING_OPTIONS = 2; // The amount of non 0 choices the arbitrator can give.

    struct DisputeStruct {
        bytes32 claimId; // Id of the claim in HATVault contract. HAT Vault 合约中的索赔ID、
        uint256 externalDisputeId; // Id of the dispute created in Kleros court. Kleros 法院中创建的外部争议ID、
        Decision ruling; // Ruling given by the arbitrator. ruling 仲裁者的裁决，通常是0或1
        bool resolved; // True if the dispute has been resolved. 争议是否已解决
        IHATClaimsManager vault; // Address of the vault related to a dispute. 与争议相关联的 HAT Vault 合约地址
    }

    IArbitrator public immutable klerosArbitrator; // The kleros arbitrator contract (e.g. Kleros Court). 保存了 Kleros 仲裁合约的地址
    IHATArbitrator public immutable hatArbitrator; // Address of the Hat arbitrator contract.  保存了 Hat 仲裁合约的地址
    bytes public arbitratorExtraData; // Extra data for the arbitrator. 字节数组保存了提供给仲裁器的额外数据

    DisputeStruct[] public disputes; // Stores the disputes created in this contract. 结构体包含了与争议相关的信息
    mapping(bytes32 => bool) public claimChallenged; // True if the claim was challenged in this contract..  跟踪特定索赔是否在此合约中被挑战/质疑
    mapping(uint256 => uint256) public externalIDtoLocalID; // Maps external dispute ids to local dispute ids. 将外部争议ID映射到本地争议ID。

    /** @dev Raised when a claim is challenged.
     *  @param _claimId Id of the claim in Vault cotract.
     */
    event Challenged(bytes32 indexed _claimId); // 被质疑的索赔ID

    /** @dev Constructor.
     *  @param _klerosArbitrator The Kleros arbitrator of the contract.  Kleros 仲裁器的地址（用于与 Kleros 法庭进行交互）
     *  @param _arbitratorExtraData Extra data for the arbitrator.  提供给仲裁器的额外数据（一些合约所需的信息，以便仲裁器能够正确地处理合约与 Kleros 法庭之间的交互。）
     *  @param _hatArbitrator Address of the Hat arbitrator.   Hat 仲裁器的地址（与 Kleros 仲裁器类似，这个地址将用于与 Hat 仲裁器进行交互）
     *  @param _metaEvidence Metaevidence for the dispute.  争议的元证据（参与方、索赔内容等）
     */

    constructor(
        IArbitrator _klerosArbitrator,
        bytes memory _arbitratorExtraData,
        IHATArbitrator _hatArbitrator,
        string memory _metaEvidence
    ) {
        // TODO: add new IEvidence events once they're established.
        //emit MetaEvidence(0, _metaEvidence);

        klerosArbitrator = _klerosArbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        hatArbitrator = _hatArbitrator;
    }

    /** @dev Notify KlerosArbitrator that expert's committee decision was challenged. Can only be called by Hat arbitrator.
     *  Requires the arbitration fees to be paid.
     *  @param _claimId The Id of the active claim in Vault contract. Vault 合约中的当前活跃索赔的ID
     *  @param _evidence URI of the evidence to support the challenge. 包含支持挑战/质疑的证据的URI
     *  @param _vault Relevant vault address. 与争议相关的保险库地址
     *  @param _disputer Address that made the challenge. 提出质疑的地址
     *  Note that the validity of the claim should be checked by Hat arbitrator.
     *  总结： 当专家委员会的决定受到质疑时，由 Hat 仲裁器调用以通知 Kleros 仲裁器。
     */
    function notifyArbitrator(
        bytes32 _claimId,
        string calldata _evidence,
        IHATClaimsManager _vault,
        address _disputer
    ) external payable override {
        // 检查函数的调用者是否是 Hat 仲裁者。
        require(msg.sender == address(hatArbitrator), "Wrong caller");
        // 检查该索赔是否已经受到了质疑
        require(!claimChallenged[_claimId], "Claim already challenged");

        // 获取仲裁费用
        uint256 arbitrationCost = getArbitrationCost();
        // 检查调用者是否支付了足够的仲裁费用
        require(msg.value >= arbitrationCost, "Should pay the full deposit.");

        // 将索赔标记为已经受到了质疑
        claimChallenged[_claimId] = true;

        // 获取当前争议的本地 ID，即当前争议在 disputes 数组中的索引
        uint256 localDisputeId = disputes.length;

        // 创建一个新的 DisputeStruct 对象，并将其存储在 disputes 数组中
        DisputeStruct storage dispute = disputes.push();
        // 将索赔 ID 分配给新的 DisputeStruct 对象
        dispute.claimId = _claimId;
        // 将与索赔相关的 Vault 地址分配给新的 DisputeStruct 对象。
        dispute.vault = _vault;

        // 在 Kleros 仲裁器上创建一个新的争议，并分配 ID
        uint256 externalDisputeId = klerosArbitrator.createDispute{
            value: arbitrationCost
        }(RULING_OPTIONS, arbitratorExtraData);
        // 将 Kleros 法庭中的争议 ID 分配给新的 DisputeStruct 对象。
        dispute.externalDisputeId = externalDisputeId;
        // 将 Kleros 法庭中的争议 ID 映射到本地争议 ID。
        externalIDtoLocalID[externalDisputeId] = localDisputeId;

        // 如果支付的仲裁费用超过了所需的费用，多余的部分将被退还给挑战者。
        if (msg.value > arbitrationCost)
            payable(_disputer).transfer(msg.value - arbitrationCost);

        // Challenged 的事件表示索赔已经受到了挑战
        emit Challenged(_claimId);
        // TODO: add new IEvidence events once they're established.
        //emit Dispute(klerosArbitrator, externalDisputeId, 0, localDisputeId);
        //emit Evidence(klerosArbitrator, localDisputeId, msg.sender, _evidence);
    }

    /** @dev Give a ruling for a dispute. Can only be called by the Kleros arbitrator.
     *  @param _disputeId ID of the dispute in the Kleros arbitrator contract.  Kleros 仲裁器合约中的争议ID
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Refused to arbitrate". 仲裁者做出的裁决
     *  总结： 对争议作出裁决
     */
    function rule(uint256 _disputeId, uint256 _ruling) external override {
        // 传入的 Kleros 仲裁器中的争议ID _disputeId 映射到本地的争议ID，以获取与争议相关的数据。
        uint256 localDisputeId = externalIDtoLocalID[_disputeId];

        // 用于访问与本地争议ID相关联的 DisputeStruct 对象。
        DisputeStruct storage dispute = disputes[localDisputeId];

        // 检查争议是否已经解决
        require(!dispute.resolved, "Already resolved");
        // 检查 _ruling 是否在有效的范围内（小于等于 RULING_OPTIONS）
        require(_ruling <= RULING_OPTIONS, "Invalid ruling option");
        require(
            // 检查调用者是否是 Kleros 仲裁器
            address(klerosArbitrator) == msg.sender,
            "Only the arbitrator can execute"
        );

        // 将 _ruling 赋值给 dispute 结构中的 ruling 字段，同时将其转换为 Decision 枚举类型。
        dispute.ruling = Decision(_ruling);
        // 将 dispute 结构中的 resolved 字段标记为已解决。
        dispute.resolved = true;

        // 将争议中的索赔ID分配给名为 claimId 的变量。
        bytes32 claimId = dispute.claimId;
        // 检查 _ruling 是否等于 Decision.ExecuteResolution 枚举值。
        if (_ruling == uint256(Decision.ExecuteResolution)) {
            // 调用 hatArbitrator 合约中的 executeResolution 函数
            hatArbitrator.executeResolution(dispute.vault, claimId);
        } else {
            // Arbitrator dismissed the resolution or refused to arbitrate (gave 0 ruling).
            // 用于解散解决方案或拒绝仲裁
            hatArbitrator.dismissResolution(dispute.vault, claimId);
        }

        // 表示作出了一个裁决
        emit Ruling(IArbitrator(msg.sender), _disputeId, _ruling);
    }

    /** @dev Get the arbitration cost to challenge a claim.
     *  @return Arbitration cost.
     */
    function getArbitrationCost() public view returns (uint256) {
        return klerosArbitrator.arbitrationCost(arbitratorExtraData);
    }
}
