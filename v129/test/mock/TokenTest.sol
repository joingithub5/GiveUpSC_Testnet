// SPDX-License-Identifier: SEE LICENSE IN LICENSE
// source: https://github.com/aurelien-cuvelier/local-uniswapv2-foundry/blob/master/src/TokenTest.sol
pragma solidity >=0.8.5;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract Token is ERC20("TurboMooner", "TBM", 18) {
    constructor() {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}
