// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iOVMCrossDomainMessenger {
    event SentMessage(bytes message);

    function xDomainMessageSender() external view returns (address);

    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}
