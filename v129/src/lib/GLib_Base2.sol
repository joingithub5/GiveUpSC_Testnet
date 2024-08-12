// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/* 
GIVEUP CRYPTO
bezu0012@gmail.com
https://twitter.com/bezu0012
*/

// WishFunding stage 8: from wishCtrl V0.0.7 11.2.sol: 0.8.13, 200 run, default evm, 11.3 mumbai 0xc599Ab68f6416A1a8eB43Af4FCC65F69361218eF good -> https://w007.vercel.app/
// next: 12.7 logic add at requestRefund for raiser to early delete campaign
// next: 12.7 logic add at requestRefund for raiser to early delete campaign, add ruleId ...

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../GlobalVariables_12x.sol";
import {GiveUpLib1} from "./GLib_Base1.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {TokenTemplate1} from "../TokenTemplate1.sol";

library GiveUpLib2 {
    function toString(uint256 number) public pure returns (string memory) {
        return Strings.toString(number);
    }

    function convertAddressToString(address _address) public pure returns (string memory) {
        return Strings.toHexString(uint160(_address), 20);
    }

    /**
     * @dev Adds an option to the list of options voted for a campaign.
     * @param _id The ID of the campaign.
     * @param _option The option to add.
     * @param _tokenSymbol The symbol of the token used to vote.
     * @param campaignOptionsVoted The mapping of campaign IDs to voter addresses to vote data.
     * @param campaign The campaign object.
     * @return True if the option was added successfully or already added, false otherwise.
     */
    function addOptionsVoted(
        uint256 _id,
        uint256 _option,
        string memory _tokenSymbol,
        mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) storage campaignOptionsVoted,
        Campaign storage campaign
    ) internal returns (bool) {
        bool optionVoted = false; // v129: change addSuccess -> optionVoted: check if _option is already voted?
        uint256 totalVote = 0; // v129: change emptyAt -> totalVote
        for (uint256 i = 0; i < 5; i++) {
            if (
                // campaignOptionsVoted[_id][msg.sender][i].option != 0 ||  // not correct
                keccak256(abi.encodePacked(campaignOptionsVoted[_id][msg.sender][i].tokenSymbol))
                    != keccak256(abi.encodePacked("")) // find i position that hasn't assigned voted token symbol
            ) {
                totalVote += 1; // if i position have assignment -> increase totalVote
            } else {
                break; // exit the for loop
            }
        }

        // if (_option < 5 && _option >= 0) { // v129: change checking at caller
        for (uint256 i = 0; i < totalVote; i++) {
            if (campaignOptionsVoted[_id][msg.sender][i].option == _option) {
                optionVoted = true; // already voted that _option in previous votes
                // break;
                return optionVoted;
            }
        }

        if (!optionVoted) {
            campaignOptionsVoted[_id][msg.sender][totalVote] = VoteData(_option, _tokenSymbol);
            optionVoted = true; // new voted at newest index
        }

        if (totalVote == 0 && optionVoted) {
            campaign.cFunded.voterAddr.push(payable(msg.sender)); // add new voter when he/she first vote thus make item unique
        }
        return optionVoted;
    }

    function updateCampaignUintFields(
        uint256 haveFundTarget,
        string[] memory _uintFields,
        uint256[] memory _uintValues,
        Campaign storage campaign,
        uint256 localStartAt,
        uint256 localDeadline
    ) internal returns (uint256 successUpdate) {
        uint256 intFieldsLength = _uintFields.length;
        for (uint256 i = 0; i < intFieldsLength; i++) {
            if (keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("startAt"))) {
                localStartAt = _uintValues[i];
                successUpdate += 1;
            } else if (keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("deadline"))) {
                localDeadline = _uintValues[i];
                successUpdate += 1;
            } else {
                if (keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("target")) && haveFundTarget > 0) {
                    campaign.cFunded.target = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("firstTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.firstTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("secondTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.secondTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("thirdTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.thirdTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("equivalentUSDTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.equivalentUSDTarget = _uintValues[i];
                    successUpdate += 1;
                } else {
                    if (haveFundTarget > 0) {
                        emit GiveUpLib1.GeneralMsg(
                            string(
                                abi.encodePacked(
                                    "Error: Field - ",
                                    _uintFields[i],
                                    " - not found/ updatable  in the Campaign structure"
                                )
                            )
                        );
                    }
                }
            }
        }
        return successUpdate;
    }

    /**
     * follow strict keywords rule in createCampaign()
     * EXCEPTION RULE: if haveFundTarget == 0, then ALL FUND TARGET WILL ALSO == 0 !!! WHATSOEVER
     * @param haveFundTarget PAY ATTENTION WHEN SETTING TO 0 ! (see Exception Rule above)
     * @param pctForBackers ...
     * @param _stringFields ...
     * @param _uintFields ...
     * @param _arrayFields ...
     * @param _stringValues ...
     * @param _uintValues ...
     * @param _group ...
     * @param _deList ...
     * @param campaign ...
     */
    function updateCampaign(
        uint256 haveFundTarget,
        uint256 pctForBackers,
        string[] memory _stringFields,
        string[] memory _uintFields,
        string[] memory _arrayFields,
        string[] memory _stringValues,
        uint256[] memory _uintValues,
        uint256[] memory _group,
        uint256[] memory _deList,
        Campaign storage campaign
    ) public returns (bool) {
        require(
            (
                campaign.cStatus.campaignStatus == campaignStatusEnum.DRAFT
                    || (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN && campaign.cFunded.totalDonating == 0)
            ),
            string(
                abi.encodePacked(
                    "Campaign' status enum code: ",
                    campaign.cStatus.campaignStatus,
                    " -> can not be UPDATED from now on!!!"
                )
            )
        );
        require(msg.sender == campaign.cId.raiser, "Unauthorized Campaign's Owner");
        require(block.timestamp <= campaign.cInfo.startAt, "start time must be now or in future");

        if (haveFundTarget != campaign.cId.haveFundTarget) {
            campaign.cId.haveFundTarget = haveFundTarget; // new in V008
        }

        // pay attention to haveFundTarget == 0
        if (haveFundTarget == 0) {
            campaign.cFunded.target = 0;
            campaign.cFunded.firstTokenTarget = 0;
            campaign.cFunded.secondTokenTarget = 0;
            campaign.cFunded.thirdTokenTarget = 0;
            campaign.cFunded.equivalentUSDTarget = 0;
        }

        // if (pctForBackers != campaign.cStatus.pctForBackers) {
        if (pctForBackers != campaign.cId.pctForBackers) {
            campaign.cId.pctForBackers = pctForBackers; // v129 // new in w008 12.1
        }

        uint256 stringFieldslength = _stringFields.length;
        for (uint256 i = 0; i < stringFieldslength; i++) {
            if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("campaignType"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cInfo.campaignType = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("title"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cInfo.title = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("description"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cInfo.description = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("image"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cInfo.image = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("option1"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cOptions.option1 = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("option2"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cOptions.option2 = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("option3"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cOptions.option3 = _stringValues[i];
            } else if (
                keccak256(abi.encode(_stringFields[i])) == keccak256(abi.encode("option4"))
                    && keccak256(abi.encode(_stringValues[i])) != keccak256(abi.encode(""))
            ) {
                campaign.cOptions.option4 = _stringValues[i];
            } else {
                emit GiveUpLib1.GeneralMsg(
                    string(
                        abi.encodePacked("Error: Field - ", _stringFields[i], " - not found in the Campaign structure")
                    )
                );
            }
        }

        uint256 localStartAt = campaign.cInfo.startAt;
        uint256 localDeadline = campaign.cInfo.deadline;
        updateCampaignUintFields(haveFundTarget, _uintFields, _uintValues, campaign, localStartAt, localDeadline);

        uint256 arrayFieldslength = _arrayFields.length;
        for (uint256 i = 0; i < arrayFieldslength; i++) {
            if (keccak256(abi.encode(_arrayFields[i])) == keccak256(abi.encode("group"))) {
                campaign.cId.group = _group;
            } else if (keccak256(abi.encode(_arrayFields[i])) == keccak256(abi.encode("deList"))) {
                campaign.cId.deList = _deList;
            }
        }

        if (localStartAt != campaign.cInfo.startAt || localDeadline != campaign.cInfo.deadline) {
            if (block.timestamp <= localStartAt && localStartAt < localDeadline) {
                campaign.cInfo.startAt = localStartAt;
                campaign.cInfo.deadline = localDeadline;
            } else {
                emit GiveUpLib1.GeneralMsg("Error: start time and (or) deadline incorrect");
            }
        }
        return true;
    }

    /**
     * Main Logic of Pay Out Rule: besides checking address(0), campaign status, this function will check conditions for each object to proceed payout:
     * if acceptance text code is "FOL" -> only operator/ contract owner can
     * if haveFundTarget = 100, operator/ contract owner, raiser, alchemist can. Raiser don't need Alchemist's address
     * if 0 < haveFundTarget < 100, operator/ contract owner, raiser, alchemist can but raiser need Alchemist's address approved.
     */
    function payOutCampaign(
        Campaign storage campaign,
        uint256 campaignTax,
        address payable contractOwner,
        address firstToken,
        address secondToken,
        address thirdToken,
        MappingCampaignIdTo storage mappingCId // address payable alchemistAddr
    )
        // ) public returns (bool) {
        internal
        returns (bool)
    {
        require(contractOwner != address(0), "invalid input addresses"); // no need to check firstToken, secondToken, thirdToken because backer can donate native token
        require(
            campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED
                || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED,
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    GiveUpLib1.campaignStatusToString(campaign.cStatus.campaignStatus),
                    " -> can not paidout if status is not in APPROVED_UNLIMITED or already PAIDOUT"
                )
            )
        );
        require(
            keccak256(abi.encode(campaign.cStatus.acceptance)) != keccak256(abi.encode("FOL"))
                || msg.sender == contractOwner,
            "Code 'FOL': Campaign will convert all fund to Platform's token / NFT"
        );
        address alchemistAddr = mappingCId.alchemist.addr;
        require(
            (msg.sender == campaign.cId.raiser && campaign.cId.haveFundTarget > 0) || msg.sender == contractOwner
                || msg.sender == alchemistAddr,
            "Invalid Pay Out Right"
        ); // new in V008: 1. phải xét tránh TH mọi người có thống nhất chuyển việc rút sang token khác vd FER, IAM? 2. raiser phải trừ TH haveFundTarget = 0 3. ngoài ra cho thêm alchemist rút

        // return performPayout(campaign, campaignTax, contractOwner, firstToken, secondToken, thirdToken, alchemistAddr);
        return performPayout(campaign, campaignTax, contractOwner, firstToken, secondToken, thirdToken, mappingCId);
    }

    /**
     * chưa chống reentrancy để test slither
     */
    function mintTokenToBackers(Campaign storage campaign, MappingCampaignIdTo storage mappingCId, TokenTemplate1 token)
        internal
    {
        uint256 totalBackers = campaign.cFunded.voterAddr.length;
        uint256 totalNativeTokenFunded = campaign.cFunded.amtFunded;
        uint256 maxSupply = token.getMaxSupplyOfTokenTemplate1();
        for (uint256 i = 0; i < totalBackers; i++) {
            address backer = payable(campaign.cFunded.voterAddr[i]);
            uint256 backerPct = (mappingCId.BackerNativeTokenFunded[backer] * 100) / totalNativeTokenFunded;
            uint256 amt = (backerPct * maxSupply) / 100;
            // token.mint(backer, amt)
            try token.mint(backer, amt) {
                // Successfully minted the token to the backer
            } catch {
                // Failed to mint the token to the backer, skip to the next backer
                continue;
            }
        }
    }

    /**
     * performCampaignTokenPayout:
     */
    function performCampaignTokenPayout(
        Campaign storage campaign,
        MappingCampaignIdTo storage mappingCId,
        ContractFunded storage contractFundedInfo
    ) internal returns (bool) {
        /**
         * tạo token và return token address
         */
        string memory _symbol = mappingCId.resultToken.tokenSymbol;
        if (bytes(_symbol).length == 0) {
            return false;
        }
        string memory _name = mappingCId.resultToken.tokenName;
        address tokenAddr =
            GiveUpLib1.createCampaignFinalToken(_name, _symbol, campaign.cId.id, mappingCId, contractFundedInfo);
        TokenTemplate1 token = TokenTemplate1(tokenAddr); // ERC20 token = ERC20(tokenAddr);

        /* check haveFundTarget & pctForBackers
        * check alchemist base on haveFundtarget and Alchemist proposal setting from raiser, community
        * then mint token to backers, raiser
        *         NOTE: 
        *  - NOT YET CHECK IF A BACKER IS A CONTRACT THAT CAN NOT RECEIVE ERC20 TOKEN, IN THIS CASE IT JUST SKIP TO THE NEXT BACKER
        *  - Alchemist DO NOT receive token because they only want to receive fund as payment for their services
        */
        uint256 haveFundTarget = campaign.cId.haveFundTarget;
        if (haveFundTarget == 100 || haveFundTarget == 0) {
            mintTokenToBackers(campaign, mappingCId, token);
            // if haveFundTarget == 100 raiser will receive 100% fund, don't receive token, no alchemist involved
            // if haveFundTarget == 0 raiser receive nothing, alchemist involved and get fund percentage = (100 - pctForBackers) as fee for their service, not token
        } else if (0 < haveFundTarget && haveFundTarget < 100) {
            /**
             * Mint token to backers and raiser
             * only alchemist can receive fund (100 - pctForBackers) similar to 1st case
             * LIQUIDITY pct = pctForBackers: send all raised fund after deduct fees to liquidity pool of this token
             */
            mintTokenToBackers(campaign, mappingCId, token);
            uint256 raiserAmt =
                ((100 - campaign.cId.pctForBackers) * token.getMaxSupplyOfTokenTemplate1() / 100) * haveFundTarget / 100;
            token.mint(campaign.cId.raiser, raiserAmt);
        } else {
            revert("Invalid haveFundTarget value");
        }
        return false;
    }

    /**
     * IS LIBRARY OF payOutCampaign function
     * Perform Payout Rule: simply check
     * - haveFundTarget = 100, Raiser don't need to update Alchemist to pay out.
     * - haveFundTarget < 100, Raiser need to have Alchemist's address to pay out.
     */
    function performPayout(
        Campaign storage campaign,
        uint256 campaignTax,
        address payable contractOwner,
        address firstToken,
        address secondToken,
        address thirdToken,
        MappingCampaignIdTo storage mappingCId // address payable alchemistAddr
    ) internal returns (bool result) {
        result = false;
        address alchemistAddr = mappingCId.alchemist.addr;
        // if (campaign.cFunded.amtFunded > 0) { // v129
        if (campaign.cFunded.amtFunded > 0 && campaign.cFunded.paidOut.nativeTokenPaidOut == false) {
            uint256 amtFunded = campaign.cFunded.amtFunded;
            // campaign.cFunded.amtFunded = 0; // v129
            campaign.cFunded.paidOut.nativeTokenPaidOut = true;
            uint256 tax_amt = GiveUpLib1.calculateTax(amtFunded, campaignTax);
            uint256 payingRaiser = GiveUpLib1.calculateTax((amtFunded - tax_amt), campaign.cId.haveFundTarget);

            (bool sent_raiser,) = payable(campaign.cId.raiser).call{value: (payingRaiser)}("");
            require(sent_raiser, "Payout raiser failed");
            if (campaignTax > 0) {
                (bool sent_platform,) = payable(contractOwner).call{value: tax_amt}("");
                require(sent_platform, "Payout platform failed");
            }
            if (campaign.cId.haveFundTarget < 100) {
                (bool sent_alchemist,) = payable(alchemistAddr).call{value: (amtFunded - tax_amt - payingRaiser)}("");
                require(sent_alchemist, "Payout alchemist failed");
            }
        }

        // if (campaign.cFunded.firstTokenFunded > 0) { // v129
        if (campaign.cFunded.firstTokenFunded > 0 && campaign.cFunded.paidOut.firstTokenPaidOut == false) {
            ERC20 token = ERC20(firstToken);
            uint256 tokenFunded = campaign.cFunded.firstTokenFunded;
            // campaign.cFunded.firstTokenFunded = 0; // v129
            campaign.cFunded.paidOut.firstTokenPaidOut = true;

            uint256 tax_amt = GiveUpLib1.calculateTax(tokenFunded, campaignTax);
            uint256 payingRaiser = GiveUpLib1.calculateTax((tokenFunded - tax_amt), campaign.cId.haveFundTarget);
            if (campaignTax > 0) {
                token.approve(contractOwner, tax_amt);
                token.transfer(contractOwner, tax_amt);
            }

            token.approve(campaign.cId.raiser, payingRaiser);
            token.transfer(campaign.cId.raiser, payingRaiser);

            if (campaign.cId.haveFundTarget < 100) {
                token.approve(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
                token.transfer(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
            }
        }

        // if (campaign.cFunded.secondTokenFunded > 0) { // v129
        if (campaign.cFunded.secondTokenFunded > 0 && campaign.cFunded.paidOut.secondTokenPaidOut == false) {
            ERC20 token = ERC20(secondToken);
            uint256 tokenFunded = campaign.cFunded.secondTokenFunded;
            // campaign.cFunded.secondTokenFunded = 0; // v129
            campaign.cFunded.paidOut.secondTokenPaidOut = true;

            // làm tương tự firstTokenFunded bên trên
            uint256 tax_amt = GiveUpLib1.calculateTax(tokenFunded, campaignTax);
            uint256 payingRaiser = GiveUpLib1.calculateTax((tokenFunded - tax_amt), campaign.cId.haveFundTarget);
            if (campaignTax > 0) {
                token.approve(contractOwner, tax_amt);
                token.transfer(contractOwner, tax_amt);
            }

            token.approve(campaign.cId.raiser, payingRaiser);
            token.transfer(campaign.cId.raiser, payingRaiser);

            if (campaign.cId.haveFundTarget < 100) {
                token.approve(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
                token.transfer(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
            }
        }

        // if (campaign.cFunded.thirdTokenFunded > 0) { // v129
        if (campaign.cFunded.thirdTokenFunded > 0 && campaign.cFunded.paidOut.thirdTokenPaidOut == false) {
            ERC20 token = ERC20(thirdToken);
            uint256 tokenFunded = campaign.cFunded.thirdTokenFunded;
            // campaign.cFunded.thirdTokenFunded = 0; // v129
            campaign.cFunded.paidOut.thirdTokenPaidOut = true;

            // làm tương tự firstTokenFunded bên trên
            uint256 tax_amt = GiveUpLib1.calculateTax(tokenFunded, campaignTax);
            uint256 payingRaiser = GiveUpLib1.calculateTax((tokenFunded - tax_amt), campaign.cId.haveFundTarget);
            if (campaignTax > 0) {
                token.approve(contractOwner, tax_amt);
                token.transfer(contractOwner, tax_amt);
            }

            token.approve(campaign.cId.raiser, payingRaiser);
            token.transfer(campaign.cId.raiser, payingRaiser);

            if (campaign.cId.haveFundTarget < 100) {
                token.approve(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
                token.transfer(alchemistAddr, tokenFunded - tax_amt - payingRaiser);
            }
        }
        campaign.cStatus.campaignStatus = campaignStatusEnum.PAIDOUT;
        result = true;
        return result;
    }

    /* Note: only ultilize some beginning field of input array, e.g _content array only use 4 first elements
    */
    function createCampaign(
        uint256 _haveFundTarget, // percentage for raiser, 0% = non profit/long term, 100=100% = tip/donation/no return ect
        uint256 _pctForBackers, // v129
        string[] memory _content, // 0.campaignType, 1.title, 2.description, 3.image
        string[] memory _options, // can be blank for basic campaign purpose, max 4 options by struct C_Options
        uint256[] memory _timeline, // startAt, deadline
        uint256[] memory _group, // new, read guidance
        uint256[] memory _deList, // new, read guidance
        uint256[] memory _fund, // 0.target, 1.firstTokenTarget, 2.secondTokenTarget, 3.thirdTokenTarget, 4.equivalentUSDTargetß
        uint256 _id, // store settingId from main contract
        Campaign storage campaign
    ) public returns (bool) {
        require( // _startAt -> _timeline[0] ...
        _timeline[0] >= block.timestamp && _timeline[0] < _timeline[1], "start time and deadline invalid");
        require(
            bytes(_content[1]).length > 0 || bytes(_content[2]).length > 0 || bytes(_content[3]).length > 0,
            "Title/ Description/ Media URL cannot be empty"
        );
        require(
            (_fund[0] > 0 ether || _fund[1] > 0 || _fund[2] > 0 || _fund[3] > 0 || _fund[4] > 0 || _haveFundTarget == 0),
            "At least ONE Fund Target Amount must >= 0 or campaign type is NoFundTarget"
        );
        campaign.cId = C_Id({
            id: _id,
            raiser: payable(msg.sender),
            group: _group,
            deList: _deList,
            haveFundTarget: _haveFundTarget, // new in V006 10_1
            pctForBackers: _pctForBackers // v129
        });
        campaign.cInfo = C_Info({
            campaignType: _content[0],
            title: _content[1],
            description: _content[2],
            image: _content[3],
            createdAt: block.timestamp,
            startAt: _timeline[0],
            deadline: _timeline[1]
        });
        // only set specific fund target if _haveFundTarget > 0
        if (_haveFundTarget > 0) {
            campaign.cFunded.target = _fund[0];
            campaign.cFunded.firstTokenTarget = _fund[1];
            campaign.cFunded.secondTokenTarget = _fund[2];
            campaign.cFunded.thirdTokenTarget = _fund[3];
            campaign.cFunded.equivalentUSDTarget = _fund[4];
        }

        campaign.cOptions =
            C_Options({option1: _options[0], option2: _options[1], option3: _options[2], option4: _options[3]});

        campaign.cStatus.campaignStatus = campaignStatusEnum.OPEN;

        return true;
    }

    function signAcceptance(
        Campaign storage campaign,
        address payable alchemistAddr,
        string memory _acceptance // ) internal {
    )
        // ) public {
        internal
    {
        require(
            campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED
                || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED,
            "campaign status must be APPROVED or APPROVED_UNLIMITED"
        );
        require(bytes(_acceptance).length != 0, "acceptance text cannot be empty");
        require(
            (alchemistAddr != address(0) && alchemistAddr == msg.sender && campaign.cId.haveFundTarget <= 50)
                || (campaign.cId.raiser == msg.sender && campaign.cId.haveFundTarget > 50),
            "wrong rule logic"
        );

        campaign.cStatus.acceptance = _acceptance;
    }

    /* backer/voter can withdraw their vote/donation (with _earlyWithdraw option in caller function); 
    _voteOption usage: see note in donateToCampaign function. 
    No need to provide token symbol (because this is reset action) */
    function removeOptionsVoted(
        uint256 _id,
        uint256 _voteOption,
        mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) storage campaignOptionsVoted,
        Campaign storage campaign
    ) internal returns (bool) {
        bool deleteSuccess = false;
        if (0 <= _voteOption && _voteOption <= 4) {
            uint256 totalVote = 0; // v129: change emptyAt -> totalVote
            uint256 deleteAt = 1000; // find the position of _voteOption in voter's voting list, e.g: if voter vote 3 times: 1st vote is option2, 2nd vote is option4, 3rd vote is option0, then result when finding option0 is deleteAt == 2 (3rd vote). Default 1000 is just a big number outside of range 0-4 for calculation purpose.
            for (uint256 i = 0; i < 5; i++) {
                if (
                    // campaignOptionsVoted[_id][msg.sender][i].option != 0 || // depricated
                    // a voted option must have wl token symbol != "" => use this as check condition
                    keccak256(abi.encodePacked(campaignOptionsVoted[_id][msg.sender][i].tokenSymbol))
                        != keccak256(abi.encodePacked(""))
                ) {
                    totalVote = totalVote + 1; // increase total voted options
                    // then check if in this i position, voter has voted for _voteOption?
                    if (campaignOptionsVoted[_id][msg.sender][i].option == _voteOption) {
                        deleteAt = i; // if yes, then note this position to remove
                            // break; // can not exit the loop here because need to calculate totalVote // exit the for loop early to save calculation cost
                    }
                } // this function totally depend on the correctness of addOptionsVoted function, if addOptionsVoted allow duplicate vote option then this removeOptionsVoted will fail in it purpose.

                /* PROBLEM 1: need to test it we need to asert if there're any case when deleteAt > totalVote?
                if YES then addOptionsVoted were fail -> removeOptionsVoted will also fail !!!
                */
            }

            if (deleteAt == 1000) {
                // not found _voteOption in voter's voting list, return false as result
                return false;
            }

            // after above deleteAt checking then start to delete vote info at deleteAt position, e.g, totalVote == 1 -> deleteAt == 0, totalVote == 5 -> deleteAt can be anywhere in range 0, 1, 2, 3, 4
            if (deleteAt < totalVote - 1) {
                campaignOptionsVoted[_id][msg.sender][deleteAt] = campaignOptionsVoted[_id][msg.sender][totalVote - 1];
                // campaignOptionsVoted[_id][msg.sender][totalVote - 1] = VoteData(0,"");  // test ok
                delete campaignOptionsVoted[_id][msg.sender][totalVote - 1]; // also test ok
                deleteSuccess = true;
                // } else if (deleteAt == totalVote - 1) { // find bug with InteractionsTest.t.sol - testVoteDonateInteraction !
            } else if (deleteAt == totalVote - 1 || deleteAt == totalVote) {
                // campaignOptionsVoted[_id][msg.sender][deleteAt] = VoteData(0,"");  // test ok
                delete campaignOptionsVoted[_id][msg.sender][deleteAt]; // also test ok
                deleteSuccess = true;
            } else if (deleteAt > totalVote && deleteAt <= 4) {
                /* CATCH AND HANDLE PROBLEM 1 ABOVE: 
                - still delete that vote record at deleteAt position
                - next revision: make error message
                */
                delete campaignOptionsVoted[_id][msg.sender][deleteAt];
                deleteSuccess = true;
            }

            // in case this is the last vote of voter, then delete voter's address from voter's list
            if (totalVote == 1 && deleteSuccess) {
                (, uint256 index) =
                    GiveUpLib1.findAddressIndex(msg.sender, new address[](0), campaign.cFunded.voterAddr);

                /* NEED TO TEST DoS when using findAddressIndex function because it use for loop to find index
                */
                if (index < campaign.cFunded.voterAddr.length - 1) {
                    // Move the last element to the index to be removed
                    campaign.cFunded.voterAddr[index] =
                        campaign.cFunded.voterAddr[campaign.cFunded.voterAddr.length - 1];
                    // Remove the last element
                    campaign.cFunded.voterAddr.pop();
                } else if (index == campaign.cFunded.voterAddr.length - 1) {
                    campaign.cFunded.voterAddr.pop();
                }
            }
        }

        return deleteSuccess;
    }

    /* depend on campaign's status and other conditions that:
    - raiser can DELETE the campaign and REFUND all backer with RAISER_DELETE_ALL_CODE
    - everyone can withdraw A SPECIFIC vote option.
    - everyone can withdraw ALL vote options with BACKER_WITHDRAW_ALL_CODE
    */
    function requestRefund(
        SimpleRequestRefundVars memory simpleVars,
        Campaign storage campaign,
        mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) storage campaignOptionsVoted,
        ContractFunded storage contractFundedInfo,
        // v129 below mapping cIdTo will depricate campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded, campaignDonatorTokenFunded, campaignOptionTokenFunded
        MappingCampaignIdTo storage cIdTo,
        // mapping(uint256 => mapping(address => mapping(address => uint256))) storage campaignDonatorTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => mapping(address => uint256))) storage campaignOptionTokenFunded, // v129
        // // mapping(string => address) storage whitelistedTokens, // v129: no need because refund don't check wl token
        // mapping(uint256 => mapping(address => uint256)) storage campaignDonatorNativeTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => uint256)) storage campaignOptionNativeTokenFunded, // v129
        mapping(address => string) storage tokenAddrToPriority
    )
        // uint256 numberOfCampaignsExcludeRefunded
        // public
        internal
        returns (
            // returns (string memory reportString, bool timelockForRefund)
            string memory reportString,
            bool isTimelockForRefund,
            TimeLockStatus returnTimeLockStatus
        )
    {
        // simpleVars.addressVars[0] contain platform/ contract owner address
        // that temporary allowed to delete on going campaign so I add it here
        // there's another checking in checkDeletableCampaign() afterward but for contract owner to be able to delete when campaign is not going on.
        require(
            (
                msg.sender == simpleVars.addressVars[0]
                    || campaign.cStatus.campaignStatus == campaignStatusEnum.REVERTING
                    || (
                        (
                            campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN
                                || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED
                        )
                            && (
                                campaign.cInfo.deadline < block.timestamp || block.timestamp < campaign.cInfo.startAt
                                    || simpleVars.earlyWithdraw
                            )
                    )
            ),
            string(
                abi.encodePacked(
                    "Campaign' status: ",
                    GiveUpLib1.campaignStatusToString(campaign.cStatus.campaignStatus),
                    " -> Can only refund if caller is the contract platform or Campaign expired & failed or in REVERTING period!"
                )
            )
        );

        uint256 totalNumber; // number of funds to be refunded
        // string memory reportString;
        // there's important upgrade from v12.3
        // First performRefund occur when backer withdraw his fund when campaign failed to meet target
        if (simpleVars.uintVars[1] != RAISER_DELETE_ALL_CODE) {
            if (!simpleVars.earlyWithdraw) {
                // Withdrawal when campaign failed
                (totalNumber,,) = performRefund(
                    simpleVars,
                    campaign,
                    REVERTING,
                    contractFundedInfo,
                    cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                    // campaignDonatorTokenFunded,
                    // campaignOptionTokenFunded,
                    // // whitelistedTokens, // v129 depricated
                    // campaignDonatorNativeTokenFunded,
                    // campaignOptionNativeTokenFunded,
                    tokenAddrToPriority
                );
                // numberOfCampaignsExcludeRefunded
                // Second performRefund occur when backer withdraw early: using EARLY_WITHDRAW code
            } else {
                // bool registerEarlyWithdraw = false;
                (totalNumber, isTimelockForRefund, returnTimeLockStatus) = performRefund(
                    simpleVars,
                    campaign,
                    EARLY_WITHDRAW,
                    contractFundedInfo,
                    cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                    // campaignDonatorTokenFunded,
                    // campaignOptionTokenFunded,
                    // // whitelistedTokens, // v129 depricated
                    // campaignDonatorNativeTokenFunded, // v129
                    // campaignOptionNativeTokenFunded, // v129
                    tokenAddrToPriority
                );

                /////////////// v129 - 240807 ////////////////////////
                /**
                 * check for cases when backer registered to withdraw successfully but not actually withdraw yet (TimeLockStatus.Registered) or in waiting timeframe (TimeLockStatus.Waiting) then return immidiately to avoid remove vote options
                 */
                if (
                    (
                        returnTimeLockStatus == TimeLockStatus.Registered
                            || returnTimeLockStatus == TimeLockStatus.Waiting
                    ) && isTimelockForRefund
                ) {
                    return (toString(totalNumber), isTimelockForRefund, returnTimeLockStatus); // there's `true` timelock at index `totalNumber` w/ status `returnTimeLockStatus`
                }

                // numberOfCampaignsExcludeRefunded
                // handle EARLY_WITHDRAW of vote option (V006 10.9)
                if (simpleVars.uintVars[1] == BACKER_WITHDRAW_ALL_CODE) {
                    for (uint256 i = 0; i < 5; i++) {
                        // campaignOptionsVoted[simpleVars.uintVars[0]][msg.sender][i] = VoteData(0,"");  // reset cách 1 ok
                        delete campaignOptionsVoted[simpleVars.uintVars[0]][
                            msg.sender
                        ][i]; // reset cách 2 ok
                    }
                    // campaign.cFunded.voterAddr -= 1;
                    (, uint256 index) =
                        GiveUpLib1.findAddressIndex(msg.sender, new address[](0), campaign.cFunded.voterAddr);

                    /* NEED TO TEST DoS when using findAddressIndex function because it use for loop to find index
                    */

                    // Move the last element to the index to be removed
                    campaign.cFunded.voterAddr[index] =
                        campaign.cFunded.voterAddr[campaign.cFunded.voterAddr.length - 1];
                    // Remove the last element
                    campaign.cFunded.voterAddr.pop();
                    reportString = "Removed ALL vote options";
                } else {
                    if (
                        removeOptionsVoted(
                            simpleVars.uintVars[0], simpleVars.uintVars[1], campaignOptionsVoted, campaign
                        )
                    ) {
                        reportString = "Remove vote option SUCCESS";
                    } else {
                        reportString = "Remove vote option FAILED";
                    }
                }
            }
            // Third performRefund occur when RAISER want to DELETE (cancel) his campaign and refund to backers
        } else {
            if (GiveUpLib1.checkDeletableCampaign(campaign, simpleVars.addressVars[0])) {
                (totalNumber,,) = performRefund(
                    simpleVars,
                    campaign,
                    DELETED,
                    contractFundedInfo,
                    cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                    // campaignDonatorTokenFunded,
                    // campaignOptionTokenFunded,
                    // // whitelistedTokens, // v129 depricated
                    // campaignDonatorNativeTokenFunded, // v129
                    // campaignOptionNativeTokenFunded, // v129
                    tokenAddrToPriority
                );
                // numberOfCampaignsExcludeRefunded
                // new in 12.3: add checking if raiser is allowed to DELETE and refund campaign
            }
        }

        if (totalNumber > 0) {
            reportString = string(abi.encodePacked("Proscessed ", toString(totalNumber), " donation(s)"));
            emit GiveUpLib1.GeneralMsg(
                string(
                    abi.encodePacked(
                        "SUCCESSFULLY REFUND cId ",
                        toString(simpleVars.uintVars[0]),
                        ", msg.sender: ",
                        convertAddressToString(msg.sender),
                        ", timestamp: ",
                        toString(block.timestamp)
                    )
                )
            );
        } else {
            reportString = string(abi.encodePacked(reportString, " + Nothing to refund"));
        }
        return (reportString, false, returnTimeLockStatus);
    }

    /**
     * The performRefund function is used to initiate the refund process for a campaign based on the given reason.
     * It performs refunds for backers of the campaign who have contributed funds.
     * If the reason is DELETED (initiated by the campaign raiser/ operator), refunds are performed for all backers.
     * If the reason is REVERTING (initiated by a backer), refunds are performed only for the specific backer only after campaign expired with failure.
     * If the reason is EARLY_WITHDRAW (initiated by a backer), refunds are performed for backer even when campaign is going on.
     * It simply loop through ALL backer, check refund condition (such as: all or specific option) and perform refund by calling singleRefund.
     * After the refunds are processed, the refundCompleted function is called to update the campaign status.
     * @param _reason The reason for the refund (must be 3 constants: EARLY_WITHDRAW, DELETED or REVERTING).
     * @return totalNumber : The number of funds to be refunded.
     * @return isTimelockForRefund : true mean backer enter refund process, it'll change some stages in backer's fundInfo variable such as: TimeLockStatus.Registered, TimeLockStatus.Waiting, ... to prevent front running
     * @return returnTimeLockStatus : The status of the refund process.
     */
    function performRefund(
        SimpleRequestRefundVars memory simpleVars,
        Campaign storage campaign,
        string memory _reason,
        ContractFunded storage contractFundedInfo,
        // v129 below mapping cIdTo will depricate campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded, campaignDonatorTokenFunded, campaignOptionTokenFunded
        MappingCampaignIdTo storage cIdTo,
        // mapping(uint256 => mapping(address => mapping(address => uint256))) storage campaignDonatorTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => mapping(address => uint256))) storage campaignOptionTokenFunded, // v129
        // // mapping(string => address) storage whitelistedTokens, // v129: no need because refund don't check wl token
        // mapping(uint256 => mapping(address => uint256)) storage campaignDonatorNativeTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => uint256)) storage campaignOptionNativeTokenFunded, // v129
        mapping(address => string) storage tokenAddrToPriority
    )
        // uint256 numberOfCampaignsExcludeRefunded
        internal
        returns (
            // returns (uint256 totalNumber, bool timelockForRefund)
            // returns (uint256 totalNumber, bool timelockForRefund, string memory returnRefundStatus)
            uint256 totalNumber,
            bool isTimelockForRefund,
            TimeLockStatus returnTimeLockStatus
        )
    {
        require(simpleVars.addressVars[2] == msg.sender, "temp extra test");
        // uint256[] memory refundList = new uint256[](campaign.cFunded.totalDonating); // save indexes
        // uint256 refundListCounter;
        // bool timeLockFound;
        // uint256 latestTimeLockIndex;
        // TimeLockStatus lastTimeLockStatus;

        // if reason is EARLY_WITHDRAW, we will not call refundCompleted function and exit performRefund
        if (keccak256(bytes(_reason)) == keccak256(bytes(EARLY_WITHDRAW))) {
            // v129 - 240811 deploy refund for `EARLY_WITHDRAW` above base on refundList, refundListCounter or return failure notice base on timeLockFound.
            (bool timeLockFound, uint256 latestTimeLockIndex, TimeLockStatus lastTimeLockStatus, uint256[] memory refundList, uint256 refundListCounter) = GiveUpLib1.deployTimeLock(campaign, simpleVars);
            if (timeLockFound) {
                return (latestTimeLockIndex, true, lastTimeLockStatus); // meet timelock (return true) at index i w/ timeLockStatus
            } else if (refundListCounter > 0) {
                for (uint256 i = 0; i < refundListCounter; i++) {
                    if (
                        singleRefund(
                            simpleVars,
                            refundList[i],
                            true,
                            campaign,
                            contractFundedInfo,
                            cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                            // campaignDonatorTokenFunded,
                            // campaignOptionTokenFunded,
                            // // whitelistedTokens, // v129 depricated
                            // campaignDonatorNativeTokenFunded, // v129
                            // campaignOptionNativeTokenFunded, // v129
                            tokenAddrToPriority
                        )
                    ) {
                        totalNumber += 1;
                    }
                }
            }
            return (totalNumber, false, returnTimeLockStatus); // don't call refundCompleted
        }

        // if reason is DELETED or REVERTING will proceed then call refundCompleted function before exit performRefund
        if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
            // refund all backers
            for (uint256 i = 0; i < campaign.cFunded.totalDonating; i++) {
                if (
                    singleRefund(
                        simpleVars,
                        i,
                        false,
                        campaign,
                        contractFundedInfo,
                        cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                        // campaignDonatorTokenFunded,
                        // campaignOptionTokenFunded,
                        // // whitelistedTokens, // v129 depricated
                        // campaignDonatorNativeTokenFunded, // v129
                        // campaignOptionNativeTokenFunded, // v129
                        tokenAddrToPriority
                    )
                ) {
                    totalNumber += 1;
                }
            }
        } else if (keccak256(bytes(_reason)) == keccak256(bytes(REVERTING))) {
            /**
             * NEXT: OPTIMIZE REVERTING by combining all donations of a backer if needed ?
             * CAUTION / Q: DoS when campaign.cFunded.totalDonating is big ???
             */
            // refund for msg.sender only
            for (uint256 i = 0; i < campaign.cFunded.totalDonating; i++) {
                if (campaign.cBacker[i].backer == msg.sender) {
                    if (
                        singleRefund(
                            simpleVars,
                            i,
                            false,
                            campaign,
                            contractFundedInfo,
                            cIdTo, // v129 will depricate below variables: campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded...
                            // campaignDonatorTokenFunded,
                            // campaignOptionTokenFunded,
                            // // whitelistedTokens, // v129 depricated
                            // campaignDonatorNativeTokenFunded, // v129
                            // campaignOptionNativeTokenFunded, // v129
                            tokenAddrToPriority
                        )
                    ) {
                        totalNumber += 1;
                    }
                }
            }
        }

        // call refundCompleted function depend on totalNumber variable
        if (totalNumber > 0) {
            // i.e there're refunds ... -> update campaign status
            // refundCompleted(_reason, campaign, numberOfCampaignsExcludeRefunded);
            refundCompleted(_reason, campaign, contractFundedInfo);
            // in case last donator withdraw and set status to REVERTED then will update numberOfCampaignsExcludeRefund there
            if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
                contractFundedInfo.totalFundedCampaign -= 1; // numberOfCampaignsExcludeRefunded only count campaign that have remain backers
            }
        } else {
            // if there're no refund...
            // refundCompleted(_reason, campaign, numberOfCampaignsExcludeRefunded);
            refundCompleted(_reason, campaign, contractFundedInfo);
        }
        return (totalNumber, false, returnTimeLockStatus);
    }

    // refund
    function singleRefund(
        SimpleRequestRefundVars memory simpleVars,
        uint256 i, // index of funds
        bool _earlyWithdraw,
        Campaign storage campaign,
        ContractFunded storage contractFundedInfo,
        // v129 below mapping cIdTo will depricate campaignDonatorNativeTokenFunded, campaignOptionNativeTokenFunded, campaignDonatorTokenFunded, campaignOptionTokenFunded
        MappingCampaignIdTo storage cIdTo,
        // mapping(uint256 => mapping(address => mapping(address => uint256))) storage campaignDonatorTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => mapping(address => uint256))) storage campaignOptionTokenFunded, // v129
        // // mapping(string => address) storage whitelistedTokens, // v129: no need because refund don't check wl token
        // mapping(uint256 => mapping(address => uint256)) storage campaignDonatorNativeTokenFunded, // v129
        // mapping(uint256 => mapping(uint256 => uint256)) storage campaignOptionNativeTokenFunded, // v129
        mapping(address => string) storage tokenAddrToPriority
    ) internal returns (bool) {
        C_Backer storage fund = campaign.cBacker[i];
        address payable recipient = fund.backer;

        /* NOTICE: AT TESTNET WILL TURN OF INTENDED FEATURE USING penaltyContract to hold withdrawal fund
        */
        // if (_earlyWithdraw) {
        //     recipient = payable(simpleVars.addressVars[1]); // penaltyContract
        // }

        /* ATTENTION:
        v129: First check for native token refund because ERC20 token will be asigned a specific address at receiving stage. Besides, check token address for address(0) to make sure in this case it's native token. 
        */

        if (
            // keccak256(abi.encode(fund.tokenSymbol)) == keccak256(abi.encode(simpleVars.stringVars[0])) && fund.qty > 0
            //     && fund.refunded == false && fund.tokenAddr == address(0)
            keccak256(abi.encode(fund.tokenSymbol)) == keccak256(abi.encode(simpleVars.stringVars[0])) && fund.qty > 0
                && fund.fundInfo.refunded == false && fund.tokenAddr == address(0)
                && fund.fundInfo.timeLockStatus == TimeLockStatus.Approved
        ) {
            // fund.refunded = true; // avoid reentrancy attack
            fund.fundInfo.refunded = true; // avoid reentrancy attack
            // not reset funds[i].qty to 0 because set refunded to true is enough, keep funds[i].qty as a proof of donating even if campaign is failed and backer withdrew.
            fund.fundInfo.refundTimestamp = block.timestamp; // v129

            (bool success,) = payable(recipient).call{value: fund.qty}("");
            if (success) {
                // fund.timestamp = block.timestamp;
                contractFundedInfo.cTotalNativeToken -= fund.qty;
                campaign.cFunded.amtFunded -= fund.qty; // deduct to match workflow (case: DELETED)
                // 10.8 do not deduct totalDonating
                // v129 deduct from presentDonating
                campaign.cFunded.presentDonating -= 1;
                // campaignDonatorNativeTokenFunded[simpleVars.uintVars[0]][fund.backer] -= fund.qty; // v129: complex version
                cIdTo.BackerNativeTokenFunded[fund.backer] -= fund.qty; // v129: after restructure it's simpler than above

                if (_earlyWithdraw) {
                    // campaignOptionNativeTokenFunded[simpleVars.uintVars[0]][fund.voteOption] -= fund.qty; // v129 complex version
                    cIdTo.OptionNativeTokenFunded[fund.voteOption] -= fund.qty; // v129: after restructure it's simpler than above
                }

                return true;
            }
        } else if (
            // keccak256(abi.encode(fund.tokenSymbol)) != keccak256(abi.encode(simpleVars.stringVars[0])) && fund.qty > 0
            //     && fund.refunded == false
            keccak256(abi.encode(fund.tokenSymbol)) != keccak256(abi.encode(simpleVars.stringVars[0])) && fund.qty > 0
                && fund.fundInfo.refunded == false && fund.fundInfo.timeLockStatus == TimeLockStatus.Approved
        ) {
            // fund.refunded = true;
            fund.fundInfo.refunded = true;
            fund.fundInfo.refundTimestamp = block.timestamp; // v129

            // do not reset funds[i].qty to 0 because set refunded to true is enough, need to keep it as a proof of donating even if campaign is failed

            // ERC20 token = ERC20(whitelistedTokens[fund.acceptedToken]); // depricated by v129
            ERC20 token = ERC20(fund.tokenAddr); // no need to check whitelist
            token.transfer(recipient, fund.qty);
            // fund.timestamp = block.timestamp;
            if (
                // keccak256(abi.encode(tokenAddrToPriority[whitelistedTokens[fund.acceptedToken]])) // depricated by v129
                // keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode("firstToken"))
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(FIRST_TOKEN))
            ) {
                contractFundedInfo.cTotalFirstToken -= fund.qty;
                campaign.cFunded.firstTokenFunded -= fund.qty; // deduct to match workflow (case: DELETED)
            } else if (
                // keccak256(abi.encode(tokenAddrToPriority[whitelistedTokens[fund.acceptedToken]])) // depricated by v129
                // keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode("secondToken"))
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(SECOND_TOKEN))
            ) {
                contractFundedInfo.cTotalSecondToken -= fund.qty;
                campaign.cFunded.secondTokenFunded -= fund.qty;
            } else if (
                // keccak256(abi.encode(tokenAddrToPriority[whitelistedTokens[fund.acceptedToken]])) // depricated by v129
                // keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode("thirdToken"))
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(THIRD_TOKEN))
            ) {
                contractFundedInfo.cTotalThirdToken -= fund.qty;
                campaign.cFunded.thirdTokenFunded -= fund.qty;
            }

            // 10.8 do not deduct totalDonating
            // v129 deduct from presentDonating
            campaign.cFunded.presentDonating -= 1;

            // campaignDonatorTokenFunded[simpleVars.uintVars[0]][fund.backer][fund.acceptedToken] -= fund.qty; // depricated by v129
            // campaignDonatorTokenFunded[simpleVars.uintVars[0]][fund.backer][fund.tokenAddr] -= fund.qty; // v129: complex version
            cIdTo.BackerTokenFunded[fund.backer][fund.tokenAddr] -= fund.qty; // v129: after restructure it's simpler than above

            // new in V007 11.0: deduct campaignOptionTokenFunded when _earlyWithdraw base on fund.voteOption (more correct vì lúc đóng vào được biến này ghi nhận)
            if (_earlyWithdraw) {
                // campaignOptionTokenFunded[simpleVars.uintVars[0]][fund.voteOption][fund.acceptedToken] -= fund.qty; // depricated by v129
                // campaignOptionTokenFunded[simpleVars.uintVars[0]][fund.voteOption][fund.tokenAddr] -= fund.qty; // v129: complex version
                cIdTo.OptionTokenFunded[fund.voteOption][fund.tokenAddr] -= fund.qty; // v129: after restructure it's simpler than above
            }
            return true;
        } else {
            return false; // bao gồm TH qty = 0 và là "ROTTEN"
        }
        return false;
    }

    /**
     * The refundCompleted function updates the campaign status after the refunds are processed.
     * If the reason is DELETED, the campaign status is set to DELETED.
     * If the reason is REVERTING, the campaign status is updated based on the remaining active backers.
     * @param _reason The reason for the refund (DELETED or REVERTING).
     */
    // function refundCompleted(string memory _reason, Campaign storage campaign, uint256 numberOfCampaignsExcludeRefunded)
    function refundCompleted(
        string memory _reason,
        Campaign storage campaign,
        ContractFunded storage contractFundedInfo
    ) internal returns (bool) {
        if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
            campaign.cStatus.campaignStatus = campaignStatusEnum.DELETED;
        } else if (keccak256(bytes(_reason)) == keccak256(bytes(REVERTING))) {
            /* v129: add new variable presentDonating in struct C_Funded which lead to
            - No need to use for loop from previous version (from v128) to calculate haveRemainBackers variable:

            C_Backer[] memory backersOfCampaign = GiveUpLib1.getBackersOfCampaign(campaign);
            bool haveRemainBackers = false;
            for (uint256 i = 0; i < backersOfCampaign.length; i++) {
                if (backersOfCampaign[i].refunded) {
                    continue;
                } else {
                    haveRemainBackers = true;
                    break;
                }
            }

            - replace haveRemainBackers by checking condition campaign.cFunded.presentDonating > 0
            */
            if (campaign.cFunded.presentDonating > 0) {
                if (campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN) {
                    campaign.cStatus.campaignStatus = campaignStatusEnum.REVERTING; // point when a backer withdrew and campaign still have remain backer(s)
                }
            } else {
                campaign.cStatus.campaignStatus = campaignStatusEnum.REVERTED; // point when all backers withdrew
                contractFundedInfo.totalFundedCampaign -= 1; // so update numberOfCampaignsExcludeRefund cause campaign's status is REVERTED
            }
        }
        return true;
    }
}
