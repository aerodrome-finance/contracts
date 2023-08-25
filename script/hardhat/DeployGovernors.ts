import { getContractAt, deploy } from "./utils/helpers";
import { ProtocolGovernor, EpochGovernor } from "../../artifacts/types";
import jsonConstants from "../constants/Base.json";
import deployedContracts from "../constants/output/ProtocolOutput.json";

async function main() {
  const governor = await deploy<ProtocolGovernor>(
    "ProtocolGovernor",
    undefined,
    deployedContracts.votingEscrow
  );
  const epochGovernor = await deploy<EpochGovernor>(
    "EpochGovernor",
    undefined,
    deployedContracts.forwarder,
    deployedContracts.votingEscrow,
    deployedContracts.minter
  );

  await governor.setVetoer(jsonConstants.team);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
