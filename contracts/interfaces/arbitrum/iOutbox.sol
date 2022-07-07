//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iOutbox {
    function l2ToL1Sender() external view returns (address);
}
