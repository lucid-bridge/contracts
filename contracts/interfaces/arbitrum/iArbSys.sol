//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iArbSys {
    function sendTxToL1(address destination, bytes calldata calldataForL1)
        external
        payable
        returns (uint256);

    function withdrawEth(address destination) external payable;
}
