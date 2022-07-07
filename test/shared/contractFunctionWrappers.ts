import { BigNumber } from "ethers";
import { ethers } from "hardhat";

const zeroAddress = ethers.constants.AddressZero;

export async function executeDeployL1Bridge() {
  const L1Bridge = await ethers.getContractFactory("L1Bridge");
  const l1Bridge = await L1Bridge.deploy([], [], [], [], zeroAddress);
  await l1Bridge.deployed();
  return l1Bridge;
}

export async function executeDeployL2Bridge(
  l1Bridge: string,
  bridgeType: number
) {
  const L2Bridge = await ethers.getContractFactory("L2Bridge");
  const l2Bridge = await L2Bridge.deploy(l1Bridge, bridgeType);
  await l2Bridge.deployed();
  return l2Bridge;
}

export async function executeDeploySource(
  remoteChainId: BigNumber,
  l2Bridge: string
) {
  const L2Source = await ethers.getContractFactory("L2Source");
  const l2Source = await L2Source.deploy(remoteChainId, l2Bridge, [], [], []);
  await l2Source.deployed();
  return l2Source;
}

export async function executeDeployDestination(
  remoteChainId: BigNumber,
  l2Bridge: string
) {
  const L2Destination = await ethers.getContractFactory("L2Destination");
  const l2Destination = await L2Destination.deploy(remoteChainId, l2Bridge);
  await l2Destination.deployed();
  return l2Destination;
}

export async function executeDeployContracts() {
  // For testing, all the contracts will be deployed on the same network

  // Deploy l1 bridge
  const l1Bridge = await executeDeployL1Bridge();

  // Deploy l2 bridges
  const l2SourceBridge = await executeDeployL2Bridge(l1Bridge.address, 0);
  const l2DestinationBridge = await executeDeployL2Bridge(l1Bridge.address, 0);

  const sourceChainId = await l2SourceBridge.getChainID();
  const destinationChainId = await l2DestinationBridge.getChainID();

  // Deploy l2 source
  const source = await executeDeploySource(
    destinationChainId,
    l2SourceBridge.address
  );

  // Deploy l2 destination
  const destination = await executeDeployDestination(
    sourceChainId,
    l2DestinationBridge.address
  );

  // set L2 bridges on l1Bridge
  await l1Bridge.setBridge(
    l2SourceBridge.address,
    sourceChainId,
    0,
    zeroAddress
  );

  await l1Bridge.setBridge(
    l2DestinationBridge.address,
    destinationChainId,
    0,
    zeroAddress
  );

  await l2SourceBridge.addPermittedAddress(source.address);

  await l1Bridge.addAddressPair(
    l2SourceBridge.address,
    destination.address,
    destinationChainId
  );

  await l2DestinationBridge.addPermittedAddress(destination.address);

  return {
    l1Bridge,
    l2SourceBridge,
    l2DestinationBridge,
    source,
    destination,
    sourceChainId,
    destinationChainId,
  };
}
