//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {GiveUp129} from "../src/GiveUp_129.sol";
import "../src/GlobalVariables_12x.sol";
// import {DeployGiveUp129} from "../script/DeployGiveUp129.s.sol";
// import "../test/unit/Input_Params.sol";
// import "../../src/GlobalVariables_12x.sol";
import {CommunityToken} from "../test/mock/CTK.sol";
// import {RottenToken} from "../test/mock/ROTTEN.sol";
// import {AnyToken} from "../test/mock/ANY.sol";
import "../test/unit/Input_Params.sol";
import {TokenTemplate1} from "../src/TokenTemplate1.sol";
/**
 * Notes in this test:
 * MAX_RULES is the campaign Id of the latest campaign
 * SEND_VALUE is the target amount of native token (e.g. ETH) of test campaign
 * SEND_TOKEN_AMT is the target amount of white list token (e.g. CTK) of test campaign
 */

contract CreateOrUpdate is Script {
    /**
     * just create simple campaign atm
     */
    function createCampaign(GiveUp129 _giveUp, uint256 _haveFundTarget, uint256 _pctForBackers)
        public
        returns (uint256)
    {
        vm.startPrank(msg.sender);
        CreateCampaignInput memory c_input = initializeCreateCampaignData(_haveFundTarget, _pctForBackers); // set target fund is 0.1 ether (SEND_VALUE)
        uint256 returnCId = _giveUp.createCampaign(
            c_input.haveFundTarget,
            c_input.content,
            c_input.options,
            c_input.timeline,
            c_input.group,
            c_input.deList,
            c_input.fund,
            c_input.pctForBackers,
            ALCHEMIST1
        );
        assert(returnCId == _giveUp.nextCId() - 1);
        // vm.stopPrank();
        return returnCId;
    }

    function updateCampaign(
        GiveUp129 _giveUp,
        uint256 _cId,
        uint256 _newHaveFundTarget,
        uint256 _newPctForBackers,
        string[] memory _uintFieldToChange,
        uint256[] memory _uintValueToChange
    ) public returns (bool) {
        vm.startPrank(msg.sender);
        // vm.startBroadcast(); // >> if caller have vm.startPrank(raiser) then ...
        UpdateCampaignInput memory _data = initializeUpdateCampaignData(
            _cId, _newHaveFundTarget, _newPctForBackers, _uintFieldToChange, _uintValueToChange
        );
        bool result = _giveUp.updateCampaign(
            _data.campaignId,
            _data.haveFundTarget,
            _data.pctForBackers,
            _data.stringFields,
            _data.intFields,
            _data.arrayFields,
            _data.stringValues,
            _data.uintValues,
            _data.group,
            _data.deList
        );
        // vm.stopPrank();
        // vm.stopBroadcast(); // >> ... you have an active prank; broadcasting and pranks are not compatible
        return result;
    }

    function run(
        GiveUp129 _giveUp,
        uint256 _cId,
        uint256 _haveFundTarget,
        uint256 _pctForBackers,
        string[] memory _uintFieldToChange,
        uint256[] memory _uintValueToChange
    ) external {
        createCampaign(_giveUp, _haveFundTarget, _pctForBackers);
        updateCampaign(_giveUp, _cId, _haveFundTarget, _pctForBackers, _uintFieldToChange, _uintValueToChange);
    }
}

