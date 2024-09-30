//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {GiveUp129} from "../src/GiveUp_129.sol";
import {GiveUpDeployer} from "../src/GiveUpDeployer.sol";
// import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CommunityToken} from "../test/mock/CTK.sol";
import {RottenToken} from "../test/mock/ROTTEN.sol";
import {AnyToken} from "../test/mock/ANY.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";
import "../test/unit/Input_Params.sol";

// contract DeployGiveUp129 is Script, StdCheats {
contract DeployGiveUp129 is Script {
    struct DeploymentResult {
        GiveUp129 giveUp; // 0x4a51FB1f34a977c568be9E0505496a9B2921A79c
        CommunityToken ctk; //0xDB8cFf278adCCF9E9b5da745B44E754fC4EE3C76
        RottenToken rotten; // 0x50EEf481cae4250d252Ae577A09bF514f224C6C4
        AnyToken any; // 0x62c20Aa1e0272312BC100b4e23B4DC1Ed96dD7D1
        GiveUpDeployer deployer; // 0x90193C961A926261B756D1E5bb255e67ff9498A1
        address proxyAddress; // 0x4a51FB1f34a977c568be9E0505496a9B2921A79c
    }

    function run(uint256 platformFee, string memory nativeTokenSymbol)
        external
        returns (GiveUp129, CommunityToken, RottenToken, AnyToken, GiveUpDeployer, address)
    {
        // vm.startBroadcast();
        // vm.broadcast(OWNER);
        vm.startBroadcast(OWNER);

        DeploymentResult memory result = deployContracts(platformFee, nativeTokenSymbol);

        vm.stopBroadcast();

        return (result.giveUp, result.ctk, result.rotten, result.any, result.deployer, result.proxyAddress);
    }

    function deployContracts(uint256 platformFee, string memory nativeTokenSymbol)
        internal
        returns (DeploymentResult memory)
    {
        DeploymentResult memory result;

        result.deployer = new GiveUpDeployer();
        bytes32 salt = keccak256("production_salt");

        (result.giveUp, result.proxyAddress) = deployGiveUp(result.deployer, salt, platformFee, nativeTokenSymbol);

        result.ctk = new CommunityToken(msg.sender);
        result.rotten = new RottenToken(msg.sender);
        result.any = new AnyToken(msg.sender);

        return result;
    }

    function deployGiveUp(GiveUpDeployer deployer, bytes32 salt, uint256 platformFee, string memory nativeTokenSymbol)
        internal
        returns (GiveUp129, address)
    {
        GiveUp129 implementation = new GiveUp129();

        address proxyAddress =
            deployer.getGiveUp129Address(salt, address(implementation), platformFee, nativeTokenSymbol);
        GiveUp129 giveUp =
            GiveUp129(deployer.deployGiveUp129(salt, address(implementation), platformFee, nativeTokenSymbol));

        require(address(giveUp) == proxyAddress, "Proxy address mismatch");
        console.log("Proxy address:", proxyAddress);
        console.log("GiveUp address:", address(giveUp));

        return (giveUp, proxyAddress);
    }
}
