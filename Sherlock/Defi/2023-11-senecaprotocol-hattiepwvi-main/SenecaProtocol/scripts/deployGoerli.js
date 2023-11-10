const hre = require("hardhat");
const { Contract } = require("hardhat/internal/hardhat-network/stack-traces/model");
const fs = require('fs');

async function main() {
  const WETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"; //WETH on goerli
  const treasury = "0x1D47E02b7C7db3A97eD44ab847F8D073Adb433B3"; //fee/interest taker
  const ORACLE_KEY = "ETH/USD";
  const ETHUSD_ORACLE = "0xb70CA068486444b569DEB64D9D3807CBEC3Bf520"; //TODO CHANGE, this is DIA Oracle

  // bentobox deployment
  const bento = await hre.ethers.getContractFactory("BentoBoxV1");
  console.log('bentobox deploying...')
  const bentobox = await bento.deploy(WETH);
  await bentobox.deployed();

  // Chamber and senUSD deployment
  const chamber = await hre.ethers.getContractFactory("ChamberFlat");
  const senUsd = await hre.ethers.getContractFactory("SenecaUSD");
  console.log('senUSD deploying...')
  const senUSD = await senUsd.deploy();
  await senUSD.deployed();
  console.log('chamber deploying...')
  const Chamber = await chamber.deploy(bentobox.address, senUSD.address);
  await Chamber.deployed();
  await Chamber.setFeeTo(treasury);
  //whitelist 
  await bentobox.whitelistMasterContract(Chamber.address, true);

  console.log(
    `BentoBox Successfully Deployed`, bentobox.address
  );

  console.log(
    `Chamber Contract Successfully Deployed`, Chamber.address
  );

  console.log(
    `SenUSD Contract Successfully Deployed`, senUSD.address
  );

  const BentoBox = await ethers.getContractAt("BentoBoxV1", bentobox.address);
  const ChamberMasterContract = Chamber.address; // Chamber

  // Deploying Clone Contract ////////////////////////////////////////////////////////////////////   WETH
  const Oracle = await hre.ethers.getContractFactory("SenecaOracle");
  const oracleContract = await Oracle.deploy(ETHUSD_ORACLE, ORACLE_KEY);

  const collateral = WETH; // wETH
  const oracleData = "0x0000000000000000000000000000000000000000";

  /// let INTEREST_CONVERSION = 1e18/(365.25*3600*24)/100
  let interest = parseInt(158440439)
  const OPENING_CONVERSION = 1e5/100
  const opening = 0.5 * OPENING_CONVERSION
  const liquidation = 4 * 1e3+1e5
  const collateralization = 90 * 1e3

  let initData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "bytes", "uint64", "uint256", "uint256", "uint256"],
    [collateral, oracleContract.address, oracleData, interest, liquidation, collateralization, opening]
  );

  console.log('initialising chamber...');
  const initChamber = Chamber.attach(Chamber.address);
  await (await initChamber.init(initData)).wait();
  console.log('initialised chamber');
  console.log('deploying clone...');
  const tx = await (await BentoBox.deploy(ChamberMasterContract, initData, true)).wait();

  const deployEvent = tx?.events?.[0];
  console.log('Clone contract Successfully Deployed: ', deployEvent.args.cloneAddress);
  ////////////////////////////////////////////////////////////////////////////////////////////

  console.log('deploying Market Lens...')
  const marketLens = await hre.ethers.getContractFactory("MarketLens");
  const MarketLensV2 = await marketLens.deploy();
  
  await MarketLensV2.deployed();
  console.log('Market Lens Successfully Deployed: ', MarketLensV2.address);

  console.log('deploying Registry Contract...')
  const registry = await hre.ethers.getContractFactory("stableEngineMap");
  const RegistryContract = await registry.deploy(deployEvent.args.cloneAddress);
  await RegistryContract.deployed();

  console.log('Registry Successfully Deployed: ', RegistryContract.address);

  await RegistryContract.addCollateralInfo(WETH, deployEvent.args.cloneAddress);
  
  //clone address, amount = 10000 ether, bentobox address
  await senUSD.fundBentoBox(deployEvent.args.cloneAddress, bentobox.address);

  //Deployments

  const deployments = {
    BentoBox: {
        address: bentobox.address,
        parameters: [WETH]
    },
    SenUSD: {
        address: senUSD.address,
        parameters: [] // Empty array since no parameters for deployment
    },
    Chamber: {
        address: Chamber.address,
        parameters: [bentobox.address, senUSD.address]
    },
    CloneContract: { // Name this appropriately
        address: deployEvent.args.cloneAddress,
        parameters: [ChamberMasterContract, initData, true]
    },
    CloneOracle: { // Name this appropriately
        address: oracleContract.address,
        parameters: [ETHUSD_ORACLE]
    },
    MarketLensV2: {
        address: MarketLensV2.address,
        parameters: [] // Empty array since no parameters for deployment
    }
};

// Save the deployments to JSON file
fs.writeFileSync('deploymentsGoerli.json', JSON.stringify(deployments, null, 2));

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
