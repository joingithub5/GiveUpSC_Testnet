// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

uint256 constant SEND_VALUE = 1 ether; // used when send native token
uint256 constant SEND_TOKEN_AMT = 100; // used when send ERC20 white listed token
address payable constant OWNER = payable(address(999)); // 0x00000000000000000000000000000000000003E7
address payable constant RULER = payable(address(1000));
address payable constant VOTER1 = payable(address(1001));
address payable constant VOTER2 = payable(address(1002));
address payable constant TRADER1 = payable(address(1011)); // 0x00000000000000000000000000000000000003F3
address payable constant TRADER2 = payable(address(1012));
address payable constant BACKER1 = payable(address(101)); // 0x0000000000000000000000000000000000000065
address payable constant BACKER2 = payable(address(102)); // 0x0000000000000000000000000000000000000066
address payable constant RAISER1 = payable(address(1)); // 0x0000000000000000000000000000000000000001
address payable constant RAISER2 = payable(address(2)); // 0x0000000000000000000000000000000000000002
address payable constant ALCHEMIST1 = payable(address(11)); // 0x000000000000000000000000000000000000000b
address payable constant ALCHEMIST2 = payable(address(12));
address constant COMMUNITY1 = address(21);
address constant COMMUNITY2 = address(22);

uint256 constant STARTING_USER_BALANCE = 100 ether;
uint256 constant MAX_SWAP_PERCENT = 1; // e.g. 1% of liquidity, change it to control slippage and test swap fee variation. the lower the smaller slippage. E.G. 1% let OWNER get 0.167 ETH from swap fee while 15% let OWNER get 1.448 ETH from swap fee
// note: with MAX_SWAP_PERCENT = 1:
// liquidity max rule: amountToken: amountETH = < 10*4  (10000:1)
// WE SHOULD USE RATIO 1000:1 in TokenTemplate1 contract, sample liquidity is 1ETH + max 10000 token
// with MAX_SWAP_PERCENT = 1... ETH: 2.125 (max 10000:1), 0.6785 (1000:1), 0.2145 (100:1), 0.0678 (10:1), 0.02145 (1:1)
// with MAX_SWAP_PERCENT = 15... ETH: 3.934 (max 10000:1), 3.337 (1000:1),  (100:1), 0.471 (10:1),  (1:1)

uint256 constant GAS_PRICE = 1;
uint256 constant FEE_PCT_10 = 10; // platform fee percentage

struct TestParams {
    uint256[] haveFundTargets;
    uint256[] pctForBackers;
    bool[] changeAlchemists;
}

struct DonationInfo {
    uint256 nativeTokenDonation;
    uint256 ctkTokenDonation;
    uint256 balanceBefore;
    uint256 ctkBalanceBefore;
}

struct CreateCampaignInput {
    uint256 haveFundTarget;
    string[] content;
    string[] options;
    uint256[] timeline;
    uint256[] group;
    uint256[] deList;
    uint256[] fund;
    uint256 pctForBackers;
}

struct UpdateCampaignInput {
    uint256 campaignId;
    uint256 haveFundTarget;
    uint256 pctForBackers;
    string[] stringFields;
    string[] intFields;
    string[] arrayFields;
    string[] stringValues;
    uint256[] uintValues;
    uint256[] group;
    uint256[] deList;
}

/* a sample campaign when raiser want to get 100% donation, no sharing
_xxx: (1st suffix) percentage of haveFundTarget, 100 = 100% in this case
_xxx: (2nd suffix) percentage of pctForBackers, 0 = 0% in this case
*/
function initializeCampaignData_100_0() view returns (CreateCampaignInput memory) {
    CreateCampaignInput memory c = CreateCampaignInput({
        haveFundTarget: 100,
        content: new string[](4),
        options: new string[](4),
        timeline: new uint256[](2),
        group: new uint256[](1),
        deList: new uint256[](1),
        fund: new uint256[](5),
        pctForBackers: 0
    });
    c.content[0] = "campaignType";
    c.content[1] = "title";
    c.content[2] = "description";
    c.content[3] = "image";
    c.timeline[0] = block.timestamp + 86400 * 3;
    c.timeline[1] = block.timestamp + 86400 * 5;
    c.fund[0] = SEND_VALUE;

    return c;
}

/* receive 2 simple input then make up remaining inputs to create campaign */
function initializeCreateCampaignData(uint256 _haveFundTarget, uint256 _pctForBackers)
    view
    returns (CreateCampaignInput memory)
{
    CreateCampaignInput memory c = CreateCampaignInput({
        haveFundTarget: _haveFundTarget,
        content: new string[](4),
        options: new string[](4),
        timeline: new uint256[](2),
        group: new uint256[](1),
        deList: new uint256[](1),
        fund: new uint256[](5),
        pctForBackers: _pctForBackers
    });
    c.content[0] = string(abi.encodePacked("campaignType_", _haveFundTarget, "_", _pctForBackers));
    c.content[1] = "title";
    c.content[2] = "description";
    c.content[3] = "image";
    c.timeline[0] = block.timestamp + 86400 * 3;
    c.timeline[1] = block.timestamp + 86400 * 5;
    c.fund[0] = SEND_VALUE; // default 1 ETH

    return c;
}

/* receive some simple input then make up remaining inputs to update campaign */
function initializeUpdateCampaignData(
    uint256 _campaignId,
    uint256 _haveFundTarget,
    uint256 _pctForBackers,
    string[] memory _uintFieldToChange, // must match keyword exactly
    uint256[] memory _uintValueToChange // must match order with _uintFieldToChange
) pure returns (UpdateCampaignInput memory) {
    UpdateCampaignInput memory updateCampaignData = UpdateCampaignInput({
        campaignId: _campaignId,
        haveFundTarget: _haveFundTarget,
        pctForBackers: _pctForBackers,
        stringFields: new string[](0),
        intFields: new string[](_uintFieldToChange.length),
        arrayFields: new string[](0),
        stringValues: new string[](0),
        uintValues: new uint256[](_uintValueToChange.length),
        group: new uint256[](0),
        deList: new uint256[](0)
    });

    for (uint256 i = 0; i < _uintFieldToChange.length; i++) {
        updateCampaignData.intFields[i] = _uintFieldToChange[i];
        updateCampaignData.uintValues[i] = _uintValueToChange[i];
    }
    return updateCampaignData;
}
