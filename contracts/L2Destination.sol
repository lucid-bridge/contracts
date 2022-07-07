//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { iL2Bridge } from "./interfaces/bridges/iL2Bridge.sol";

contract L2Destination is ReentrancyGuard {
  struct TransferData {
    address tokenAddress;
    address destination;
    uint256 amount;
    uint256 fee;
    uint256 startTime;
    uint256 feeRampup;
  }

  /* ========== Events ========== */

  event TransferBought(
    address indexed tokenAddress,
    address destination,
    uint256 amount,
    uint256 fee,
    uint256 startTime,
    uint256 feeRampup,
    uint256 transferID,
    address indexed buyer
  );

  /* ========== State ========== */

  iL2Bridge private l2Bridge;
  uint256 private remoteChainID;

  mapping(bytes32 => address) public transferOwners;

  constructor(uint256 _remoteChainID, iL2Bridge _l2Bridge) {
    remoteChainID = _remoteChainID;
    l2Bridge = _l2Bridge;
  }

  /* ========== Functions ========== */

  function buy(TransferData memory transferData, uint256 transferID)
    external
    payable
    nonReentrant
  {
    bytes32 transferHash = _hashTransferData(transferData, transferID);
    require(
      transferOwners[transferHash] == address(0),
      "the Owner of transfer is set already"
    );

    uint256 amountMinusFee = transferData.amount -
      getLPFee(transferData, block.timestamp);

    if (transferData.tokenAddress == address(0)) {
      require(msg.value >= amountMinusFee, "Insufficient fund");
      (bool sent, ) = payable(transferData.destination).call{
        value: amountMinusFee
      }("");
      require(sent, "Failed to send Ether");
    } else {
      require(
        IERC20(transferData.tokenAddress).allowance(
          msg.sender,
          address(this)
        ) >= amountMinusFee,
        "Insufficient fund"
      );

      require(
        IERC20(transferData.tokenAddress).transferFrom(
          msg.sender,
          transferData.destination,
          amountMinusFee
        ),
        "Transaction failed"
      );
    }

    transferOwners[transferHash] = msg.sender;

    emit TransferBought(
      transferData.tokenAddress,
      transferData.destination,
      transferData.amount,
      transferData.fee,
      transferData.startTime,
      transferData.feeRampup,
      transferID,
      msg.sender
    );
  }

  function changeOwner(
    TransferData memory transferData,
    uint256 transferID,
    address newOwner
  ) external {
    bytes32 transferHash = _hashTransferData(transferData, transferID);

    if (transferOwners[transferHash] == address(0)) {
      require(
        msg.sender == transferData.destination,
        "Only destination can set owner"
      );
    } else {
      require(
        msg.sender == transferOwners[transferHash],
        "Only the owner of transferData can set newOnwer"
      );
    }

    transferOwners[transferHash] = newOwner;
  }

  function withdraw(
    TransferData memory transferData,
    uint256 transferID,
    bytes32 stateRoot,
    uint256 branchMask,
    bytes32[] memory siblings
  ) external nonReentrant {
    bytes32 transferHash = _hashTransferData(transferData, transferID);
    address owner = transferOwners[transferHash];

    if (owner == address(0)) {
      require(
        msg.sender == transferData.destination,
        "The owner is not set. only destination can withdraw"
      );
    } else {
      require(msg.sender == owner, "Only the owner of transfer can withdraw");
    }

    uint256 amount = transferData.amount;

    if (transferData.tokenAddress == address(0)) {
      require(
        address(this).balance >= amount,
        "Contract does not have enough Ether balance"
      );
    } else {
      require(
        IERC20(transferData.tokenAddress).balanceOf(address(this)) >= amount,
        "Contract does not have enough Token balance"
      );
    }

    bytes memory message = abi.encode(transferData);
    l2Bridge.withdraw(
      transferID,
      remoteChainID,
      message,
      stateRoot,
      branchMask,
      siblings
    );

    if (transferData.tokenAddress == address(0)) {
      (bool sent, ) = payable(owner).call{ value: amount }("");
      require(sent, "Failed to send Ether");
    } else {
      IERC20(transferData.tokenAddress).transfer(owner, amount);
    }

    transferOwners[transferHash] = address(this);
  }

  function getLPFee(TransferData memory transferData, uint256 currentTime)
    public
    pure
    returns (uint256)
  {
    if (currentTime < transferData.startTime) {
      return 0;
    } else if (currentTime >= transferData.startTime + transferData.feeRampup) {
      return transferData.fee;
    } else {
      return
        (transferData.fee * (currentTime - transferData.startTime)) /
        transferData.feeRampup;
    }
  }

  function remoteRootExists(bytes32 rootHashKey) public view returns (bool) {
    return l2Bridge.remoteRoots(rootHashKey);
  }

  function _hashTransferData(
    TransferData memory transferData,
    uint256 transferID
  ) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          transferData.tokenAddress,
          transferData.destination,
          transferData.amount,
          transferData.fee,
          transferData.startTime,
          transferData.feeRampup,
          transferID
        )
      );
  }

  receive() external payable {}
}
