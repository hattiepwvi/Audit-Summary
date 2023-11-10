
# Deployment

Add 'PRIVATE_KEY' to .env

To deploy, run:

```
npx hardhat run scripts/deploy.js --network goerli  
```

Then update test constants at the beginning of contractsTestGoerli.js and interestTests.js

After deployment, run a fork of the chain using:

```
npx hardhat node --fork <infura or alchemy>
```

Then to run tests:

```
npx hardhat test --network hardhat
```

# SenecaProtocol

## Chambers

```solidity
function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas) external payable returns (uint256 value1, uint256 value2)
```

Actions include:
- `ACTION_BORROW`: Borrow senUSD
- `ACTION_GET_REPAY_SHARE`: Get repay amount  
- `ACTION_BENTO_DEPOSIT`: Deposit into BentoBox
- `ACTION_ADD_COLLATERAL`: Add collateral.
- `ACTION_REPAY`: Repay debt.
- `ACTION_REMOVE_COLLATERAL`: Remove collateral.
- `ACTION_UPDATE_EXCHANGE_RATE`: Update exchange rate.
- `ACTION_BENTO_SETAPPROVAL`: Set BentoBox approval.
- `ACTION_BENTO_DEPOSIT`: Deposit into BentoBox.
- `ACTION_BENTO_WITHDRAW`: Withdraw from BentoBox.
- `ACTION_BENTO_TRANSFER`: Transfer within BentoBox.
- `ACTION_BENTO_TRANSFER_MULTIPLE`: Transfer multiple within BentoBox.
- `ACTION_CALL`: Generic function call.

# SenUSD 

## Summary

- The SenUSD token contract is senUSD_OFT.sol.
- SenUSD inherits from OFT to enable LayerZero bridging
- The admin can mint new tokens to addresses
- Anyone can burn their own tokens  
- Integrates with BentoBox to provide borrowing capacity

### Minting

The admin can mint new tokens using mint(). Minting is rate limited based on time passed and current total supply.

```solidity
function mint(address to, uint256 amount) public onlyOwner
```

To mint tokens into a BentoBox clone:

```solidity  
function mintToBentoBox(address clone, uint256 amount, IBentoBoxV1 bentoBox) public onlyOwner
```

### Burning

Any holder can burn their own tokens using burn().

```solidity
function burn(uint256 _amount) public 
```
