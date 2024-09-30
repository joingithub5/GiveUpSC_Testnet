// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GiveUp_129.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GiveUpDeployer {
    function deployGiveUp129(
        bytes32 _salt,
        address _implementation,
        uint256 _platformFee,
        string memory _nativeTokenSymbol
    ) public returns (GiveUp129) {
        _salt = keccak256(abi.encodePacked(SALT_2_CREATE_TOKEN)); // hardcoded salt to test

        // // Triển khai implementation
        // GiveUp129 implementation = new GiveUp129();

        // Chuẩn bị dữ liệu khởi tạo
        bytes memory initData = abi.encodeWithSelector(GiveUp129.initialize.selector, _platformFee, _nativeTokenSymbol);

        // Triển khai proxy với salt
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(_implementation), initData));

        address proxyAddress;
        assembly {
            proxyAddress := create2(0, add(proxyBytecode, 0x20), mload(proxyBytecode), _salt)
        }

        // Chuyển quyền sở hữu cho người gọi gốc (OWNER)
        GiveUp129(proxyAddress).transferOwnership(tx.origin);

        return GiveUp129(proxyAddress);
        // return new GiveUp129{salt: _salt}(_platformFee, _nativeTokenSymbol);
    }

    // function getGiveUp129Address(bytes32 _salt, uint256 _platformFee, string memory _nativeTokenSymbol)
    function getGiveUp129Address(
        bytes32 _salt,
        address _implementation,
        uint256 _platformFee,
        string memory _nativeTokenSymbol
    ) public view returns (address) {
        _salt = keccak256(abi.encodePacked(SALT_2_CREATE_TOKEN)); // hardcoded salt to test
        bytes memory initData = abi.encodeWithSelector(GiveUp129.initialize.selector, _platformFee, _nativeTokenSymbol);
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_implementation, initData));
        // bytes memory bytecode =
        //     abi.encodePacked(type(GiveUp129).creationCode, abi.encode(_platformFee, _nativeTokenSymbol));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}
