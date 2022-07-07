import { expect } from "chai";
import { ethers } from "hardhat";
import { executeDeployContracts } from "./shared/contractFunctionWrappers";

const zeroAddress = ethers.constants.AddressZero;

describe("Bridge", () => {
  it("should", async () => {
    const [_, user1, user2, user3, user4] = await ethers.getSigners();

    // user1 wants to send 1 ETH from L2 source to user2 in L2 destination.
    // user3 is a liquidity provider.
    // user4 will transfer all token balance to destination

    const {
      source,
      l2SourceBridge,
      l2DestinationBridge,
      destination,
      sourceChainId,
      destinationChainId,
    } = await executeDeployContracts();

    console.log(
      "Alice balance before transfer initiation:",
      await user1.getBalance()
    );

    const amount = ethers.utils.parseEther("1");
    const amountPlusFee = amount.mul(10005).div(10000);
    const fee = ethers.utils.parseEther("0.1");
    const startTime = Math.round(new Date().getTime() / 1000) + 1;
    const feeRampup = 10;

    const transferData = {
      tokenAddress: zeroAddress,
      destination: user2.address,
      amount,
      fee,
      startTime,
      feeRampup,
    };

    // Alice call Withdraw function on L2 source
    let tx = await source
      .connect(user1)
      .withdraw(transferData, { value: amountPlusFee });
    await tx.wait();

    console.log(
      "Alice balance after transfer initiation:",
      await user1.getBalance()
    );

    // Check bounty pool
    const sourceBountyPool = await source.tokenBountyPool(zeroAddress);
    expect(sourceBountyPool).to.eq(amountPlusFee.sub(amount));

    // Check the logs
    const filter = source.filters.TransferInitiated();

    const logs = await ethers.provider.getLogs(filter);

    const events = logs.map((log) => {
      return source.interface.parseLog(log);
    });
    expect(events.length).to.greaterThan(0);

    const transferInitiatedEvent = events[0];

    const rootHashKey = await source.getRootHashKey();

    const abiCoder = new ethers.utils.AbiCoder();

    // Updating rootHash on the destination side
    tx = await l2SourceBridge.updateL2Bridges([destinationChainId]);
    await tx.wait();

    // check if rootHash get updated on the destination side
    expect(await destination.remoteRootExists(rootHashKey)).to.true;

    console.log("user3 is about to buy the transfer");
    console.log(
      "user3 balacne before buying the transfer:",
      await user3.getBalance()
    );
    console.log(
      "user2 balance before user3 buys the transfer:",
      await user2.getBalance()
    );

    const transferId: number =
      transferInitiatedEvent.args.transferID.toNumber();
    console.log("transfer ID is:", transferId);

    await ethers.provider.send("evm_increaseTime", [2000]);
    await ethers.provider.send("evm_mine", []);

    const timestamp = (await ethers.provider.getBlock("latest")).timestamp;

    const LPFee = await destination.getLPFee(transferData, timestamp);
    console.log("LPFee:", LPFee);

    tx = await destination
      .connect(user3)
      .buy(transferData, transferId, { value: transferData.amount.sub(LPFee) });
    await tx.wait();

    console.log(
      "user3 balacne after buying the transfer:",
      await user3.getBalance()
    );
    console.log(
      "user2 balance after user3 buys the transfer:",
      await user2.getBalance()
    );

    const transferHash = ethers.utils.keccak256(
      abiCoder.encode(
        [
          "address",
          "address",
          "uint256",
          "uint256",
          "uint256",
          "uint256",
          "uint256",
        ],
        [
          transferData.tokenAddress,
          transferData.destination,
          transferData.amount,
          transferData.fee,
          transferData.startTime,
          transferData.feeRampup,
          transferId,
        ]
      )
    );

    // Check if user3 is the owner of transfer
    const transferOwnerAddress = await destination.transferOwners(transferHash);
    expect(transferOwnerAddress).to.eq(user3.address);

    // Moving source contract Ether balance to destination
    const transferTokenBalanceGas =
      await source.estimateGas.transferTokenBalanceToRemote(zeroAddress);
    const gasPrice = await ethers.provider.getGasPrice();

    console.log(
      "transferTokenBalanceGasPrice:",
      transferTokenBalanceGas.mul(gasPrice)
    );
    console.log("bounty pool:", await source.tokenBountyPool(zeroAddress));

    console.log(
      "user4 balance before transferring token balance:",
      await user4.getBalance()
    );

    tx = await source.connect(user4).transferTokenBalanceToRemote(zeroAddress);
    await tx.wait();

    console.log(
      "user4 balance after transferring token balance:",
      await user4.getBalance()
    );

    console.log("bounty pool:", await source.tokenBountyPool(zeroAddress));

    const message = abiCoder.encode(
      ["address", "address", "uint256", "uint256", "uint256", "uint256"],
      [
        transferData.tokenAddress,
        transferData.destination,
        transferData.amount,
        transferData.fee,
        transferData.startTime,
        transferData.feeRampup,
      ]
    );

    const messageProof = await l2SourceBridge.getMessageProof(
      transferId,
      destinationChainId,
      message
    );

    const rHash = messageProof.rootHash;
    const branchMask = messageProof.branchMask;
    const siblings = messageProof.siblings;

    console.log(
      "destination contract balance before withdraw:",
      await ethers.provider.getBalance(destination.address)
    );

    tx = await destination
      .connect(user3)
      .withdraw(transferData, transferId, rHash, branchMask, siblings);
    await tx.wait();

    console.log("user3 balance after withdraw:", await user3.getBalance());
    console.log(
      "destination contract balance after withdraw:",
      await ethers.provider.getBalance(destination.address)
    );
  });
});
