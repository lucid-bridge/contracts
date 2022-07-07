//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {iBridge} from "./iBridge.sol";

interface iInbox {
    function createRetryableTicket(
        address destAddr,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes memory data
    ) external returns (uint256);

    function bridge() external view returns (iBridge);

    function depositEth(address destAddr) external payable returns (uint256);
}
