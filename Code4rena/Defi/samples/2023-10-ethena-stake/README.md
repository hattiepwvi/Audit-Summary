# Ethena Labs audit details
- Total Prize Pool: $36,500 USDC
  - HM awards: $24,750 USDC
  - Analysis awards: $1,500 USDC
  - QA awards: $750 USDC
  - Bot Race awards: $2,250 USDC
  - Gas awards: $750 USDC
  - Judge awards: $3,600 USDC
  - Lookout awards: $2,400 USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-10-ethena-labs/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts October 24, 2023 20:00 UTC
- Ends October 30, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

The 4naly3er report can be found [here](https://github.com/code-423n4/2023-10-ethena/blob/main/4naly3er-report.md).

Automated findings output for the audit can be found [here](https://github.com/code-423n4/2023-10-ethena/blob/main/bot-report.md) within 24 hours of audit opening.

_Note for C4 wardens: Anything included in the 4naly3er **or** the automated findings output is considered a publicly known issue and is ineligible for awards._

# Overview

## Gitbook
To get an overview of Ethena, please visit our [Gitbook](https://ethena-labs.gitbook.io/ethena-labs/10CaMBZwnrLWSUWzLS2a/).

## Goals

The goal of Ethena is to offer a permissionless stablecoin, USDe, to defi users and to offer users yield for being in our ecosystem. Unlike USDC where Circle captures the yield, USDe holders can stake their USDe in exchange to receive stUSDe, which increases in value relative to USDe as the protocol earns yield. (Similar to rETH increasing in value with respect to ETH)

## How USDe is minted

Ethena provides an RFQ of how much USDe can be minted for a stETH amount. If user agrees to price, user signs the EIP712 signature and submits it to Ethena. stETH is traded for newly minted USDe at the rate specified by Ethena's RFQ and user's signature. The stETH is then sent to custodians and delegated to perps exchange, where an a USD amount of ETH perps equal to the USDe minted is shorted, creating a delta neutral position.

## How Ethena generated yield

Users mint USDe with stETH, and Ethena opens an equvilant short ETH perps position on perps exchanges. stETH yields 3-4% annualized, while short ETH perps yield 6-8%. The combined long and short position daily yield is sent to an insurance fund, and then sent to the staking contract every 8 hours.

## How we maintain delta neutrality

The long stETH and short ETH perps creates a position with value that's fixed to the time of it's creation. Imagine ETH = $2000, user sends in 10 stETH to mint 20000 USDe, and Ethena shorts 10 ETH worth of perps.

If the market goes down 90%, the long 10 stETH position is now worth $2000, down from $20000. While the short 10 ETH perps position has an unrealized P&L of $18000. If the user wishes to redeem his USDe, the short perps position can be closed to realize $18000 of profits, and buy 90 stETH. Along with the original 10 stETH, the user is returned 100 stETH, also worth $20000.

## Our 3 Smart contracts

### USDe.sol

`USDe.sol` is the contract of our stablecoin. It extends `ERC20Burnable`, `ERC20Permit` and `Ownable2Step` from Open Zepplin. There's a single variable, the `minter` address that can be modified by the `OWNER`. Outside of `Ownable2Step` contract owner only has one custom function, the ability to set the `minter` variable to any address.

The `minter` address is the only address that has the ability to mint USDe. This minter address has one of the most powerful non-owner permissions, the ability to create an unlimited amount of USDe. It will always be pointed to the `EthenaMinting.sol` contract.

### EthenaMinting.sol

`EthenaMinting.sol` is the contract and address that the `minter` variable in `USDe.sol` points to. When users mint USDe with stETH (or other collateral) or redeems collateral for USDe, this contract is invoked.

The primary functions used in this contract is `mint()` and `redeen()`. Users who call this contract are all within Ethena. When outside users wishes to mint or redeem, they perform an EIP712 signature based on an offchain price we provided to them. They sign the order and sends it back to Ethena's backend, where we run a series of checks and are the ones who take their signed order and put them on chain.

By design, Ethena will be the only ones calling `mint()`,`redeen()` and other functions in this contract.

### Minting

In the `mint()` function, `order` and `signature` parameters comes from users who wishes to mint and performed the EIP 712 signature. `route` is generated by Ethena, where it defines where the incoming collateral from users go to. The address in `route` we defined must be inside `_custodianAddresses` as a safety check, to ensure funds throughout the flow from users end up in our custodians within a single transaction. Only `DEFAULT_ADMIN_ROLE` can add custodian address.

### Redeeming

Similar to minting, user performs an EIP712 signature with prices Ethena defined. We then submit their signature and order into `redeem()` function. The funds from redemption comes from the Ethena minting contract directly. Ethena aims to hold between $100k-$200k worth of collateral at all times for hot redemptions. This mean for users intending to redeem a large amount, they will need to redeem over several blocks. Alternatively they can sell USDe on the open market.

### Setting delegated signer

Some users trade through smart contracts. Ethena minting has the ability to delegate signers to sign for an address, using `setDelegatedSigner`. The smart contract should call this function with the desired EOA address to delegate signing to. To remove delegation, call `removeDelegatedSigner`. Multiple signers can be delegated at once, and it can be used by EOA addresses as well.

By setting a delegated signer, the smart contract allows both the `order.benefactor` and delegated signed to be the address that's ecrecovered from the order and signature, rather than just `order.benefactor`.

#### Security

`EthenaMinting.sol` have crucial roles called the `MINTER` and `REDEEMER`. Starting with `MINTER`, in our original design, they have the ability to mint any amount of USDe for any amount of collateral. Given `MINTER` is a hot wallet and is an EOA address, we considered the scenario where this key becomes compromised. An attacker could then mint a billion USDe for no collateral, and dump them on pools, causing a black swan event our insurance fund cannot cover.

Our solution is to enforce an on chain mint and redeem limitation of 100k USDe per block. In addition, we have `GATEKEEPER` roles with the ability to disable mint/redeems and remove `MINTERS`,`REDEEMERS`. `GATEKEEPERS` acts as a safety layer in case of compromised `MINTER`/`REDEEMER`. They will be run in seperate AWS accounts not tied to our organisation, constantly checking each transaction on chain and disable mint/redeems on detecting transactions at prices not in line with the market. In case compromised `MINTERS` or `REDEEMERS` after this security implementation, a hacker can at most mint 100k USDe for no collateral, and redeem all the collateral within the contract (we will hold ~$200k max), for a max loss of $300k in a single block, before `GATEKEEPER` disable mint and redeem. The $300k loss will not materialy affect our operations.

Further down the line, there has been considerations to give external organisations a `GATEKEEPER` role. We expect the external organisations to only invoke the gatekeeper functions when price errors occur on chain. Abuse of this prvileage means their `GATEKEEPER` role will be removed.

The `DEFAULT_ADMIN_ROLE`, also our ethena multisig, is required to re-enable minting/redeeming. `DEFAULT_ADMIN_ROLE` also has the power to add/remove `GATEKEEPERS`,`MINTER` and `REDEEMER`.

`DEFAULT_ADMIN_ROLE` is the most powerful role in the minting contract, but is still beneath the `OWNER` role of `USDe.sol`, given that the owner can remove the minting contract's privilege to mint.

### StakedUSDeV2.sol

`StakedUSDeV2.sol` is where holders of USDe stablecoin can stake their stablecoin, get stUSDe in return and earn yield. Our protocol's yield is paid out by having a `REWARDER` role of the staking contract send yield in USDe, increasing the stUSDe value with respect to USDe.

This contract is a modification of the ERC4626 standard, with a change to vest in rewards linearly over 8 hours to prevent users frontrunning the payment of yield, then unwinding their position right after (or even in the same block). This is also the reason for `REWARDER` role. Otherwise users can be denied rewards if random addresses send in 1 wei and modifies the rate of reward vesting.

There's also an additional change to add a 14 day cooldown period on unstaking stUSDe. When the unstake process is initiated, from the user's perspective, stUSDe is burnt immediately, and they will be able to invoke the withdraw function after cooldown is up to get their USDe in return. Behind the scenes, on burning of stUSDe, USDe is sent to a seperate silo contract to hold the funds for the cooldown period. And on withdrawal, the staking contract moves user funds from silo contract out to the user's address. The cooldown is configurable up to 90 days.

Due to legal requirements, there's a `SOFT_RESTRICTED_STAKER_ROLE` and `FULL_RESTRICTED_STAKER_ROLE`. The former is for addresses based in countries we are not allowed to provide yield to, for example USA. Addresses under this category will be soft restricted. They cannot deposit USDe to get stUSDe or withdraw stUSDe for USDe. However they can participate in earning yield by buying and selling stUSDe on the open market.

`FULL_RESTRCITED_STAKER_ROLE` is for sanction/stolen funds, or if we get a request from law enforcement to freeze funds. Addresses fully restricted cannot move their funds, and only Ethena can unfreeze the address. Ethena also have the ability to repossess funds of an address fully restricted. We understand having the ability to freeze and repossess funds of any address Ethena choose could be a cause of concern for defi users decisions to stake USDe. While we aim to make our operations as secure as possible, interacting with Ethena still requires a certain amount of trust in our organisation outside of code on the smart contract, given the tie into cefi to earn yield.

Note this restriction only applied to staking contract, there are no restrictions or ability to freeze funds of the USDe stablecoin, unlike USDC.

## Owner of Ethena's smart contracts
Ethena utilises a gnosis safe multisig to hold ownership of its smart contracts. All multisig keys are cold wallets. We will require 7/10 or more confirmations before transactions are approved. This multisig is purely for the purpose of owning the smart contracts, and will not hold funds or do other on chain actions.

## Links

- **Documentation:** https://ethena-labs.gitbook.io/ethena-labs/10CaMBZwnrLWSUWzLS2a/
- **Website:** https://www.ethena.fi/
- **Twitter:** https://twitter.com/ethena_labs
- **Discord:** https://discord.com/invite/ethena

# Scope
Smart contract files are located in /protocols/USDe/contracts

`USDe.sol`
`EthenaMinting.sol` and the contract it extends, `SingleAdminAccessControl.sol`
`StakedUSDeV2.sol`, the contract it extends, `StakedUSDe.sol` and the additional contract it creates `USDeSilo.sol`

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [USDe.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/USDe.sol) | 24 | USDe token stablecoin contract that grants another address the ability to mint USDe | [`@openzeppelin/ERC20Burnable.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Burnable.sol) [`@openzeppelin/ERC20Permit.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) [`@openzeppelin/Ownable2Step.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol)|
| [EthenaMinting.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/EthenaMinting.sol) | 295 | The contract where minting and redemption occurs. USDe.sol grants this contract the ability to mint USDe | [`@openzeppelin/ReentrancyGuard.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol) |
| [StakedUSDe.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/StakedUSDe.sol) | 130 | Extension of ERC4626. Users stake USDe to receive stUSDe which increases in value as Ethena deposits protocol yield here | [`@openzeppelin/ReentrancyGuard.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol) [`@openzeppelin/ERC20Permit.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol) [`@openzeppelin/ERC4626.sol`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol) |
| [StakedUSDeV2.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/StakedUSDeV2.sol) | 76 | Extends StakedUSDe, adds a redemption cooldown.  | |
| [USDeSilo.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/USDeSilo.sol) | 20 | Contract to temporarily hold USDe during redemption cooldown  | |
| [SingleAdminAccessControl.sol](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/SingleAdminAccessControl.sol) | 43 | EthenaMinting uses SingleAdminAccessControl rather than the standard AccessControl  | |

## Out of Scope

Any file not listed above

# Additional Context

### ERC20 Interactions

stETH and our own USDe stablecoin.

### ERC721 Interactions

Only our own ERC712 signed order in EthenaMinting.sol.

### Blockchains

Ethereum mainnet
  
### Trusted Roles

- `USDe` minter - can mint any amount of `USDe` tokens to any address. Expected to be the `EthenaMinting` contract
- `USDe` owner - can set token `minter` and transfer ownership to another address
- `USDe` token holder - can not just transfer tokens but burn them and sign permits for others to spend their balance
- `StakedUSDe` admin - can rescue tokens from the contract and also to redistribute a fully restricted staker's `stUSDe` balance, as well as give roles to other addresses (for example the `FULL_RESTRICTED_STAKER_ROLE` role)
- `StakedUSDeV2` admin - has all power of "`StakedUSDe` admin" and can also call the `setCooldownDuration` method
- `REWARDER_ROLE` - can transfer rewards into the `StakedUSDe` contract that will be vested over the next 8 hours
- `BLACKLIST_MANAGER_ROLE` - can do/undo full or soft restriction on a holder of `stUSDe`
- `SOFT_RESTRICTED_STAKER_ROLE` - address with this role can't stake his `USDe` tokens or get `stUSDe` tokens minted to him
- `FULL_RESTRICTED_STAKER_ROLE` - address with this role can't burn his `stUSDe` tokens to unstake his `USDe` tokens, neither to transfer `stUSDe` tokens. His balance can be manipulated by the admin of `StakedUSDe`
- `MINTER_ROLE` - can actually mint `USDe` tokens and also transfer `EthenaMinting`'s token or ETH balance to a custodian address
- `REDEEMER_ROLE` - can redeem collateral assets for burning `USDe`
- `EthenaMinting` admin - can set the maxMint/maxRedeem amounts per block and add or remove supported collateral assets and custodian addresses, grant/revoke roles
- `GATEKEEPER_ROLE` - can disable minting/redeeming of `USDe` and remove `MINTER_ROLE` and `REDEEMER_ROLE` roles from authorized accounts


# Attack Ideas (Where to look for bugs)


# Main Invariants

Properties that should NEVER be broken under any circumstance:

EthenaMinting.sol - User's signed EIP712 order, if executed, must always execute as signed. ie for mint orders, USDe is minted to user and collateral asset is removed from user based on the signed values.

Max mint per block should never be exceeded.

USDe.sol - Only the defined minter address can have the ability to mint USDe.



# Known Issues

- `SOFT_RESTRICTED_STAKER_ROLE` can be bypassed by user buying/selling stUSDe on the open market
- Line 343 in `EthenaMinting.sol` should be `InvalidAddress()` instead of `InvalidAmount()`
- `maxRedeemPerBlock` does not limit redemption in case of `REDEEMER_ROLE` key compromise unlike `maxMintPerBlock`, as the attacker can redeem all collateral held in the contract for 0 USDe, which does not increment `maxRedeemPerBlock`. This is by design, as limiting unlimited mints was the primary attack vector we wish to eliminate on key compromise and losing all funds currently in minting contract (which will be a <$200k amount) is an acceptable outcome. 


## Scoping Details 

```
- If you have a public code repo, please share it here: ethena.fi  
- How many contracts are in scope?: 6   
- Total SLoC for these contracts?: 588  
- How many external imports are there?: 4
- How many separate interfaces and struct definitions are there for the contracts within scope?: 6
- Does most of your code generally use composition or inheritance?: Inheritance   
- How many external calls?:    
- What is the overall line coverage percentage provided by your tests?: 70%
- Is this an upgrade of an existing system?: False
- Check all that apply (e.g. timelock, NFT, AMM, ERC20, rollups, etc.): ERC-20 Token
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?: False  
- Please describe required context: N/A
- Does it use an oracle?: No  
- Describe any novel or unique curve logic or mathematical models your code uses:  None
- Is this either a fork of or an alternate implementation of another project?: No   
- Does it use a side-chain?: No, ethereum mainnet only
- Describe any specific areas you would like addressed: Any attack that results in misplacement of funds or denial of service.
```

# Tests

## Install

### Foundry unit tests

```bash
forge build
forge test
```

Enable tracing and logging to console via

```
forge test -vvvv
```
