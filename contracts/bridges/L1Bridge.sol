//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/bridges/iL2Bridge.sol";
import {iOVMCrossDomainMessenger} from "../interfaces/optimism/iOVMCrossDomainMessenger.sol";
import {iOVML1StandardBridge} from "../interfaces/optimism/iOVML1StandardBridge.sol";
import {iInbox} from "../interfaces/arbitrum/iInbox.sol";
import {iOutbox} from "../interfaces/arbitrum/iOutbox.sol";

contract L1Bridge is Ownable, ReentrancyGuard {
    /* ========== State ========== */

    mapping(bytes32 => bool) public roots;
    mapping(uint256 => address) public bridgeByChainId;
    mapping(uint256 => uint32) public bridgeTypeByChainId;
    mapping(uint256 => address) public bridgeMessengerByChainId;
    mapping(address => mapping(uint256 => address)) public validAddressPairs; //Source-Destination contracts valid pairs

    mapping(string => mapping(uint256 => address)) private tokenL2Addresses;

    iOVML1StandardBridge public OVML1StandardBridge;

    constructor(
        address[] memory bridges,
        uint256[] memory chainIDs,
        uint32[] memory bridgeTypes,
        address[] memory messengers,
        iOVML1StandardBridge _OVML1StandardBridge
    ) {
        require(
            bridges.length == chainIDs.length &&
                bridges.length == bridgeTypes.length &&
                bridges.length == messengers.length
        );

        for (uint256 i = 0; i < bridges.length; i++) {
            setBridge(bridges[i], chainIDs[i], bridgeTypes[i], messengers[i]);
        }

        OVML1StandardBridge = _OVML1StandardBridge;
    }

    /* ========== Functions ========== */

    function sendToL2(
        bytes32 root,
        uint256 chainID,
        uint256[] memory toChainIDs
    ) public {
        bytes32 rootHash = keccak256(abi.encode(root, chainID));
        require(roots[rootHash], "Root is not valid");
        for (uint256 i = 0; i < toChainIDs.length; i++) {
            uint256 chainId = toChainIDs[i];
            uint256 bridgeType = bridgeTypeByChainId[chainId];
            address bridgeAddress = bridgeByChainId[chainId];
            address messenger = bridgeMessengerByChainId[chainId];

            bytes memory data = abi.encodeWithSignature(
                "addRemoteRoot(bytes32, uint256)",
                root,
                chainID
            );

            if (bridgeType == 0) {
                //Test
                iL2Bridge(bridgeAddress).addRemoteRoot(root, chainID);
            } else if (bridgeType == 1) {
                //Optimism
                iOVMCrossDomainMessenger(messenger).sendMessage(
                    bridgeAddress,
                    data,
                    1000000
                );
            } else if (bridgeType == 2) {
                //Arbitrum
                iInbox inbox = iInbox(messenger);
                inbox.createRetryableTicket(
                    bridgeAddress,
                    0,
                    0,
                    msg.sender,
                    msg.sender,
                    1000000,
                    0,
                    data
                );
            }
        }
    }

    function update(bytes32 root, uint256 chainID) public {
        uint256 bridgeType = bridgeTypeByChainId[chainID];
        address bridgeAddress = bridgeByChainId[chainID];
        address messenger = bridgeMessengerByChainId[chainID];

        if (bridgeType == 0) {
            //Test
            require(bridgeAddress == msg.sender);
        } else if (bridgeType == 1) {
            //Optimism
            require(
                msg.sender == messenger &&
                    iOVMCrossDomainMessenger(messenger)
                        .xDomainMessageSender() ==
                    bridgeAddress
            );
        } else if (bridgeType == 2) {
            //Arbitrum
            iInbox inbox = iInbox(messenger);
            iOutbox outbox = iOutbox(inbox.bridge().activeOutbox());
            require(
                msg.sender == address(outbox) &&
                    bridgeAddress == outbox.l2ToL1Sender()
            );
        } else {
            assert(false);
        }

        roots[keccak256(abi.encode(root, chainID))] = true;
    }

    function updateAndSend(
        bytes32 root,
        uint256 chainID,
        uint256[] memory toChainIDs
    ) public {
        update(root, chainID);
        sendToL2(root, chainID, toChainIDs);
    }

    function regularSendToL2(
        address l1TokenAddress,
        address l2TokenAddress,
        uint256 amount,
        uint256 chainID,
        uint256 remoteChainID
    ) external payable nonReentrant {
        uint256 bridgeType = bridgeTypeByChainId[chainID];
        address messenger = bridgeMessengerByChainId[chainID];
        address destination;

        if (bridgeType == 0) {
            destination = validAddressPairs[msg.sender][remoteChainID];

            //Test
            require(
                destination != address(0),
                "Only valid contracts can transfer funds"
            );
        } else if (bridgeType == 1) {
            destination = validAddressPairs[
                iOVMCrossDomainMessenger(messenger).xDomainMessageSender()
            ][remoteChainID];

            //Optimism
            require(
                msg.sender == messenger && destination != address(0),
                "Only valid contracts can transfer funds"
            );
        } else if (bridgeType == 2) {
            //Arbitrum
            //TODO: arbitrum support
        } else {
            assert(false);
        }

        uint256 destinationBridgeType = bridgeTypeByChainId[remoteChainID];

        if (l1TokenAddress == address(0)) {
            if (destinationBridgeType == 0) {
                //Test
                (bool sent, ) = payable(destination).call{value: amount}("");
                require(sent, "Failed to send Ether");
            } else if (destinationBridgeType == 1) {
                //Optimism
                OVML1StandardBridge.depositETHTo{value: amount}(
                    destination,
                    1000000,
                    "0x"
                );
            } else if (destinationBridgeType == 2) {
                iInbox inbox = iInbox(messenger);
                inbox.depositEth{value: amount}(destination);
            } else {
                assert(false);
            }
        } else {
            //TODO: add token transfer support
            assert(false);
        }
    }

    function addAddressPair(
        address source,
        address destination,
        uint256 destinationChainID
    ) external onlyOwner {
        validAddressPairs[source][destinationChainID] = destination;
    }

    function setBridge(
        address bridge,
        uint256 chainID,
        uint32 bridgeType,
        address messenger
    ) public onlyOwner {
        bridgeByChainId[chainID] = bridge;
        bridgeTypeByChainId[chainID] = bridgeType;
        bridgeMessengerByChainId[chainID] = messenger;
    }

    receive() external payable {}
}
