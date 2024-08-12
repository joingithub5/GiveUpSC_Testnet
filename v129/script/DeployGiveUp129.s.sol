//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {GiveUp129} from "../src/GiveUp_129.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CommunityToken} from "../test/mock/CTK.sol";
import {RottenToken} from "../test/mock/ROTTEN.sol";
import {AnyToken} from "../test/mock/ANY.sol";

contract DeployGiveUp129 is Script {
    function run(uint256 platformFee, string memory nativeTokenSymbol)
        external
        returns (GiveUp129, CommunityToken, RottenToken, AnyToken)
    {
        // HelperConfig helperConfig = new HelperConfig(); // reserve

        vm.startBroadcast();
        GiveUp129 giveup129 = new GiveUp129(platformFee, nativeTokenSymbol);
        CommunityToken ctk = new CommunityToken(msg.sender);
        RottenToken rotten = new RottenToken(msg.sender);
        AnyToken any = new AnyToken(msg.sender);
        // console.log("address of giveUp at deployer: ", address(giveup129)); // troubleshooting
        vm.stopBroadcast();
        return (giveup129, ctk, rotten, any);
    }
}
