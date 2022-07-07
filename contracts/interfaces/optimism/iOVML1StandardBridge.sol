//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iOVML1StandardBridge {
    function depositETHTo(
        address _to,
        uint32 _l2Gas,
        bytes calldata _data
    ) external payable;
}
