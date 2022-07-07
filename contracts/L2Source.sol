//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { iL2Bridge } from "./interfaces/bridges/iL2Bridge.sol";
import { iOVML2StandardBridge } from "./interfaces/optimism/iOVML2StandardBridge.sol";
import { iOVMCrossDomainMessenger } from "./interfaces/optimism/iOVMCrossDomainMessenger.sol";
import { iArbSys } from "./interfaces/arbitrum/iArbSys.sol";
import { iL1Bridge } from "./interfaces/bridges/iL1Bridge.sol";

contract L2Source is Ownable, ReentrancyGuard {
  struct TransferData {
    address tokenAddress;
    address destination;
    uint256 amount;
    uint256 fee;
    uint256 startTime;
    uint256 feeRampup;
  }

  /* ========== Events ========== */

  event TransferInitiated(
    address indexed tokenAddress,
    address destination,
    uint256 amount,
    uint256 fee,
    uint256 startTime,
    uint256 feeRampup,
    uint256 transferID,
    address indexed self
  );

  /* ========== Constants ========== */

  uint8 constant CONTRACT_FEE_BASIS_POINTS = 5;

  /* ========== State ========== */

  uint256 private remoteChainId;
  iL2Bridge private l2Bridge;

  //get token address on L1 and "Remote chain L2" by token address on current chain
  mapping(address => address) public tokenL1Address;
  mapping(address => address) public tokenRemoteChainAddress;

  // token address => bounty pool
  mapping(address => uint256) public tokenBountyPool;

  constructor(
    uint256 _remoteChainId,
    iL2Bridge _l2Bridge,
    address[] memory tokenAddresses,
    address[] memory tokenL1Addresses,
    address[] memory tokenRemoteChainAddresses
  ) {
    require(
      tokenAddresses.length == tokenL1Addresses.length &&
        tokenAddresses.length == tokenRemoteChainAddresses.length
    );

    remoteChainId = _remoteChainId;
    l2Bridge = _l2Bridge;

    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      setToken(
        tokenAddresses[i],
        tokenL1Addresses[i],
        tokenRemoteChainAddresses[i]
      );
    }
  }

  /* ========== Functions ========== */

  function withdraw(TransferData memory transferData)
    external
    payable
    nonReentrant
  {
    uint256 amountPlusFee = getAmountPlusFee(transferData.amount);
    uint256 fee = amountPlusFee - transferData.amount;

    if (transferData.tokenAddress == address(0)) {
      //ETH
      require(msg.value == amountPlusFee, "Insufficient fund");
    } else {
      //Token
      require(
        IERC20(transferData.tokenAddress).allowance(
          msg.sender,
          address(this)
        ) >= amountPlusFee,
        "Insufficient fund"
      );

      require(
        IERC20(transferData.tokenAddress).transferFrom(
          msg.sender,
          address(this),
          amountPlusFee
        ),
        "Transaction failed. Failed to transfer fund"
      );
    }

    bytes memory message = abi.encode(
      transferData.tokenAddress,
      transferData.destination,
      transferData.amount,
      transferData.fee,
      transferData.startTime,
      transferData.feeRampup
    );

    uint256 transferID = l2Bridge.send(message, remoteChainId);

    tokenBountyPool[transferData.tokenAddress] += fee;

    emit TransferInitiated(
      transferData.tokenAddress,
      transferData.destination,
      transferData.amount,
      transferData.fee,
      transferData.startTime,
      transferData.feeRampup,
      transferID,
      address(this)
    );
  }

  function transferTokenBalanceToRemote(address tokenAddress)
    public
    nonReentrant
  {
    if (tokenAddress == address(0)) {
      //ETH
      uint256 bountyAmount = tokenBountyPool[tokenAddress];
      uint256 etherBalance = address(this).balance;
      uint256 amountToTransfer = etherBalance - bountyAmount;
      require(amountToTransfer > 0, "Contract Ether balance is 0");

      l2Bridge.regularTransfer{ value: amountToTransfer }(
        tokenAddress, // 0
        tokenL1Address[tokenAddress], // 0
        tokenRemoteChainAddress[tokenAddress], // 0
        amountToTransfer,
        remoteChainId
      );

      (bool sent, ) = payable(msg.sender).call{ value: bountyAmount }("");
      require(sent, "Failed to send Ether");
    } else {
      //Token
      uint256 bountyAmount = tokenBountyPool[tokenAddress];
      uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
      uint256 amountToTransfer = tokenBalance - bountyAmount;
      require(amountToTransfer > 0, "Contract Token balance is 0");

      IERC20(tokenAddress).transfer(address(l2Bridge), amountToTransfer);

      l2Bridge.regularTransfer(
        tokenAddress,
        tokenL1Address[tokenAddress],
        tokenRemoteChainAddress[tokenAddress],
        amountToTransfer,
        remoteChainId
      );

      IERC20(tokenAddress).transfer(msg.sender, bountyAmount);
    }

    tokenBountyPool[tokenAddress] = 0;
  }

  function updateRemoteRoot() public {
    uint256[] memory remoteChainIds = new uint256[](1);
    remoteChainIds[0] = remoteChainId;
    return l2Bridge.updateL2Bridges(remoteChainIds);
  }

  function getMessageProof(uint256 transferID, bytes memory message)
    public
    view
    returns (
      bytes32 rootHash,
      uint256 branchMask,
      bytes32[] memory siblings
    )
  {
    return l2Bridge.getMessageProof(transferID, remoteChainId, message);
  }

  function getRootHashKey() public view returns (bytes32) {
    bytes32 rootHash = l2Bridge.getRootHash();
    uint256 chainID = l2Bridge.getChainID();
    return keccak256(abi.encode(rootHash, chainID));
  }

  function setToken(
    address _tokenAddress,
    address _tokenL1Address,
    address _tokenRemoteChainAddress
  ) public onlyOwner {
    tokenL1Address[_tokenAddress] = _tokenL1Address;
    tokenRemoteChainAddress[_tokenAddress] = _tokenRemoteChainAddress;
  }

  function getAmountPlusFee(uint256 amount) public pure returns (uint256) {
    return (amount * (10000 + CONTRACT_FEE_BASIS_POINTS)) / 10000;
  }
}
