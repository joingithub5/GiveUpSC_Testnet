// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/* 
GIVEUP CRYPTO
bezu0012@gmail.com
https://twitter.com/bezu0012
*/

// WishFunding stage 8: testing 12.5: handle DOWN VOTE with rotten token, delete old comment

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../GlobalVariables_12x.sol";
import {TokenTemplate1} from "../TokenTemplate1.sol";

library GiveUpLib1 {
    event GeneralMsg(string message);

    // RESTRUCTURING in v129 lead to obmit isWhiteListTokenExisted
    // function isWhiteListTokenExisted(
    //     // 12.6 can be used as general purpose to check other list as well
    //     address tokenAddress,
    //     // address[] memory whitelistedTokensAddressList // 12.1
    //     bool whitelistedTokensAddressList // v129
    // ) public pure returns (bool) {
    //     for (uint256 i = 0; i < whitelistedTokensAddressList.length; i++) {
    //         if (whitelistedTokensAddressList[i] == tokenAddress) {
    //             return true;
    //         }
    //     }
    //     return false;
    // }

    /**
     * return the amount that platform take as tax for each successful campaign
     */
    function calculateTax(uint256 _amount, uint256 _campaignTax) public pure returns (uint256) {
        return (_amount * _campaignTax) / 100;
    }

    /* NEED TO TEST DoS when using findAddressIndex function because it use for loop to find index
                */
    /**
     * How to use: if address array which want to be checked is:
     * payable: pass address[](0) to variable addresses
     * not payable: pass address payable[](0) to variable payables
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

    // RESTRUCTURING in v129 lead to obmit checkAddWhiteListToken
    // function checkAddWhiteListToken(
    //     address tokenAddress,
    //     // address[] memory whitelistedTokensAddressList // 12.1
    //     bool whitelistedTokensAddressList // v129
    // ) public pure returns (bool) {
    //     // no need chainId or network because will make one contract for each network
    //     require(!isWhiteListTokenExisted(tokenAddress, whitelistedTokensAddressList), "token address existed");
    //     require(tokenAddress != address(0), "ERC20 token address must not be 0 or native token address");
    //     return true;
    // }

    // function checkRemoveWhiteListToken(
    //     // 12.6 can be used as general purpose to check other list as well
    //     address tokenAddress, // no need token symbol tokenAddress is enough
    //     address[] memory whitelistedTokensAddressList // 12.1
    // ) public pure returns (uint256) {
    //     require(isWhiteListTokenExisted(tokenAddress, whitelistedTokensAddressList), "token address NOT existed");

    //     // Find the index of the tokenAddress in the array
    //     uint256 index = findAddressIndex(tokenAddress, whitelistedTokensAddressList);
    //     require(index < whitelistedTokensAddressList.length, "Token address not found");
    //     return index;
    // }

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
            campaign.cFunded.target > 0 || campaign.cFunded.firstTokenTarget > 0
                || campaign.cFunded.secondTokenTarget > 0 || campaign.cFunded.thirdTokenTarget > 0
                || campaign.cFunded.equivalentUSDTarget > 0
        ) {
            if (
                // 1.1 but all target are not met
                (campaign.cFunded.amtFunded < campaign.cFunded.target && campaign.cFunded.amtFunded >= 0)
                    && (
                        campaign.cFunded.firstTokenFunded < campaign.cFunded.firstTokenTarget
                            && campaign.cFunded.firstTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.secondTokenFunded < campaign.cFunded.secondTokenTarget
                            && campaign.cFunded.secondTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.thirdTokenFunded < campaign.cFunded.thirdTokenTarget
                            && campaign.cFunded.thirdTokenFunded >= 0
                    )
                    && (
                        campaign.cFunded.equivalentUSDFunded < campaign.cFunded.equivalentUSDTarget
                            && campaign.cFunded.equivalentUSDFunded >= 0
                    )
            ) {
                result = 0; // 'NotMet'
            } else {
                // 1.2 others case besides 1.1 which is at least 1 target met
                if (
                    (campaign.cFunded.amtFunded >= campaign.cFunded.target && campaign.cFunded.target > 0)
                        || (
                            campaign.cFunded.equivalentUSDFunded >= campaign.cFunded.equivalentUSDTarget
                                && campaign.cFunded.equivalentUSDTarget > 0
                        )
                        || (
                            campaign.cFunded.firstTokenFunded >= campaign.cFunded.firstTokenTarget
                                && campaign.cFunded.firstTokenTarget > 0
                        )
                        || (
                            campaign.cFunded.secondTokenFunded >= campaign.cFunded.secondTokenTarget
                                && campaign.cFunded.secondTokenTarget > 0
                        )
                        || (
                            campaign.cFunded.thirdTokenFunded >= campaign.cFunded.thirdTokenTarget
                                && campaign.cFunded.thirdTokenTarget > 0
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
            (campaign.cFunded.target == 0 && campaign.cFunded.amtFunded > campaign.cFunded.target)
                || (
                    campaign.cFunded.firstTokenTarget == 0
                        && campaign.cFunded.firstTokenFunded > campaign.cFunded.firstTokenTarget
                )
                || (
                    campaign.cFunded.secondTokenTarget == 0
                        && campaign.cFunded.secondTokenFunded > campaign.cFunded.secondTokenTarget
                )
                || (
                    campaign.cFunded.thirdTokenTarget == 0
                        && campaign.cFunded.thirdTokenFunded > campaign.cFunded.thirdTokenTarget
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
                                || (campaign.cFunded.totalDonating == 0 && campaign.cFunded.voterAddr.length == 0)
                        )
                ) // 12.3: chưa ai đóng vào (vote thì được) hoặc TH no target mà không chuyển trạng thái APPROVED rồi lại quá hạn cũng chứng tỏ không ai donate
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

    /// @notice Returns an array of backers of a campaign.
    /// @dev The function iterates over the `campaign.cBacker` array and copies elements to the `backersOfCampaign` array.
    /// @param campaign The campaign storage object.
    /// @return backersOfCampaign An array of backers of the campaign.
    function getBackersOfCampaign(Campaign storage campaign) public view returns (C_Backer[] memory) {
        uint256 length = campaign.cFunded.totalDonating;
        C_Backer[] memory backersOfCampaign = new C_Backer[](length);
        for (uint256 i = 0; i < length; i++) {
            backersOfCampaign[i] = campaign.cBacker[i];
        }

        // NOTE FOR FURTHER UPGRAGE: use memory copy instead of loop iteration for GAS OPTIMIZATION (not yet checked) https://g.co/gemini/share/1eb1868bb087
        // hint: https://g.co/gemini/share/61fe60a42be0
        // assembly {
        //     let backersStart := backersOfCampaign.slot
        //     let campaignBackersStart := campaign.cBacker.slot
        //     let size := mul(length, sizeof(C_Backer))
        //     copy(backersStart, campaignBackersStart, size)
        // }

        return backersOfCampaign;
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
            (mappingCId[_id].BackerNativeTokenFunded[msg.sender] * 100) / campaigns[_id].cFunded.amtFunded;

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
            // success = false case: reportIndex is always last fraudReportId (lastReportIndex), fraudRealtimePct is old fraudPct
            success = false;
            fraudRealtimePct = mappingCId[_id].fraudRateIndexes.fraudPct;
            return (success, lastReportIndex, fraudRealtimePct);
        }
        // success = true case: reportIndex is always last fraudReportId (lastReportIndex), fraudRealtimePct is has just updated fraudPct above
        success = true;
        backerFraudReport[_id][msg.sender].reportId = lastReportIndex;
        backerFraudReport[_id][msg.sender].reportIDHistory.push(lastReportIndex);
        fraud[_id][lastReportIndex] = RateDetail({
            rater: msg.sender,
            timestamp: block.timestamp,
            star: 0,
            campaignId: _id,
            ratedObject: "raiser",
            content: _reportProof
        });
        mappingCId[_id].fraudRateIndexes.fraudReportId += 1; // update fraudReportId for next use
        fraudRealtimePct = mappingCId[_id].fraudRateIndexes.fraudPct;
        return (success, lastReportIndex, fraudRealtimePct);
    }

    /**
     * set Campaign Final Token name and symbol
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
        bool isLegitimateCommunityAddr = (
            campaign.cInfo.startAt <= block.timestamp && mappingCId[_forCampaignId].community.presentAddr == _setter
                && (
                    keccak256(abi.encodePacked(mappingCId[_forCampaignId].resultToken.tokenSymbol))
                        == keccak256(abi.encodePacked(""))
                )
        );
        require(_setter != address(0), "setter address must not be 0");
        require(isLegitimateRaiser || isLegitimateCommunityAddr, "setter is not raiser or community in RIGHT timeframe");

        mappingCId[_forCampaignId].resultToken.tokenName = _name;
        mappingCId[_forCampaignId].resultToken.tokenSymbol = _symbol;
    }

    /**
     */
    function createCampaignFinalToken(
        string memory _name,
        string memory _symbol,
        uint256 _forCampaignId,
        MappingCampaignIdTo storage mappingCId,
        ContractFunded storage contractFundedInfo
    ) internal returns (address) {
        TokenTemplate1 newToken = new TokenTemplate1(_name, _symbol, address(this), _forCampaignId);
        mappingCId.resultToken.tokenAddr = address(newToken);
        mappingCId.resultToken.tokenIndex = contractFundedInfo.totalCampaignToken;
        contractFundedInfo.totalCampaignToken += 1;
        return address(newToken);
    }

    /////////////// v129 - 240811 ////////////////////////
    /**
     * 
     */
    function deployTimeLock(
        Campaign storage campaign,
        SimpleRequestRefundVars memory simpleVars
    )
        internal
        returns (bool, uint256, TimeLockStatus, uint256[] memory, uint256)
    {
        require(simpleVars.uintVars[1] == BACKER_WITHDRAW_ALL_CODE || (0 <= simpleVars.uintVars[1] && simpleVars.uintVars[1] <= 4), "invalid vote option");
        
        address withdrawer = simpleVars.addressVars[2];
        uint256[] memory refundList = new uint256[](campaign.cFunded.totalDonating); // save indexes
        uint256 refundListCounter;
        bool timeLockFound;
        uint256 latestTimeLockIndex;
        TimeLockStatus lastTimeLockStatus;
        uint256 delayBlockNumberToPreventFrontRun = simpleVars.uintVars[2];

        if (simpleVars.uintVars[1] == BACKER_WITHDRAW_ALL_CODE) {
            for (uint256 i = 0; i < campaign.cFunded.totalDonating; i++) {
                if (campaign.cBacker[i].backer == withdrawer && !campaign.cBacker[i].fundInfo.refunded) {
                    lastTimeLockStatus = timelockForEarlyWithdraw(campaign.cBacker[i], delayBlockNumberToPreventFrontRun);
                    if (lastTimeLockStatus != TimeLockStatus.Approved) {
                        if (!timeLockFound) timeLockFound = true;
                        latestTimeLockIndex = i;
                    } else {
                        refundList[refundListCounter] = i;
                        refundListCounter += 1;
                    }                
                }
            }
        } else if (0 <= simpleVars.uintVars[1] && simpleVars.uintVars[1] <= 4) {
            for (uint256 i = 0; i < campaign.cFunded.totalDonating; i++) {
                if (campaign.cBacker[i].backer == withdrawer && !campaign.cBacker[i].fundInfo.refunded && campaign.cBacker[i].voteOption == simpleVars.uintVars[1]) {
                    lastTimeLockStatus = timelockForEarlyWithdraw(campaign.cBacker[i], delayBlockNumberToPreventFrontRun);
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
