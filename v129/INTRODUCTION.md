# GiveUp129 Smart Contract Documentation

## Introduction

GiveUp129 is the main smart contract of the GiveUp Platform, designed to create and monetize three types of campaigns: donate/tip campaigns, collaboration campaigns, and non-profit campaigns. This documentation provides an overview of the contract's features and related contracts for further exploration.

## Table of Contents

- [GiveUp129 Smart Contract Documentation](#giveup129-smart-contract-documentation)
  - [Introduction](#introduction)
  - [Table of Contents](#table-of-contents)
  - [Contract Overview](#contract-overview)
  - [USESAGE:](#usesage)
  - [Technical Features](#technical-features)
  - [Campaign Types](#campaign-types)
  - [Related Contracts](#related-contracts)
  - [Important Functions](#important-functions)
    - [Campaign Management](#campaign-management)
    - [Funding and Withdrawal](#funding-and-withdrawal)
    - [Token Management](#token-management)
  - [Events](#events)
  - [Security Considerations](#security-considerations)
  - [Further Reading](#further-reading)

## Contract Overview

The GiveUp129 contract is an upgradeable smart contract that implements various interfaces and uses OpenZeppelin libraries for enhanced security and functionality. It manages campaign creation, funding, and payout processes.

**Contract Declaration:**
```solidity
contract GiveUp129 is BackerTokenInterface, ReentrancyGuard, Initializable, UUPSUpgradeable, OwnableUpgradeable {
// Contract body
}
```

## USESAGE: 
1. Use this contract to create a token in the form of a tokenized campaign. Campaign can be anything you can imagine.
2. Advantages:
   1. Raiser can tokenize anything and sell shares of it. 
   2. Backer (or buyer) can buy shares of your campaign and then get the LP when campaign succeeds with confidence of:
      1. Knowning fee to be paid in advance when withdraw fund via LP.
      2. Knowing that in the worst case, they can always get back their fund (minus platform fee, raiser's setting fee) by redeeming LP.
      3. Knowing that in normal cases, price safety mechanism will make their LP price only go up together with the campaign result token price.
   3. Backer (or buyer) can withdraw fund with no loss, no lock when campaign fails or in progress.

## Technical Features
    Already implemented:
1. **Upgradeable**: Uses OpenZeppelin's upgradeable contracts pattern.
2. **Multi-token Support**: Handles native tokens (e.g., ETH) and whitelisted ERC20 tokens.
3. **Campaign Management**: Creates, updates, and manages various types of campaigns.
4. **Voting System**: Allows backers to vote on campaign options.
5. **Fraud Reporting**: Implements a system for backers to report fraudulent campaigns.
   Not yet implemented:
6. **Timelock Mechanism**: Prevents front-running attacks during withdrawals.
7. **NFT Integration**: Works with ContributionNFT for rewarding backers.
   Testnet UI: https://giveup.vercel.app/

## Campaign Types

1. **Donate or Tip Campaign**: 
   - Raiser receives all funds
   - Backers/Alchemist receive campaign result tokens as rememberance. 
   - IMPORTANT NOTE: donation fund is lost because it is donation/ tip in nature.

2. **Collaboration Campaign**: 
   - Raised funds (minus platform fee) are pooled with campaign tokens
   - Participants (raiser, alchemist, backers) receive shares based on predefined rules

3. **Non-profit Campaign**:
   - Similar to collaboration campaign, but raiser gets 0% of raised funds.
   - No time or fund target limits
   - Alchemist controls payout

## Related Contracts

1. **TokenTemplate1**: Manages campaign-specific tokens
2. **ContributionNFT**: Handles NFT rewards for backers (not yet implemented)
3. **GiveUpLib1**: Library containing helper functions
4. **GiveUpLib2**: Additional library with helper functions
5. **GlobalVariables_12x**: Defines global variables and structs
6. **BackerTokenInterface**: Interface for backer token functionality

## Important Functions

### Campaign Management

1. `initialize(uint256 _campaignTax, string memory _nativeTokenSymbol)`: Initializes the contract
2. `setCampaignFinalTokenNameAndSymbol(string memory _name, string memory _symbol, uint256 _forCampaignId)`: Sets the campaign's final token name and symbol
3. `raiserChangeAlchemist(uint256 _id, address payable _alchemistAddr)`: Allows raiser to propose a new alchemist
4. `communityProposeAlchemist(uint256 _id, address payable _alchemistAddr)`: Allows community to propose an alchemist
5. `approveAlchemist(uint256 _id, bool _vetoFraudCampaign, string memory _proof)`: Approves or vetos an alchemist

### Funding and Withdrawal

1. `backerAddFraudReport(uint256 _id, string memory _fraudProof)`: Allows backers to report fraud
2. `backerRemoveFraudReport(uint256 _id, string memory _reason)`: Allows backers to remove their fraud report
3. `requestRefund(uint256 _campaignId, uint256 _voteOption)`: Initiates a refund request for backers

### Token Management

1. `addWhiteListToken(address _tokenAddress, string memory _tokenPriority)`: Adds a new token to the whitelist

## Events

1. `Action(uint256 id, string actionType, address indexed executor, uint256 timestamp)`: Logs various actions in the contract
2. `GeneralLog(string message)`: Logs general messages

## Security Considerations

1. Uses OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks
2. Implements a timelock mechanism to prevent front-running (not yet implemented)
3. Utilizes `SafeERC20` for safe token transfers (not yet audited)
4. Employs access control modifiers like `ownerOnly()` (not yet audited)

## Further Reading

For more detailed information on specific functions and their implementations, please refer to the following files:

- `GiveUp129.sol`: Main contract file
- `TokenTemplate1.sol`: Campaign token management
- `ContributionNFT.sol`: NFT reward system (not yet implemented)
- `GLib_Base1.sol` and `GLib_Base2.sol`: Helper libraries
- `GlobalVariables_12x.sol`: Global variables and structs
- `BackerTokenInterface.sol`: Interface for backer token functionality

Please note that this contract is still in development and has not been fully tested or audited. Use caution when interacting with unaudited smart contracts.

