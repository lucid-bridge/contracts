//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iBridge {
    function activeOutbox() external view returns (address);
}
