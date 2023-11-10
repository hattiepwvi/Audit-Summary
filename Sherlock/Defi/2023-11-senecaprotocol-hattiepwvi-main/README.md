
# Seneca Protocol contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Arbitrum, Ethereum, Optimism, Base
___

### Q: Which ERC20 tokens do you expect will interact with the smart contracts? 
We anticipate potentially supporting any ERC20. Any token with unusual functionality should be addressed with composite solutions or avoided.
___

### Q: Which ERC721 tokens do you expect will interact with the smart contracts? 
ERC721s could be supported in the future, but they would be integrated on top of the current implementation rather than directly interacting with it.
___

### Q: Do you plan to support ERC1155?
ERC1155s could be supported in the future, but they would be integrated on top of the current implementation rather than directly interacting with it.
___

### Q: Which ERC777 tokens do you expect will interact with the smart contracts? 
We don't currently plan to support ERC777s.
___

### Q: Are there any FEE-ON-TRANSFER tokens interacting with the smart contracts?

We can anticipate a fee-on-transfer token interacting with smart contracts via sSEN collateralization, as atomically liquidating a sSEN position would necessitate unstaking and DEX selling of SEN, the latter implying standard fee-on-transfer logic.
___

### Q: Are there any REBASING tokens interacting with the smart contracts?

Yes, there will be rebasing tokens interacting with the smart contracts, such as deposit receipts from lending markets.
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED?
TRUSTED
___

### Q: Is the admin/owner of the protocol/contracts TRUSTED or RESTRICTED?
TRUSTED
___

### Q: Are there any additional protocol roles? If yes, please explain in detail:
- Owner: can add BentoBox strategies, whitelist a masterContract for easy approvals, setFeeTo, reduceSupply of senUSD, and mint senUSD.

- CDP user: can 'addCollateral', 'removeCollateral', 'borrow', and 'repay' interacting with the respective Chambers functions, which interface with the BentoBox through cook().

- Liquidator: can liquidate using the function 'liquidate' and secure a bonus percentage of collateral

-feeReceiver: will be owner by default and can be changed.
___

### Q: Is the code/contract expected to comply with any EIPs? Are there specific assumptions around adhering to those EIPs that Watsons should be aware of?
EIP712 for signatures and ERC165 for interface detection on OFT side.
___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
We are aware newFeeTo function contains no check for zero address as the receiver.
___

### Q: Please provide links to previous audits (if any).
Seneca's codebase is a fork of Abracadabra's, and we are aware of a De.Fi audit of that codebase.

https://files.safe.de.fi/safe/files/audit/pdf/abracadabra.pdf
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, input validation expectations, etc)?
We expect off-chain procedures and mechanisms for watching open CDPs and calling 'liquidate' when possible. The same applies for the update function in oracle contracts that SenecaOracle is interfacing with.
___

### Q: In case of external protocol integrations, are the risks of external contracts pausing or executing an emergency withdrawal acceptable? If not, Watsons will submit issues related to these situations that can harm your protocol's functionality.
Such risks are acceptable.
___

### Q: Do you expect to use any of the following tokens with non-standard behaviour with the smart contracts?
We don't expect to.
___

### Q: Add links to relevant protocol resources
https://seneca-protocol-docs.gitbook.io/seneca-protocol/
https://github.com/SenecaDefi/SenecaProtocol
___



# Audit scope


[SenecaProtocol @ 3df270c6e441865af19f097a4e63f4d032ad7954](https://github.com/SenecaDefi/SenecaProtocol/tree/3df270c6e441865af19f097a4e63f4d032ad7954)
- [SenecaProtocol/contracts/BentoBoxFlat.sol](SenecaProtocol/contracts/BentoBoxFlat.sol)
- [SenecaProtocol/contracts/ChamberFlat.sol](SenecaProtocol/contracts/ChamberFlat.sol)
- [SenecaProtocol/contracts/libraries/BytesLib.sol](SenecaProtocol/contracts/libraries/BytesLib.sol)
- [SenecaProtocol/contracts/libraries/ExcessivelySafeCall.sol](SenecaProtocol/contracts/libraries/ExcessivelySafeCall.sol)
- [SenecaProtocol/contracts/lzApp/LzApp.sol](SenecaProtocol/contracts/lzApp/LzApp.sol)
- [SenecaProtocol/contracts/lzApp/NonblockingLzApp.sol](SenecaProtocol/contracts/lzApp/NonblockingLzApp.sol)
- [SenecaProtocol/contracts/senUSD_OFT.sol](SenecaProtocol/contracts/senUSD_OFT.sol)
- [SenecaProtocol/contracts/token/oft/v2/OFTCoreV2.sol](SenecaProtocol/contracts/token/oft/v2/OFTCoreV2.sol)
- [SenecaProtocol/contracts/token/oft/v2/fee/BaseOFTWithFee.sol](SenecaProtocol/contracts/token/oft/v2/fee/BaseOFTWithFee.sol)
- [SenecaProtocol/contracts/token/oft/v2/fee/Fee.sol](SenecaProtocol/contracts/token/oft/v2/fee/Fee.sol)
- [SenecaProtocol/contracts/token/oft/v2/fee/OFTWithFee.sol](SenecaProtocol/contracts/token/oft/v2/fee/OFTWithFee.sol)

