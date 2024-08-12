// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

uint256 constant SEND_VALUE = 0.1 ether; // used when send native token
uint256 constant SEND_TOKEN_AMT = 100; // used when send ERC20 white listed token
address payable constant RULER = payable(address(1000));
address payable constant VOTER1 = payable(address(1001));
address payable constant VOTER2 = payable(address(1002));
address payable constant BACKER1 = payable(address(101));
address payable constant BACKER2 = payable(address(102));
address payable constant RAISER1 = payable(address(1));
address payable constant RAISER2 = payable(address(2));
address payable constant ALCHEMIST1 = payable(address(11));
address payable constant ALCHEMIST2 = payable(address(12));
address constant COMMUNITY1 = address(21);
address constant COMMUNITY2 = address(22);

uint256 constant STARTING_USER_BALANCE = 100 ether;

uint256 constant GAS_PRICE = 1;

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
    c.fund[0] = SEND_VALUE;

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
