import * as dotenv from "dotenv";
import { writeFileSync } from "fs";
import { executeDeployContracts } from "../test/shared/contractFunctionWrappers";

dotenv.config();

async function main() {
  const {
    source,
    destination,
    l1Bridge,
    l2DestinationBridge,
    l2SourceBridge,
    sourceChainId,
    destinationChainId,
  } = await executeDeployContracts();

  const data = `const sourceAddress = "${source.address}"
const destinationAddress = "${destination.address}"

export { sourceAddress, destinationAddress }
    `;

  writeFileSync("../frontend/config/contracts.ts", data);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
