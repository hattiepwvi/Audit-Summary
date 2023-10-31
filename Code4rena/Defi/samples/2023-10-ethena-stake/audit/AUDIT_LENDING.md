/**
   总结： USDe稳定币，Ethena 是 ETH 的 Delta中性稳定币协议；
         - Ethena专注于开发ETH到期期货和永续掉期对冲解决方案
       1）现金流：stETH => USDe => (短头寸)ETH永续合约做空 (中性 delta)收益率为6-8% + (长头寸)stETH的收益率为3-4%
            - 询价机制（RFQ），用于确定一定数量的stETH可以兑换多少USDe。用户同意价格，将会签署EIP712签名并提交给Ethena。
            - stETH 发送到托管人，委托给永续交易所，铸造的USDe数量相等的ETH永续合约做空，从而创建一个Delta中性头寸。
               - stETH代表Lido中质押的以太币，其价值包括了初始存款和质押奖励。
            - 多头和空头头寸收益被发送到一个保险基金，然后每8小时发送到质押合约。
            - USDe质押以获得 stUSDe
            - 添加了GATEKEEPER角色来检查交易价格是否符合市场，使用gnosis安全多签名钱包来拥有其智能合约的所有权。
        2）三个合约：
            - USDe.sol：稳定币合约，扩展了ERC20Burnable、ERC20Permit和Ownable2Step
            - EthenaMinting.so：铸币合约，被USDe.sol引用。用于处理用户铸造和赎回USDe的请求。
            - StakedUSDeV2.sol：用于用户质押USDe以获取stUSDe
        3）最担心的错误：稳定币铸币、质押、收益计算
            - 抵押机制的潜在缺陷、与收益计算相关的问题，或者可能影响稳定币协议的
            - 最关键的部分：稳定币机制、抵押管理、智能合约和安全措施、与交易所和平台的集成以及风险管理。
            - 特别担心质押和铸币机制。与Aave市场V3的借贷整合可能不太令人担忧
            

 */

Project info
Please provide us with the following:
A short description of your project:

Ethena is an ETH-powered delta-neutral stablecoin protocol that aims to achieve price stability through futures arbitrage across centralized and decentralized venues. It provides staking returns to users and offers various hedging solutions, such as ETH expiring futures and perpetual swaps, to construct floating versus fixed return profiles.

- Link to documentation:
  https://app.gitbook.com/o/uL0A7ZhBdOBWE4R46usw/s/sBsPyff5ft3inFy9jyjt/

- Git repo:
  https://github.com/ethena-labs/ethena (protocols/USDe/contracts/lending directory)

- Commit hash:
  0bdceecf8b57c26e56a717c0dacda4cd89ede71a

Pre-audit questionnaire

- Please provide a brief summary of the purpose and function of the system:

The Ethena system’s primary purpose is to offer a Stablecoin solution powered by ETH that achieves price stability while providing staking returns to users. By leveraging futures arbitrage across centralized and decentralized platforms, the protocol aims to maintain the stablecoin’s value. Additionally, Ethena focuses on developing ETH expiring futures and perpetual swap hedging solutions to create various floating versus fixed return profiles.

- What kind of bugs are you most concerned about?

The ones that can compromise the security, stability, or accuracy of the Ethena system. This may include vulnerabilities in smart contracts, potential flaws in the collateralization mechanisms, issues related to yield calculations, or any other bugs that could impact the integrity and reliability of the stablecoin protocol.
What parts of the project are most critical to its overall operation?
Stablecoin Mechanism, Collateral Management, Smart Contracts and Security Measures, Integration with Exchanges and Platforms and Risk Management.

- Are there any specific areas or components of the project that you are particularly worried about in terms of potential bugs or defects that may require additional attention?
  The staking and minting mechanism. The lending integration with the Aave market V3 shouldn’t be too concerning as we only modified small portions of the code, nonetheless its worth to take a good look.
  Pre-audit checklist

[ ] Code is frozen
If not, why? Still under development.
[ ] Test coverage is 100%
[X] Unit tests cover both positive and negative scenarios
[X] All tests pass
[X] Documentation provided
[X] Code has Natspec comments
[ ] A README is provided on how to setup and run your test suite
[X] If applicable - which ERC20 tokens do you plan to to integrate/whitelist? For now USDe, wEth, stEth, corresponding ATokens from the Aave lending integration… more TDB
