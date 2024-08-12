//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";

contract HelperConfig {
    uint256 public constant BLAST_TEST_CHAINID = 168587773;
    uint256 public constant ETH_CHAINID = 1;
    uint256 public constant OPTIMISM_CHAINID = 10;
    uint256 public constant BASE_CHAINID = 8453;
    uint256 public constant ANVIL_CHAINID = 31337;

    struct NetworkConfig {
        uint256 chainId;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == BLAST_TEST_CHAINID) {
            activeNetworkConfig = getBlastTestConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        } // add other chain later
    }

    function getBlastTestConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory blastConfig = NetworkConfig({chainId: BLAST_TEST_CHAINID});
        return blastConfig;
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        //         if(activeNetworkConfig.somethingSuchAsPriceFeedAddress != address(0)) {
        //     return activeNetworkConfig;
        // }  // reserve for later
        NetworkConfig memory config = NetworkConfig({chainId: ANVIL_CHAINID});
        return config;
    }
}
