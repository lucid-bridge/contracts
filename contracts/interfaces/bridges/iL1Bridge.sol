//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iL1Bridge {
    function setBridge(
        address bridge,
        uint256 chainID,
        uint32 bridgeType,
        address messenger
    ) external;

    function sendToL2(
        bytes32 root,
        uint256 chainID,
        uint256[] memory toChainIDs
    ) external;

    function update(bytes32 root, uint256 chainID) external;

    function updateAndSend(
        bytes32 root,
        uint256 chainID,
        uint256[] memory toChainIDs
    ) external;

    function regularSendToL2(
        address l1TokenAddress,
        address l2TokenAddress,
        uint256 amount,
        uint256 chainID,
        uint256 remoteChainID
    ) external payable;
}
