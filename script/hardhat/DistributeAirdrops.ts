import { getContractAt } from "./utils/helpers";
import { AirdropDistributor } from "../../artifacts/types";
import { ethers } from "hardhat";
import path from "path";
import * as fs from "fs";
import Decimal from "decimal.js";

async function main() {
  const BATCH_SIZE = 10;

  // parse contract
  const root = path.resolve(__dirname, "../");
  const rawContractData = fs.readFileSync(
    `${root}/constants/output/DeployCore-${process.env.OUTPUT_FILENAME}`
  );
  const contractData = JSON.parse(rawContractData.toString());
  const distributor = await getContractAt<AirdropDistributor>(
    "AirdropDistributor",
    contractData.AirdropDistributor
  );

  // parse airdrop information
  const rawdata = fs.readFileSync(
    `${root}/constants/${process.env.AIRDROPS_FILENAME}`
  );
  const data = JSON.parse(rawdata.toString()).airdrop;
  const addresses: string[] = data.map((entry: any) => entry.owner);
  const values: Decimal[] = data.map(
    (entry: any) => new Decimal(entry.airdrop)
  );
  const sum: Decimal = values.reduce(
    (total, currentAmount) => total.plus(currentAmount),
    new Decimal(0)
  );
  const expected = new Decimal(200_000_000 * 1e18);
  if (sum.greaterThan(expected)) {
    const diff = sum.minus(expected); // calculate difference, will be dust
    values[0] = values[0].minus(diff); // remove from very first value
  }

  const amounts: string[] = values.map((entry: Decimal) => entry.toFixed()); // remove scientific notation

  let count = 0;
  for (let i = 0; i < addresses.length; i += BATCH_SIZE) {
    const end = Math.min(i + BATCH_SIZE, addresses.length);
    const addressBatch = addresses.slice(i, end);
    const amountBatch = amounts.slice(i, end);

    const feeData: ethers.types.FeeData = await ethers.provider.getFeeData();
    const tx = await distributor.distributeTokens(addressBatch, amountBatch, {
      gasLimit: 15000000,
      maxPriorityFeePerGas: feeData.lastBaseFeePerGas.div(50),
    });

    count++;
    console.log("Tx No.:", count);
    console.log("Transaction sent:", tx.hash);
    await tx.wait();
    console.log("Transaction confirmed:", tx.hash);
  }

  await distributor.renounceOwnership();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
