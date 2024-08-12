// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BackerTokenInterface.sol";
// import {SALT_2_CREATE_TOKEN} from "./GlobalVariables_12x.sol";

contract TokenTemplate1 is ERC20 {
    // uint256 public constant MAX_SUPPLY = 1000000000 * 10 ** 18;
    uint256 public constant MAX_SUPPLY = 1e9 * 1 ether; // 1 billion
    BackerTokenInterface public giveUpMainContract;
    uint256 public immutable i_campaignId;

    constructor(string memory _name, string memory _symbol, address _giveUpMainContract, uint256 _campaignId)
        ERC20(_name, _symbol)
    {
        giveUpMainContract = BackerTokenInterface(_giveUpMainContract);
        i_campaignId = _campaignId;
    }

    function getMaxMintPctBaseOnNativeToken(address _backerAddr, uint256 _campaignId) public view returns (uint256) {
        return giveUpMainContract.getMaxMintPctBaseOnNativeToken(_backerAddr, _campaignId);
    }

    function mint(address to, uint256 amount) external {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply reached");
        require(amount <= getMaxMintPctBaseOnNativeToken(to, i_campaignId), "Exceeds max mint amount");
        _mint(to, amount);
    }
    // see note about upgrade to create2
    //     function create2(bytes32 salt, string memory name, string memory symbol, address _giveUpMainContract, uint256 _campaignId) external {
    //         bytes memory bytecode = type(TokenTemplate1).creationCode;
    //         bytes32 codeHash = keccak256(bytecode);

    //         address deployedContract = address(uint160(uint256(keccak256(abi.encodePacked(
    //             bytes1(0xff),
    //             address(this),
    //             SALT_2_CREATE_TOKEN,
    //             codeHash
    //         )))));

    //         require(deployedContract != address(0), "Create2: Failed to deploy contract");
    // }
    function getMaxSupplyOfTokenTemplate1() public pure returns (uint256) {
        return MAX_SUPPLY;
    }
}
