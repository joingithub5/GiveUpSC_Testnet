// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

/* 
GIVEUP CRYPTO
bezu0012@gmail.com
https://twitter.com/bezu0012
*/

// Note DOWN VOTE will use rotten token

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../GlobalVariables_12x.sol";
import {TokenTemplate1} from "../TokenTemplate1.sol";

library GiveUpLib1 {
    event GeneralMsg(string message);

    /**
     * return the amount that platform take as tax for each successful campaign
     */
    function calculateTax(uint256 _amount, uint256 _campaignTax) public pure returns (uint256) {
        return (_amount * _campaignTax) / 100;
    }

    /* Todo: NEED TO TEST DoS when using findAddressIndex function because it use for loop to find index
                */
    /**
     * How to use: if address array which want to be checked is:
     * payable: pass address[](0) to variable addresses (it'll turn off non-payable case and focus on payable case)
     * not payable: pass address payable[](0) to variable payables (it'll turn off payable case and focus on non-payable case)
     */
    function findAddressIndex(address anyAddress, address[] memory addresses, address payable[] memory payables)
        public
        pure
        returns (bool found, uint256 index)
    {
        require(anyAddress != address(0), "Invalid address");
        if (addresses.length == 0) {
            uint256 length = payables.length;
            for (uint256 i = 0; i < length; i++) {
                if (payables[i] == anyAddress) {
                    return (true, i);
                }
            }
            return (false, 0);
        } else if (payables.length == 0) {
            uint256 length = addresses.length;
            for (uint256 i = 0; i < length; i++) {
                if (addresses[i] == anyAddress) {
                    return (true, i);
                }
            }
            return (false, 0);
        } else {
            return (false, 0); // invalid input that violate guidance
        }
    }

    /** get easy reading string from enum variable campaignStatusEnum */
    function campaignStatusToString(campaignStatusEnum status) public pure returns (string memory) {
        if (status == campaignStatusEnum.OPEN) return "OPEN";
        if (status == campaignStatusEnum.APPROVED) return "APPROVED";
        if (status == campaignStatusEnum.REVERTED) return "REVERTED";
        if (status == campaignStatusEnum.DELETED) return "DELETED";
        if (status == campaignStatusEnum.PAIDOUT) return "PAIDOUT";
        if (status == campaignStatusEnum.DRAFT) return "DRAFT";
        if (status == campaignStatusEnum.APPROVED_UNLIMITED) {
            return "APPROVED_UNLIMITED";
        }
        if (status == campaignStatusEnum.REVERTING) return "REVERTING";
        // if (status == campaignStatusEnum.PAUSED) return "PAUSED"; // reserved: not yet deploy the logic
        // Add additional cases for new status values

        revert("Invalid campaignStatusEnum value");
    }

    // NOTICE: return value are strictly in: 0. 'NotMet', 1. 'Met', 2. "equivalentUSDTarget?", 3. "MetPlusBonus", 4. 'NoTarget'
    function checkFundedTarget(Campaign storage campaign) public view returns (uint16 result) {
        if (
            campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED
                || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED
                || campaign.cStatus.campaignStatus == campaignStatusEnum.PAIDOUT
        ) {
            result = 1;
            return result;
        } else if (
            campaign.cStatus.campaignStatus == campaignStatusEnum.REVERTED
                || campaign.cStatus.campaignStatus == campaignStatusEnum.REVERTING
                || campaign.cStatus.campaignStatus == campaignStatusEnum.DELETED
        ) {
            result = 0;
            return result;
        } // don't care if campaign is success but DELETED OR REVERTED by other reasons

        // if campaign status is OPEN
        // 1. if there're clear target
        if (
            campaign.cFunded.raisedFund.target > 0 || campaign.cFunded.raisedFund.firstTokenTarget > 0
                || campaign.cFunded.raisedFund.secondTokenTarget > 0 || campaign.cFunded.raisedFund.thirdTokenTarget > 0
                || campaign.cFunded.raisedFund.equivalentUSDTarget > 0
        ) {
            if (
                // 1.1 but all target are not met
                (
                    campaign.cFunded.raisedFund.amtFunded < campaign.cFunded.raisedFund.target
                        && campaign.cFunded.raisedFund.amtFunded >= 0
                )
                    && (
                        campaign.cFunded.raisedFund.firstTokenFunded < campaign.cFunded.raisedFund.firstTokenTarget
                            && campaign.cFunded.raisedFund.firstTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.raisedFund.secondTokenFunded < campaign.cFunded.raisedFund.secondTokenTarget
                            && campaign.cFunded.raisedFund.secondTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.raisedFund.thirdTokenFunded < campaign.cFunded.raisedFund.thirdTokenTarget
                            && campaign.cFunded.raisedFund.thirdTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.raisedFund.equivalentUSDFunded < campaign.cFunded.raisedFund.equivalentUSDTarget
                            && campaign.cFunded.raisedFund.equivalentUSDFunded >= 0
                    )
            ) {
                result = 0; // 'NotMet'
            } else {
                // 1.2 others case besides 1.1 which is at least 1 target met
                if (
                    (
                        campaign.cFunded.raisedFund.amtFunded >= campaign.cFunded.raisedFund.target
                            && campaign.cFunded.raisedFund.target > 0
                    )
                        || (
                            campaign.cFunded.raisedFund.equivalentUSDFunded
                                >= campaign.cFunded.raisedFund.equivalentUSDTarget
                                && campaign.cFunded.raisedFund.equivalentUSDTarget > 0
                        )
                        || (
                            campaign.cFunded.raisedFund.firstTokenFunded >= campaign.cFunded.raisedFund.firstTokenTarget
                                && campaign.cFunded.raisedFund.firstTokenTarget > 0
                        )
                        || (
                            campaign.cFunded.raisedFund.secondTokenFunded >= campaign.cFunded.raisedFund.secondTokenTarget
                                && campaign.cFunded.raisedFund.secondTokenTarget > 0
                        )
                        || (
                            campaign.cFunded.raisedFund.thirdTokenFunded >= campaign.cFunded.raisedFund.thirdTokenTarget
                                && campaign.cFunded.raisedFund.thirdTokenTarget > 0
                        )
                ) {
                    result = 1; // 'Met'
                }
            }
        } else {
            // 2. No target (i.e all targets are 0) -> assign 4, don't care any other params
            result = 4; // 'NoTarget' <-> '4NextGen' campaignType
        }
        // check special case after having result = 1 such as: if having any bonus fund?
        if (
            (
                campaign.cFunded.raisedFund.target == 0
                    && campaign.cFunded.raisedFund.amtFunded > campaign.cFunded.raisedFund.target
            )
                || (
                    campaign.cFunded.raisedFund.firstTokenTarget == 0
                        && campaign.cFunded.raisedFund.firstTokenFunded > campaign.cFunded.raisedFund.firstTokenTarget
                )
                || (
                    campaign.cFunded.raisedFund.secondTokenTarget == 0
                        && campaign.cFunded.raisedFund.secondTokenFunded > campaign.cFunded.raisedFund.secondTokenTarget
                )
                || (
                    campaign.cFunded.raisedFund.thirdTokenTarget == 0
                        && campaign.cFunded.raisedFund.thirdTokenFunded > campaign.cFunded.raisedFund.thirdTokenTarget
                )
        ) {
            if (result == 0) {
                // use oracle price feed to calculate equivalentUSDTarget
                result = 2; // 'equivalentUSDTarget?'
            } else if (result == 1) {
                result = 3; // 'MetPlusBonus'
            }
        }
    }

    /**
     * use as library for requestRefund function
     */
    function checkDeletableCampaign(Campaign storage campaign, address contractOwner) internal view returns (bool) {
        require(
            (
                campaign.cStatus.campaignStatus != campaignStatusEnum.DELETED
                    && campaign.cStatus.campaignStatus != campaignStatusEnum.REVERTED
            ),
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    campaignStatusToString(campaign.cStatus.campaignStatus),
                    " -> Campaign was DELETED before or REVERTED."
                )
            )
        );
        require(
            (
                (
                    campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN
                        && (
                            (campaign.cInfo.deadline < block.timestamp && checkFundedTarget(campaign) == 4)
                            || (campaign.cFunded.raisedFund.totalDonating == 0 && campaign.cFunded.voterCount == 0)
                        )
                ) // 12.3: chưa ai contribute vào (tuy nhiên vẫn chấp nhận vote vì không cần số lượng tiền để vote) hoặc TH no target mà không chuyển trạng thái APPROVED rồi lại quá hạn cũng chứng tỏ không ai contribute
                    || campaign.cStatus.campaignStatus == campaignStatusEnum.DRAFT || msg.sender == contractOwner
            ), // use for special case, must ask community, extreme CAREFULL
            // BECAUSE THERE'RE MANY CASES you don't want platform owner to delete such as: APPROVED?, APPROVED_UNLIMITED, PAIDOUT, REVERTING ect.
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    campaignStatusToString(campaign.cStatus.campaignStatus),
                    " -> Campaign can not be DELETED from now on except platform's operator!!!"
                )
            )
        );
        require((msg.sender == campaign.cId.raiser || msg.sender == contractOwner), "Unauthorized Campaign's Owner");
        return true;
    }

    /// @notice Returns an array of backers of a campaign. By default, it ONLY return present backers (i.e. not includes refunded backers, includeRefunded == false by default).
    /// @dev The function iterates over the `campaign.cBacker` array and copies elements to the `backersOfCampaign` array depend of the condition of `includeRefunded`.
    /// @param campaign The campaign storage object.
    /// @return backersOfCampaign An array of backers of the campaign with the `includeRefunded` condition.
    function getBackersOfCampaign(Campaign storage campaign, bool includeRefunded)
        public
        view
        returns (C_Backer[] memory)
    {
        uint256 length;
        if (includeRefunded) {
            length = campaign.cFunded.raisedFund.totalDonating;
        } else {
            length = campaign.cFunded.raisedFund.presentDonating;
        }

        C_Backer[] memory backersOfCampaign = new C_Backer[](length);
        for (uint256 i = 0; i < length; i++) {
            if (campaign.cBacker[i].fundInfo.refunded && !includeRefunded) continue;
            backersOfCampaign[i] = campaign.cBacker[i];
        }

        // IDEA FOR FURTHER UPGRAGE: use memory copy instead of loop iteration for GAS OPTIMIZATION (not yet checked) https://g.co/gemini/share/1eb1868bb087
        // hint: https://g.co/gemini/share/61fe60a42be0
        // assembly {
        //     let backersStart := backersOfCampaign.slot
        //     let campaignBackersStart := campaign.cBacker.slot
        //     let size := mul(length, sizeof(C_Backer))
        //     copy(backersStart, campaignBackersStart, size)
        // }

        return backersOfCampaign;
    }

    /**
     * get contributions from backer in a campaign, filter on condition `refunded`
     * @param campaign The campaign storage object.
     * @param backer The address of the backer.
     * @param refunded true = find contributions that are refunded, false = find contributions that are not refunded
     * @return numberOfContributions The number of contributions found.
     * @return contributionIndexList An array of indexes of the contributions found (`refunded` filter applied).
     */
    function getCampaignContributionsFromBacker(Campaign storage campaign, address backer, bool refunded)
        public
        view
        returns (uint256 numberOfContributions, uint256[] memory)
    {
        C_Backer[] memory backersOfCampaign = getBackersOfCampaign(campaign, refunded);
        uint256 length = backersOfCampaign.length;
        uint256[] memory tempIndexList = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            if (backersOfCampaign[i].backer == backer && backersOfCampaign[i].fundInfo.refunded == refunded) {
                tempIndexList[numberOfContributions] = i;
                numberOfContributions += 1;
            }
        }

        uint256[] memory contributionIndexList = new uint256[](numberOfContributions);
        for (uint256 i = 0; i < numberOfContributions; i++) {
            contributionIndexList[i] = tempIndexList[i];
        }
        return (numberOfContributions, contributionIndexList);
    }

    /**
     * get a campaign without backers
     * Note: different from getNoBackersCampaigns in "s" at the tail, here we just return one campaign without backers, not all.
     */
    function getNoBackersCampaign(Campaign storage campaign)
        public
        view
        returns (CampaignNoBacker memory campaignNoBacker)
    {
        campaignNoBacker.cId = campaign.cId;
        campaignNoBacker.cInfo = campaign.cInfo;
        campaignNoBacker.cFunded = campaign.cFunded;
        campaignNoBacker.cOptions = campaign.cOptions;
        campaignNoBacker.cStatus = campaign.cStatus;
        return campaignNoBacker;
    }

    /// @notice Returns an array of campaigns without backers.
    /// @dev The function iterates over the `campaigns` mapping and copies the campaign information (exclude backers) to the `allCampaigns` array.
    /// @param numberOfRuleCampaign The number of rule campaign.
    /// @param numberOfNormalCampaign The total number of campaigns.
    /// @param campaigns The mapping of campaigns.
    /// @return allCampaigns An array of campaigns without backers.
    /// Note: there'll be a gap between `numberOfRuleCampaign` and `numberOfNormalCampaign`.
    function getNoBackersCampaigns(
        uint256 numberOfRuleCampaign,
        uint256 numberOfNormalCampaign,
        mapping(uint256 => Campaign) storage campaigns
    ) public view returns (CampaignNoBacker[] memory) {
        CampaignNoBacker[] memory allCampaigns =
            new CampaignNoBacker[](numberOfRuleCampaign + numberOfNormalCampaign - MAX_RULES);
        for (uint256 i = 0; i < numberOfRuleCampaign; i++) {
            allCampaigns[i].cId = campaigns[i].cId;
            allCampaigns[i].cInfo = campaigns[i].cInfo;
            allCampaigns[i].cFunded = campaigns[i].cFunded;
            allCampaigns[i].cOptions = campaigns[i].cOptions;
            allCampaigns[i].cStatus = campaigns[i].cStatus;
        }
        for (uint256 i = numberOfRuleCampaign; i < numberOfNormalCampaign - MAX_RULES; i++) {
            allCampaigns[i].cId = campaigns[i + MAX_RULES].cId;
            allCampaigns[i].cInfo = campaigns[i + MAX_RULES].cInfo;
            allCampaigns[i].cFunded = campaigns[i + MAX_RULES].cFunded;
            allCampaigns[i].cOptions = campaigns[i + MAX_RULES].cOptions;
            allCampaigns[i].cStatus = campaigns[i + MAX_RULES].cStatus;
        }
        return allCampaigns;
    }

    /**
     *
     * @param _id campaignId
     * @param _isFraud true = add, false = remove fraud report
     * @param _reportProof text content from reporter
     * @param campaigns storage mapping of campaigns
     * @param mappingCId storage mapping of mappingCId
     * @param fraud storage mapping of fraud
     * @param backerFraudReport storage mapping of backerFraudReport
     * @return success : true = success, false = failed
     * @return reportIndex always return last fraudReportId
     * @return fraudRealtimePct : updated fraud percentage, formular = 100 * (backer's native token funded / total native token funded)
     */
    function backerReportFraud(
        uint256 _id,
        bool _isFraud,
        string memory _reportProof,
        mapping(uint256 => Campaign) storage campaigns,
        mapping(uint256 => MappingCampaignIdTo) storage mappingCId,
        mapping(uint256 => mapping(uint256 => RateDetail)) storage fraud,
        mapping(uint256 => mapping(address => FraudReport)) storage backerFraudReport
    ) internal returns (bool success, uint256 reportIndex, uint256 fraudRealtimePct) {
        require(mappingCId[_id].BackerNativeTokenFunded[msg.sender] > 0, "You're not backer");
        uint256 backerPct =
            (mappingCId[_id].BackerNativeTokenFunded[msg.sender] * 100) / campaigns[_id].cFunded.raisedFund.amtFunded;

        FraudReport memory presentFraudReport = backerFraudReport[_id][msg.sender];
        uint256 lastReportIndex = mappingCId[_id].fraudRateIndexes.fraudReportId;
        if (!presentFraudReport.isFraudNow && _isFraud) {
            // update return variable with workflow: "BACKER ADD FRAUD REPORT"
            mappingCId[_id].fraudRateIndexes.fraudPct += backerPct;
            mappingCId[_id].fraudRateIndexes.fraudReportCounter += 1;
            backerFraudReport[_id][msg.sender].isFraudNow = true;
        } else if (presentFraudReport.isFraudNow && !_isFraud) {
            // update return variable with workflow: "BACKER REMOVE FRAUD REPORT"
            mappingCId[_id].fraudRateIndexes.fraudPct -= backerPct;
            mappingCId[_id].fraudRateIndexes.fraudReportCounter -= 1;
            backerFraudReport[_id][msg.sender].isFraudNow = false;
        } else {
            // if this function fail for unexpected reasons -> set success = false and return present status where reportIndex is always last fraudReportId (lastReportIndex), fraudRealtimePct is old fraudPct
            success = false;
            fraudRealtimePct = mappingCId[_id].fraudRateIndexes.fraudPct;
            return (success, lastReportIndex, fraudRealtimePct);
        }
        // If this function success -> set success = true ...
        success = true;
        backerFraudReport[_id][msg.sender].reportId = lastReportIndex;
        backerFraudReport[_id][msg.sender].reportIDHistory.push(lastReportIndex);
        fraud[_id][lastReportIndex] = RateDetail({
            rater: msg.sender,
            timestamp: block.timestamp,
            star: 0,
            campaignId: _id,
            ratedObject: "raiser", // note: hardcode atm
            content: _reportProof
        });
        mappingCId[_id].fraudRateIndexes.fraudReportId += 1; // update fraudReportId for next use
        fraudRealtimePct = mappingCId[_id].fraudRateIndexes.fraudPct;
        return (success, lastReportIndex, fraudRealtimePct);
    }

    /**
     * set Campaign Final Token name and symbol: only Raiser and Community can call this function
     * 1. Raiser can set campaign final token name and symbol before campaign started
     * 2. Community can set campaign final token name and symbol after campaign started and token symbol is empty
     */
    function setCampaignFinalTokenNameAndSymbol(
        string memory _name,
        string memory _symbol,
        uint256 _forCampaignId,
        mapping(uint256 => MappingCampaignIdTo) storage mappingCId,
        Campaign storage campaign,
        address _setter
    ) external {
        bool isLegitimateRaiser = (campaign.cId.raiser == _setter && campaign.cInfo.startAt > block.timestamp);
        bool isLegitimateCommunityAddr =
            (campaign.cInfo.startAt <= block.timestamp && mappingCId[_forCampaignId].community.presentAddr == _setter);
        require(_setter != address(0), "setter address must not be 0");
        require(isLegitimateRaiser || isLegitimateCommunityAddr, "setter is not raiser or community in RIGHT timeframe");
        require(
            mappingCId[_forCampaignId].resultToken.tokenAddr == address(0)
                && (
                    keccak256(abi.encodePacked(mappingCId[_forCampaignId].resultToken.tokenSymbol))
                        == keccak256(abi.encodePacked(""))
                ),
            "Token already set"
        );

        mappingCId[_forCampaignId].resultToken.tokenName = _name;
        mappingCId[_forCampaignId].resultToken.tokenSymbol = _symbol;
    }

    /**
     * NOTE: should be upgradeable in TokenTemplate1
     */
    function createCampaignFinalToken(
        string memory name,
        string memory symbol,
        // uint256 _forCampaignId,
        CampaignNoBacker memory campaignNoBacker,
        MappingCampaignIdTo storage mappingCId,
        // ContractFunded storage contractFundedInfo,
        address contractOwner // used as operator in new token contract
    ) internal returns (address payable) {
        // NOTE: check if address(this) = GiveUp contract ???
        // TokenTemplate1 newToken = new TokenTemplate1(_name, _symbol, address(this), _forCampaignId, contractOwner);
        TokenTemplate1 newToken =
            new TokenTemplate1(name, symbol, address(this), contractOwner, campaignNoBacker, mappingCId.alchemist);
        // mappingCId.resultToken.tokenIndex = contractFundedInfo.totalCampaignToken;
        // mappingCId.resultToken.tokenAddr = address(newToken);
        // contractFundedInfo.totalCampaignToken += 1;
        return payable(address(newToken));
    }

    /////////////// v129 - 240811 ////////////////////////
    /**
     * testing ...
     *
     */
    function deployTimeLock(Campaign storage campaign, PackedVars1 memory packedVars1)
        internal
        returns (bool, uint256, TimeLockStatus, uint256[] memory, uint256)
    {
        require(
            packedVars1.uintVars[1] == BACKER_WITHDRAW_ALL_CODE
                || (0 <= packedVars1.uintVars[1] && packedVars1.uintVars[1] <= 4),
            "invalid vote option"
        );

        address withdrawer = packedVars1.addressVars[2];
        uint256[] memory refundList = new uint256[](campaign.cFunded.raisedFund.totalDonating); // save indexes
        uint256 refundListCounter;
        bool timeLockFound;
        uint256 latestTimeLockIndex;
        TimeLockStatus lastTimeLockStatus;
        uint256 delayBlockNumberToPreventFrontRun = packedVars1.uintVars[2];

        if (packedVars1.uintVars[1] == BACKER_WITHDRAW_ALL_CODE) {
            for (uint256 i = 0; i < campaign.cFunded.raisedFund.totalDonating; i++) {
                if (campaign.cBacker[i].backer == withdrawer && !campaign.cBacker[i].fundInfo.refunded) {
                    lastTimeLockStatus =
                        timelockForEarlyWithdraw(campaign.cBacker[i], delayBlockNumberToPreventFrontRun);
                    if (lastTimeLockStatus != TimeLockStatus.Approved) {
                        if (!timeLockFound) timeLockFound = true;
                        latestTimeLockIndex = i;
                    } else {
                        refundList[refundListCounter] = i;
                        refundListCounter += 1;
                    }
                }
            }
        } else if (0 <= packedVars1.uintVars[1] && packedVars1.uintVars[1] <= 4) {
            for (uint256 i = 0; i < campaign.cFunded.raisedFund.totalDonating; i++) {
                if (
                    campaign.cBacker[i].backer == withdrawer && !campaign.cBacker[i].fundInfo.refunded
                        && campaign.cBacker[i].voteOption == packedVars1.uintVars[1]
                ) {
                    lastTimeLockStatus =
                        timelockForEarlyWithdraw(campaign.cBacker[i], delayBlockNumberToPreventFrontRun);
                    if (lastTimeLockStatus != TimeLockStatus.Approved) {
                        if (!timeLockFound) timeLockFound = true;
                        latestTimeLockIndex = i;
                    } else {
                        refundList[refundListCounter] = i;
                        refundListCounter += 1;
                    }
                }
            }
        }

        return (timeLockFound, latestTimeLockIndex, lastTimeLockStatus, refundList, refundListCounter);
    }

    /////////////// v129 - 240807 ////////////////////////
    /**
     * testing ...
     * After we know backer is legitimate so we first register him to be able to refund after some block.number by setting requestRefundBlockNumber
     */
    function timelockForEarlyWithdraw(C_Backer storage fund, uint256 delayBlockNumberToPreventFrontRun)
        internal
        returns (TimeLockStatus timeLockStatus)
    {
        if (fund.fundInfo.requestRefundBlockNumber == 0) {
            fund.fundInfo.requestRefundBlockNumber = block.number;
            fund.fundInfo.timeLockStatus = TimeLockStatus.Registered;
            return timeLockStatus = TimeLockStatus.Registered;
        } else if (
            fund.fundInfo.requestRefundBlockNumber > 0
                && (block.number - fund.fundInfo.requestRefundBlockNumber) <= delayBlockNumberToPreventFrontRun
        ) {
            if (fund.fundInfo.timeLockStatus == TimeLockStatus.Registered) {
                fund.fundInfo.timeLockStatus = TimeLockStatus.Waiting;
            }
            return timeLockStatus = TimeLockStatus.Waiting; // delay time not passed yet
        } else if (
            fund.fundInfo.requestRefundBlockNumber > 0
                && (block.number - fund.fundInfo.requestRefundBlockNumber) >= delayBlockNumberToPreventFrontRun
        ) {
            if (fund.fundInfo.timeLockStatus != TimeLockStatus.Approved) {
                fund.fundInfo.timeLockStatus = TimeLockStatus.Approved;
            }
            return timeLockStatus = TimeLockStatus.Approved;
        } else {
            revert("unknown error");
        }
    }
}
