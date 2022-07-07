//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../libraries/PatriciaTree/PatriciaTree.sol";

import { iOVMCrossDomainMessenger } from "../interfaces/optimism/iOVMCrossDomainMessenger.sol";
import { iArbSys } from "../interfaces/arbitrum/iArbSys.sol";
import { iOVML2StandardBridge } from "../interfaces/optimism/iOVML2StandardBridge.sol";
import { iL1Bridge } from "../interfaces/bridges/iL1Bridge.sol";

contract L2Bridge is PatriciaTree, Ownable {
  /* ========== Constants ========== */

  address constant OVML2CrossDomainMessenger =
    0x4200000000000000000000000000000000000007;

  address public constant OVML2ETHTokenAddress =
    0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000;

  iOVML2StandardBridge constant OVML2StandardBridge =
    iOVML2StandardBridge(0x4200000000000000000000000000000000000010);

  /* ========== State ========== */

  using Counters for Counters.Counter;
  Counters.Counter private nextTransferID;
  mapping(bytes32 => bool) public remoteRoots;
  mapping(bytes32 => bool) private withdrawn;
  mapping(address => bool) private isPermittedAddress;

  iL1Bridge public l1Bridge;
  uint8 public bridgeType; // 0 -> Test, 1 -> Optimism, 2 -> Arbitrum

  iArbSys arbSys = iArbSys(address(100));

  constructor(iL1Bridge _l1Bridge, uint8 _bridgeType) {
    l1Bridge = _l1Bridge;
    bridgeType = _bridgeType;
    isPermittedAddress[msg.sender] = true;
  }

  /* ========== Modifiers ========== */

  modifier permittedAddress(address _addr) {
    require(isPermittedAddress[_addr], "Permission denied");
    _;
  }

  /* ========== Functions ========== */

  // Insert the TransferData to the tree
  function send(bytes memory message, uint256 toChainId)
    public
    permittedAddress(msg.sender)
    returns (uint256)
  {
    nextTransferID.increment();
    uint256 transferID = nextTransferID.current();

    bytes32 key = getHash(transferID, getChainID(), toChainId, message);
    insert(abi.encode(key), message);

    return transferID;
  }

  function updateL2Bridges(uint256[] memory toChainIDs) public {
    bytes memory data = abi.encodeWithSignature(
      "updateAndSend(bytes32,uint256,uint256[] memory)",
      tree.root,
      getChainID(),
      toChainIDs
    );

    if (bridgeType == 0) {
      //Test
      l1Bridge.updateAndSend(tree.root, getChainID(), toChainIDs);
    } else if (bridgeType == 1) {
      //Optimism
      iOVMCrossDomainMessenger(OVML2CrossDomainMessenger).sendMessage(
        address(l1Bridge),
        data,
        1000000
      );
    } else if (bridgeType == 2) {
      //Arbitrum
      arbSys.sendTxToL1(address(l1Bridge), data);
    }
  }

  function updateL1Bridge() public {
    bytes memory data = abi.encodeWithSignature(
      "update(bytes32,uint256)",
      tree.root,
      getChainID()
    );

    if (bridgeType == 0) {
      //Test
      l1Bridge.update(tree.root, getChainID());
    } else if (bridgeType == 1) {
      //Optimism
      iOVMCrossDomainMessenger(OVML2CrossDomainMessenger).sendMessage(
        address(l1Bridge),
        data,
        1000000
      );
    } else if (bridgeType == 2) {
      //Arbitrum
      arbSys.sendTxToL1(address(l1Bridge), data);
    }
  }

  function regularTransfer(
    address tokenAddress,
    address l1TokenAddress,
    address remoteChainTokenAddress,
    uint256 amount,
    uint256 remoteChainID
  ) external payable permittedAddress(msg.sender) {
    uint256 chainID = getChainID();

    bytes memory data = abi.encodeWithSignature(
      "regularSendToL2(address,address,uint256,uint256,uint256)",
      l1TokenAddress,
      remoteChainTokenAddress,
      amount,
      chainID,
      remoteChainID
    );

    if (tokenAddress == address(0)) {
      //ETH
      require(msg.value >= amount);

      if (bridgeType == 0) {
        //Test

        l1Bridge.regularSendToL2{ value: amount }(
          l1TokenAddress,
          remoteChainTokenAddress,
          amount,
          chainID,
          remoteChainID
        );
      } else if (bridgeType == 1) {
        //Optimism

        OVML2StandardBridge.withdrawTo(
          OVML2ETHTokenAddress,
          address(l1Bridge),
          amount,
          2000000,
          "0x"
        );

        iOVMCrossDomainMessenger(OVML2CrossDomainMessenger).sendMessage(
          address(l1Bridge),
          data,
          1000000
        );
      } else if (bridgeType == 2) {
        //Arbitrum

        arbSys.withdrawEth{ value: amount }(address(l1Bridge));
        arbSys.sendTxToL1(address(l1Bridge), data);
      } else {
        assert(false);
      }
    } else {
      //Token
      require(IERC20(tokenAddress).balanceOf(address(this)) >= amount);

      if (bridgeType == 0) {
        //Test
        require(
          IERC20(tokenAddress).transfer(address(l1Bridge), amount),
          "Transaction failed"
        );
      } else if (bridgeType == 1) {
        //Optimism
        OVML2StandardBridge.withdrawTo(
          tokenAddress,
          address(l1Bridge),
          amount,
          2000000,
          "0x"
        );

        iOVMCrossDomainMessenger(OVML2CrossDomainMessenger).sendMessage(
          address(l1Bridge),
          data,
          1000000
        );
      } else if (bridgeType == 2) {
        //Arbitrum
        //TODO: add arbitrum support
      } else {
        assert(false);
      }
    }
  }

  function addRemoteRoot(bytes32 root, uint256 chainID) public {
    if (bridgeType == 1) {
      //Optimism
      require(
        msg.sender == OVML2CrossDomainMessenger &&
          iOVMCrossDomainMessenger(OVML2CrossDomainMessenger)
            .xDomainMessageSender() ==
          address(l1Bridge)
      );
    } else {
      //Test and Arbitrum
      require(msg.sender == address(l1Bridge));
    }

    remoteRoots[keccak256(abi.encode(root, chainID))] = true;
  }

  function verify(
    uint256 transferID,
    uint256 fromChainId,
    uint256 toChainId,
    bytes memory message,
    bytes32 rootHash,
    uint256 branchMask,
    bytes32[] memory siblings
  ) public pure returns (bytes32 key) {
    bytes32 _key = getHash(transferID, fromChainId, toChainId, message);
    verifyProof(rootHash, abi.encode(_key), message, branchMask, siblings);
    return _key;
  }

  function getMessageProof(
    uint256 transferID,
    uint256 toChainId,
    bytes memory message
  )
    public
    view
    returns (
      bytes32 rootHash,
      uint256 branchMask,
      bytes32[] memory siblings
    )
  {
    bytes32 key = getHash(transferID, getChainID(), toChainId, message);
    (uint256 _branchMask, bytes32[] memory _siblings) = getProof(
      abi.encode(key)
    );
    return (tree.root, _branchMask, _siblings);
  }

  function withdraw(
    uint256 transferID,
    uint256 fromChainId,
    bytes memory message,
    bytes32 rootHash,
    uint256 branchMask,
    bytes32[] memory siblings
  ) public permittedAddress(msg.sender) {
    require(remoteRoots[keccak256(abi.encode(rootHash, fromChainId))]);
    bytes32 key = verify(
      transferID,
      fromChainId,
      getChainID(),
      message,
      rootHash,
      branchMask,
      siblings
    );
    require(!withdrawn[key], "Withdrawn already");
    withdrawn[key] = true;
  }

  function getHash(
    uint256 transferID,
    uint256 fromChainId,
    uint256 toChainId,
    bytes memory message
  ) public pure returns (bytes32) {
    return keccak256(abi.encode(transferID, fromChainId, toChainId, message));
  }

  function getChainID() public view returns (uint256) {
    uint256 id = block.chainid;

    // 5001 -> Localhost network
    // 80001 -> Mumbai network
    if (id == 5001 || id == 80001) {
      //Test
      id = uint32(uint160(address(this)));
    }

    return id;
  }

  function addPermittedAddress(address _addr) external onlyOwner {
    isPermittedAddress[_addr] = true;
  }
}
