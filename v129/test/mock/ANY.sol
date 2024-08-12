// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* a simple token to test (e.g as an unwhitelisted token), anyone can mint. */

contract AnyToken is ERC20, ERC20Burnable, Ownable {
    constructor(address initialOwner) ERC20("Any Token", "ANT") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
