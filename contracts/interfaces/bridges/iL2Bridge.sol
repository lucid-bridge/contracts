//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { iL1Bridge } from "./iL1Bridge.sol";
import { iOVML2StandardBridge } from "../optimism/iOVML2StandardBridge.sol";

interface iL2Bridge {
  function send(bytes memory message, uint256 toChainId)
    external
    returns (uint256 nonce);

  function withdraw(
    uint256 transferID,
    uint256 fromChainId,
    bytes memory message,
    bytes32 rootHash,
    uint256 branchMask,
    bytes32[] memory siblings
  ) external;

  function updateL2Bridges(uint256[] memory toChainIDs) external;

  function getChainID() external view returns (uint256);

  function getMessageProof(
    uint256 transferID,
    uint256 toChainId,
    bytes memory message
  )
    external
    view
    returns (
      bytes32 rootHash,
      uint256 branchMask,
      bytes32[] memory siblings
    );

  function addRemoteRoot(bytes32 root, uint256 chainID) external;

  function regularTransfer(
    address tokenAddress,
    address l1TokenAddress,
    address remoteChainTokenAddress,
    uint256 amount,
    uint256 remoteChainID
  ) external payable;

  function l1Bridge() external view returns (iL1Bridge);

  function bridgeType() external view returns (uint32);

  function OVML2StandardBridge() external view returns (iOVML2StandardBridge);

  function OVML2CrossDomainMessenger() external view returns (address);

  function getRootHash() external view returns (bytes32);

  function remoteRoots(bytes32 arg0) external view returns (bool);
}
