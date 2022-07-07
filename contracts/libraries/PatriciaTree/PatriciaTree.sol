//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Data} from "./Data.sol";
import {Bits} from "../bits/Bits.sol";

contract PatriciaTree {
    using Data for Data.Tree;
    using Data for Data.Node;
    using Data for Data.Edge;
    using Data for Data.Label;
    using Bits for uint256;

    Data.Tree internal tree;

    // Get the root hash.
    function getRootHash() external view returns (bytes32) {
        return tree.root;
    }

    // Get the root edge.
    function getRootEdge() external view returns (Data.Edge memory e) {
        e = tree.rootEdge;
    }

    // Get the node with the given key. The key needs to be
    // the keccak256 hash of the actual key.
    function getNode(bytes32 hash) external view returns (Data.Node memory n) {
        n = tree.nodes[hash];
    }

    // Returns the Merkle-proof for the given key
    // Proof format should be:
    //  - uint branchMask - bitmask with high bits at the positions in the key
    //                    where we have branch nodes (bit in key denotes direction)
    //  - bytes32[] _siblings - hashes of sibling edges
    function getProof(bytes memory key)
        public
        view
        returns (uint256 branchMask, bytes32[] memory _siblings)
    {
        require(tree.root != 0);
        Data.Label memory k = Data.Label(keccak256(key), 256);
        Data.Edge memory e = tree.rootEdge;
        bytes32[256] memory siblings;
        uint256 length;
        uint256 numSiblings;
        while (true) {
            (Data.Label memory prefix, Data.Label memory suffix) = k
                .splitCommonPrefix(e.label);
            assert(prefix.length == e.label.length);
            if (suffix.length == 0) {
                // Found it
                break;
            }
            length += prefix.length;
            branchMask |= uint256(1) << (255 - length);
            length += 1;
            (uint256 head, Data.Label memory tail) = suffix.chopFirstBit();
            siblings[numSiblings++] = tree
                .nodes[e.node]
                .children[1 - head]
                .edgeHash();
            e = tree.nodes[e.node].children[head];
            k = tail;
        }
        if (numSiblings > 0) {
            _siblings = new bytes32[](numSiblings);
            for (uint256 i = 0; i < numSiblings; i++) {
                _siblings[i] = siblings[i];
            }
        }
    }

    function verifyProof(
        bytes32 rootHash,
        bytes memory key,
        bytes memory value,
        uint256 branchMask,
        bytes32[] memory siblings
    ) public pure returns (bool) {
        Data.Label memory k = Data.Label(keccak256(key), 256);
        Data.Edge memory e;
        e.node = keccak256(value);
        for (uint256 i = 0; branchMask != 0; i++) {
            uint256 bitSet = branchMask.lowestBitSet();
            branchMask &= ~(uint256(1) << bitSet);
            (k, e.label) = k.splitAt(255 - bitSet);
            uint256 bit;
            (bit, e.label) = e.label.chopFirstBit();
            bytes32[2] memory edgeHashes;
            edgeHashes[bit] = e.edgeHash();
            edgeHashes[1 - bit] = siblings[siblings.length - i - 1];
            e.node = keccak256(abi.encode(edgeHashes));
        }
        e.label = k;
        require(rootHash == e.edgeHash());
        return true;
    }

    function insert(bytes memory key, bytes memory value) internal {
        tree.insert(key, value);
    }
}
