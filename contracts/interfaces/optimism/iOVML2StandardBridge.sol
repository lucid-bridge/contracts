//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iOVML2StandardBridge {
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _l1Gas,
        bytes calldata _data
    ) external;
}