contract DonateOrVote is Script {
    /**
     * caller must provider proper timeframe before calling donateWLToken(), voteWLToken()
     */
    function donateWLToken(
        GiveUp129 _giveUp,
        uint256 _campaignId,
        uint256 _option,
        uint256 _feedback,
        CommunityToken _tokenAddr,
        uint256 _amount
    ) public returns (bool) {
        vm.startPrank(msg.sender);
        _tokenAddr.mint(msg.sender, _amount * 100); // target fund usually 10 * SEND_TOKEN_AMT => mint redundantly
        _tokenAddr.approve(address(_giveUp), _amount * 100); // approve redundantly
        bool success =
            _giveUp.donateWhiteListTokenToCampaign(_campaignId, _option, _amount, address(_tokenAddr), _feedback);
        // vm.stopPrank();
        return success;
    }

    function voteWLToken(
        GiveUp129 _giveUp,
        uint256 _campaignId,
        uint256 _option,
        uint256 _feedback,
        CommunityToken _tokenAddr
    ) public returns (bool) {
        vm.startPrank(msg.sender);
        bool success = _giveUp.donateWhiteListTokenToCampaign(_campaignId, _option, 0, address(_tokenAddr), _feedback);
        // vm.stopPrank();
        return success;
    }

    function donate(GiveUp129 _giveUp, uint256 _campaignId, uint256 _option, uint256 _feedback, uint256 _amount)
        public
        returns (bool)
    {
        vm.startPrank(msg.sender);
        bool success = _giveUp.donateToCampaign{value: _amount}(_campaignId, _option, _feedback);
        // vm.stopPrank();
        return success;
    }

    function vote(GiveUp129 _giveUp, uint256 _campaignId, uint256 _option, uint256 _feedback) public returns (bool) {
        vm.startPrank(msg.sender);
        bool success = _giveUp.donateToCampaign{value: 0}(_campaignId, _option, _feedback);
        // vm.stopPrank();
        return success;
    }

    function run(
        GiveUp129 _giveUp,
        uint256 _campaignId,
        uint256 _option,
        uint256 _feedback,
        CommunityToken _tokenAddr,
        uint256 _amount
    ) external {
        donateWLToken(_giveUp, _campaignId, _option, _feedback, _tokenAddr, _amount);
        voteWLToken(_giveUp, _campaignId, _option, _feedback, _tokenAddr);
        donate(_giveUp, _campaignId, _option, _feedback, _amount);
        vote(_giveUp, _campaignId, _option, _feedback);
    }
}

contract WithdrawOrRefund is Script {}

contract PaidoutOrDelete is Script {
    // function payOutCampaign(GiveUp129 _giveUp, uint256 _campaignId) public returns (bool) {
    function payOutCampaign(GiveUp129 _giveUp, uint256 _campaignId)
        public
        returns (TokenTemplate1 resultToken, uint256 liquidity)
    {
        vm.startPrank(msg.sender);
        // bool raiserPaidOut = _giveUp.payOutCampaign(_campaignId);
        (resultToken, liquidity) = _giveUp.payOutCampaign(_campaignId);
        // vm.stopPrank();
        // return raiserPaidOut;
    }

    function deleteCampaign(GiveUp129 _giveUp, uint256 _campaignId) public returns (bool) {
        vm.startPrank(msg.sender);
        bool raiserPaidOut = _giveUp.deleteCampaign(_campaignId);
        // vm.stopPrank();
        return raiserPaidOut;
    }

    function run(GiveUp129 _giveUp, uint256 _campaignId) external {
        payOutCampaign(_giveUp, _campaignId);
        deleteCampaign(_giveUp, _campaignId);
    }
}

contract Util is Script {
    event LogCampaignOptionsVotedResult(bool success, bytes result);

    function getVoterOptions(GiveUp129 _giveUp, uint256 _campaignId) public view returns (VoteData[] memory) {
        address caller = msg.sender;
        uint256 optionCount = 0;
        VoteData[] memory voteDatas = new VoteData[](5);
        for (uint256 i = 0; i < 5; i++) {
            VoteData memory voteData = _giveUp.getCampaignOptionsVoted(_campaignId, caller, i);
            if (bytes(voteData.tokenSymbol).length != 0) {
                // if (keccak256(abi.encodePacked(voteData.tokenSymbol)) != keccak256(abi.encodePacked(""))) {
                voteDatas[optionCount] = voteData;
                optionCount = optionCount + 1;
            }
        }
        if (optionCount < 5) {
            VoteData[] memory finalVoteDatas = new VoteData[](optionCount);
            for (uint256 i = 0; i < optionCount; i++) {
                finalVoteDatas[i] = voteDatas[i];
            }
            console.log("optionCount: ", optionCount);
            return finalVoteDatas;
        }

        console.log("optionCount: ", optionCount);
        return voteDatas;
    }

    function run(GiveUp129 _giveUp, uint256 _campaignId) external view {
        getVoterOptions(_giveUp, _campaignId);
    }
}
