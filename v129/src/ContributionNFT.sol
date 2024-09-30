// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./TokenTemplate1.sol";

/**
 * NOTE DRAFT ONLY
 */
contract ContributionNFT is ERC721Enumerable, Ownable {
    TokenTemplate1 public tokenTemplate1;
    uint256 private _nextTokenId = 1;
    string private _name;
    string private _symbol;

    struct Contribution {
        address participant;
        uint256 amount;
        uint256 timestamp;
        string participantType;
    }

    mapping(uint256 => Contribution) private _contributions;

    constructor(address _tokenTemplate1Address) ERC721("", "") Ownable(msg.sender) {
        TokenTemplate1 tokenTemplate1Instance = TokenTemplate1(payable(_tokenTemplate1Address));
        tokenTemplate1 = tokenTemplate1Instance;

        _name = string(abi.encodePacked(tokenTemplate1Instance.name(), "_NFT"));
        _symbol = string(abi.encodePacked(tokenTemplate1Instance.symbol(), "_NFT"));
    }

    function mintNFT(address to, uint256 amount, string memory participantType) external returns (uint256) {
        require(msg.sender == address(tokenTemplate1), "Only TokenTemplate1 can mint");
        uint256 tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        _contributions[tokenId] = Contribution(to, amount, block.timestamp, participantType);
        _nextTokenId++;
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(tokenId > 0 && tokenId < _nextTokenId, "Token does not exist");
        Contribution memory contribution = _contributions[tokenId];

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Contribution NFT #',
                        Strings.toString(tokenId),
                        '",',
                        '"description": "This NFT represents a contribution to the campaign",',
                        '"attributes": [',
                        '{"trait_type": "Participant Type", "value": "',
                        contribution.participantType,
                        '"},',
                        '{"trait_type": "Contribution Amount", "value": ',
                        Strings.toString(contribution.amount),
                        "},",
                        '{"trait_type": "Contribution Time", "value": ',
                        Strings.toString(contribution.timestamp),
                        "}",
                        "]}"
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function getContributionInfo(uint256 tokenId)
        external
        view
        returns (address participant, uint256 amount, uint256 timestamp, string memory participantType)
    {
        require(tokenId > 0 && tokenId < _nextTokenId, "Token does not exist");
        Contribution memory contribution = _contributions[tokenId];
        return (contribution.participant, contribution.amount, contribution.timestamp, contribution.participantType);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
}
