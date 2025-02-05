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
  - [Smart Contract Testing:](#smart-contract-testing)
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

**Already implemented:**
1. **Upgradeable**: Uses OpenZeppelin's upgradeable contracts pattern.
2. **Multi-token Support**: Handles native tokens (e.g., ETH) and whitelisted ERC20 tokens.
3. **Campaign Management**: Creates, updates, and manages various types of campaigns.
4. **Voting System**: Allows backers to vote on campaign options.
5. **Fraud Reporting**: Implements a system for backers to report fraudulent campaigns.
   
**Not yet implemented:**
6. **Timelock Mechanism**: Prevents front-running attacks during withdrawals.
7. **NFT Integration**: Works with ContributionNFT for rewarding backers.
   
**Testnet UI:** https://giveup.vercel.app/

**Public repo:** https://github.com/joingithub5/GiveUpSC_Testnet/blob/main/v129/INTRODUCTION.md

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

## Smart Contract Testing:
- after installing foundry, run `forge coverage` at sc/v129 to test all contracts. Here is the result up to 2024 Sept 30:

```
  Ran 1 test for test/integration/ExploitTest.t.sol:GiveUp129ExploitTest
[PASS] testExploit_1() (gas: 908910)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 21.15ms (6.27ms CPU time)

Ran 13 tests for test/unit/GiveUp_129Test.t.sol:GiveUp129UnitTest
[PASS] testChangeTax() (gas: 47454)
[PASS] testCreateCampaign() (gas: 651448)
[PASS] testDelayBlockNumberToPreventFrontRun() (gas: 47050)
[PASS] testDonateToCampaign_0_90() (gas: 1221136)
[PASS] testGetBackerFraudReport() (gas: 526716)
[PASS] testGetCIdFromAddressAndIndex() (gas: 521301)
[PASS] testGetRateDetail() (gas: 563839)
[PASS] testGetRateDetailOfFraudReport() (gas: 563790)
[PASS] testOutsideCantSendNativeTokenDirectlyToContract() (gas: 899296)
[PASS] testOwnerIsMessageSender() (gas: 28418)
[PASS] testPenaltyContract() (gas: 55711)
[PASS] testPresentCIdAndRuleId() (gas: 26161)
[PASS] testRulerAddr() (gas: 60019)
Suite result: ok. 13 passed; 0 failed; 0 skipped; finished in 27.81ms (47.85ms CPU time)

Ran 2 tests for test/integration/InteractionsTest_2.t.sol:InteractionsTest_2
[PASS] testContributionNFT() (gas: 17007910)
[PASS] testNormalAndNonprofitCampaigns() (gas: 86563082)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 212.39ms (205.63ms CPU time)

Ran 12 tests for test/integration/InteractionsTest.t.sol:GiveUp129InteractionsTest
[PASS] testAllPaidOutDeleteCombinations() (gas: 95568360)
[PASS] testDeleteCampaign() (gas: 2384335)
[PASS] testDeleteCampaign_0_xxx() (gas: 2409339)
[PASS] testDonateVoteWithdraw_0_90_p1() (gas: 3810411)
[PASS] testDonateVoteWithdraw_0_90_p2() (gas: 4995630)
[PASS] testDonateVoteWithdraw_100_0() (gas: 2905037)
[PASS] testNonProfitCampaignPayoutRight_P1() (gas: 2973498)
[PASS] testNonProfitCampaignPayoutRight_P2() (gas: 14823965)
[PASS] testPaidOutDelete_90_10() (gas: 16446028)
[PASS] testUpdateCampaign() (gas: 3108898)
[PASS] testVoteDonateInteraction() (gas: 3666756)
[PASS] testWhiteListTokenInteractions() (gas: 252091)
Suite result: ok. 12 passed; 0 failed; 0 skipped; finished in 339.91ms (562.90ms CPU time)

Ran 4 tests for test/unit/UniswapDeployerTest.t.sol:UniswapTests
[PASS] test_deployedRouter() (gas: 5691)
[PASS] test_swapAndCheckFee() (gas: 46561579)
[PASS] test_uniswapFactory() (gas: 12188)
[PASS] test_wrappedEther() (gas: 9974)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 636.22ms (611.34ms CPU time)

Ran 5 test suites in 643.70ms (1.24s CPU time): 32 tests passed, 0 failed, 0 skipped (32 total tests)
| File                         | % Lines           | % Statements      | % Branches       | % Funcs          |
|------------------------------|-------------------|-------------------|------------------|------------------|
| script/DeployGiveUp129.s.sol | 100.00% (21/21)   | 100.00% (24/24)   | 50.00% (1/2)     | 100.00% (3/3)    |
| script/HelperConfig.s.sol    | 0.00% (0/7)       | 0.00% (0/9)       | 0.00% (0/2)      | 0.00% (0/3)      |
| script/Interactions.s.sol    | 74.07% (40/54)    | 78.26% (54/69)    | 50.00% (3/6)     | 61.54% (8/13)    |
| script/UniswapDeployer.s.sol | 100.00% (3/3)     | 100.00% (3/3)     | 100.00% (0/0)    | 100.00% (1/1)    |
| src/ContributionNFT.sol      | 78.95% (15/19)    | 77.27% (17/22)    | 50.00% (3/6)     | 83.33% (5/6)     |
| src/GiveUpDeployer.sol       | 100.00% (13/13)   | 100.00% (19/19)   | 100.00% (0/0)    | 100.00% (2/2)    |
| src/GiveUp_129.sol           | 85.43% (211/247)  | 84.81% (229/270)  | 52.24% (70/134)  | 87.04% (47/54)   |
| src/TokenTemplate1.sol       | 63.35% (121/191)  | 61.40% (132/215)  | 40.58% (56/138)  | 65.00% (13/20)   |
| src/lib/GLib_Base1.sol       | 59.17% (100/169)  | 58.58% (140/239)  | 45.74% (43/94)   | 85.71% (12/14)   |
| src/lib/GLib_Base2.sol       | 68.35% (216/316)  | 64.26% (302/470)  | 51.00% (102/200) | 93.33% (14/15)   |
| test/lib/TestLib.sol         | 81.25% (13/16)    | 78.95% (15/19)    | 100.00% (2/2)    | 50.00% (1/2)     |
| test/mock/ANY.sol            | 100.00% (1/1)     | 100.00% (1/1)     | 100.00% (0/0)    | 100.00% (2/2)    |
| test/mock/CTK.sol            | 0.00% (0/1)       | 0.00% (0/1)       | 100.00% (0/0)    | 0.00% (0/2)      |
| test/mock/ROTTEN.sol         | 0.00% (0/1)       | 0.00% (0/1)       | 100.00% (0/0)    | 0.00% (0/2)      |
| test/mock/TokenTest.sol      | 0.00% (0/1)       | 0.00% (0/1)       | 100.00% (0/0)    | 0.00% (0/1)      |
| Total                        | 71.13% (754/1060) | 68.67% (936/1363) | 47.95% (280/584) | 77.14% (108/140) |
```

## Further Reading

For more detailed information on specific functions and their implementations, please refer to the following files:

- `GiveUp129.sol`: Main contract file
- `TokenTemplate1.sol`: Campaign token management
- `ContributionNFT.sol`: NFT reward system (not yet implemented)
- `GLib_Base1.sol` and `GLib_Base2.sol`: Helper libraries
- `GlobalVariables_12x.sol`: Global variables and structs
- `BackerTokenInterface.sol`: Interface for backer token functionality

Please note that this contract is still in development and has not been fully tested or audited. Use caution when interacting with unaudited smart contracts.

