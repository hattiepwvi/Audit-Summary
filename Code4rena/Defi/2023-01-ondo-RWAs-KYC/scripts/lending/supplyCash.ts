import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";

const hre = require("hardhat");
async function main() {
  const cash = await hre.ethers.getContract("mockCash_local");
  const fCash = await hre.ethers.getContract("fCash");
  const signers = await hre.ethers.getSigners();
  await cash.approve(fCash.address, BigNumber.from("100000000000000000000"));
  await fCash.mint(BigNumber.from("100000000000000000000"));
  console.log(`The signers address is: ${signers[0].address}`);
  console.log(
    `The fCASH balance is: ${(
      await fCash.balanceOf(signers[0].address)
    ).toString()}`
  );
}
main();
