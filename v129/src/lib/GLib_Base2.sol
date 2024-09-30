// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

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
     * @dev When voter vote for an option, if the option is already in his vote result mapping, it will not be added and returns false. If the option is not in the mapping, it will be added and returns true.
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
        mapping(uint256 => mapping(uint256 => address)) storage campaignVoter,
        Campaign storage campaign
    ) internal returns (bool) {
        bool optionVoted = false; // will turn true later on if _option is already voted
        uint256 totalVote = 0; // count how many distinct options have been voted by msg.sender
        for (uint256 i = 0; i < 5; i++) {
            if (
                keccak256(abi.encodePacked(campaignOptionsVoted[_id][msg.sender][i].tokenSymbol))
                    != keccak256(abi.encodePacked("")) // find i position that hasn't assigned voted token symbol
            ) {
                totalVote += 1; // if i position have assignment -> increase totalVote
            } else {
                break; // exit the for loop because campaignOptionsVoted save vote sequence, if there's no assignment, it means no vote has been made at that slot.
            }
        }

        for (uint256 i = 0; i < totalVote; i++) {
            if (campaignOptionsVoted[_id][msg.sender][i].option == _option) {
                optionVoted = true; // caller already voted that _option in previous votes
                return optionVoted; 
            }
        }

        if (!optionVoted) {
            campaignOptionsVoted[_id][msg.sender][totalVote] = VoteData(_option, _tokenSymbol);
            optionVoted = true; // new vote added at newest index
        }

        if (totalVote == 0 && optionVoted) {
            // add new voter when he/she first vote thus make item unique
            campaignVoter[_id][campaign.cFunded.voterCount] = msg.sender;
            campaign.cFunded.voterCount += 1;
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
                    campaign.cFunded.raisedFund.target = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("firstTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.raisedFund.firstTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("secondTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.raisedFund.secondTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("thirdTokenTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.raisedFund.thirdTokenTarget = _uintValues[i];
                    successUpdate += 1;
                } else if (
                    keccak256(abi.encode(_uintFields[i])) == keccak256(abi.encode("equivalentUSDTarget"))
                        && haveFundTarget > 0
                ) {
                    campaign.cFunded.raisedFund.equivalentUSDTarget = _uintValues[i];
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
     * NOTE EXCEPTION RULE: if haveFundTarget == 0, then ALL FUND TARGET WILL ALSO == 0 !!! WHATSOEVER
     * TODO: when haveFundTarget = 0,still deploy mechanism for raiser to set campaign fund target and deadline like normal campaign (for management purpose).
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
                    || (
                        campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN
                            && campaign.cFunded.raisedFund.totalDonating == 0
                    )
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
            campaign.cId.haveFundTarget = haveFundTarget;
        }

        if (haveFundTarget == 0) {
            campaign.cFunded.raisedFund.target = 0;
            campaign.cFunded.raisedFund.firstTokenTarget = 0;
            campaign.cFunded.raisedFund.secondTokenTarget = 0;
            campaign.cFunded.raisedFund.thirdTokenTarget = 0;
            campaign.cFunded.raisedFund.equivalentUSDTarget = 0;
        }

        if (pctForBackers != campaign.cId.pctForBackers) {
            campaign.cId.pctForBackers = pctForBackers;
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
     * - if haveFundTarget = 100, operator/ contract owner, raiser, alchemist can call payout. Raiser don't need Alchemist's address
     * - if 0 < haveFundTarget < 100, operator/ contract owner, raiser, alchemist can call payout. but raiser need Alchemist's address approved.
     * - if haveFundTarget = 0 -> see function performPayout for more detail
     */
    function payOutCampaign(
        Campaign storage campaign,
        MappingCampaignIdTo storage mappingCId, 
        PackedVars1 memory packedVars1,
        ContractFunded storage contractFundedInfo,
        address caller
    )
        internal
        returns (TokenTemplate1 resultToken, uint256 liquidity)
    {
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
        // require(
        //     keccak256(abi.encode(campaign.cStatus.acceptance)) != keccak256(abi.encode("FOL"))
        //         || msg.sender == contractOwner,
        //     "Code 'FOL': Campaign will convert all fund to Platform's token / NFT"
        // );
        /**
         * NOTE: NOT YET DEPLOY "FOL" CODE ABOVE ATM
         * if acceptance text code is "FOL" -> only operator/ contract owner can call this function (Note: not deploy atm)
         * if acceptance code != "FOL":
         */
        address alchemistAddr = mappingCId.alchemist.addr;
        require(
            (
                msg.sender == campaign.cId.raiser && campaign.cId.haveFundTarget > 0
                    && campaign.cId.haveFundTarget < 100 && mappingCId.alchemist.addr != address(0)
                    && mappingCId.alchemist.isApproved
            ) || (msg.sender == campaign.cId.raiser && campaign.cId.haveFundTarget == 100)
                || msg.sender == packedVars1.addressVars[0] || (msg.sender == alchemistAddr && alchemistAddr != address(0)),
            "Invalid Pay Out Right"
        );

        // avoid reentrancy attack
        require(
            !campaign.cFunded.paidOut.nativeTokenPaidOut && !campaign.cFunded.paidOut.firstTokenPaidOut
                && !campaign.cFunded.paidOut.secondTokenPaidOut && !campaign.cFunded.paidOut.thirdTokenPaidOut
                && !campaign.cFunded.paidOut.equivalentUSDPaidOut
        );

        return performPayout(campaign, mappingCId, packedVars1, contractFundedInfo, caller);
    }

    /**
     * createTokenContractForParticipantsSelfWithdraw()
     * Called by: performPayout()
     * create a token contract instance from TokenTemplate1 contract factory to record share for backers, raiser, alchemist. Also sending all raised funds to this newly created contract for backers, raiser, alchemist to withdraw LP token share later by themselves.
     * Reference 1: See rule to create liquidity pool in the code
     */
    function createTokenContractForParticipantsSelfWithdraw(
        Campaign storage campaign,
        MappingCampaignIdTo storage mappingCId,
        PackedVars1 memory packedVars1,
        address caller
    ) internal returns (TokenTemplate1 resultToken, uint256 liquidity) {
        require(bytes(mappingCId.resultToken.tokenSymbol).length != 0, "please set token symbol first");

        /* Note Reference 1: RULE to create liquidity pool or TRANSFER RAISED FUND (after tax) TO RESULT TOKEN CONTRACT depen on:
        * - if haveFundTarget = 100, don't add liquidity, transfer this deducted raised fund (include native token and whitelisted token) to result token contract and accredit to raiser, raiser will be able to withdraw their share later.
        * - if haveFundTarget < 100, also transfer all fund to result token contract similar to above, and add initial liquidity to <result token-native token> pool, all participants later can withdraw the LP share by themselves. Raised whitelisted token can be handled later by community address/ operator.
        */

        // update storage variable before passing to create campaign result token contract
        uint256 nativeTokenFundAfterTax = campaign.cFunded.raisedFund.amtFunded
            - GiveUpLib1.calculateTax(campaign.cFunded.raisedFund.amtFunded, packedVars1.uintVars[0]);
        if (!campaign.cFunded.raiserPaidOut.processed && !campaign.cFunded.alchemistPaidOut.processed) {
            if (caller == campaign.cId.raiser) {
                campaign.cFunded.raiserPaidOut.processed = true; // prevent reentrancy attack
                campaign.cFunded.raiserPaidOut.processedTime = block.timestamp;
            } else if (caller == mappingCId.alchemist.addr) {
                campaign.cFunded.alchemistPaidOut.processed = true; // prevent reentrancy attack
                campaign.cFunded.alchemistPaidOut.processedTime = block.timestamp;
            } else if (caller == packedVars1.addressVars[0]) {
                emit GiveUpLib1.GeneralMsg("function called by contract owner");
            } else {
                revert("function called by invalid address");
            }

            if (campaign.cId.haveFundTarget == 100) {
                if (campaign.cFunded.raisedFund.amtFunded > 0 && campaign.cFunded.paidOut.nativeTokenPaidOut) {
                    // only raiser can get raised fund as below parameters when haveFundTarget = 100
                    campaign.cFunded.raiserPaidOut.nativeTokenAmt = nativeTokenFundAfterTax;
                    campaign.cFunded.raiserPaidOut.firstTokenAmt = campaign.cFunded.raisedFund.firstTokenFunded;
                    campaign.cFunded.raiserPaidOut.secondTokenAmt = campaign.cFunded.raisedFund.secondTokenFunded;
                    campaign.cFunded.raiserPaidOut.thirdTokenAmt = campaign.cFunded.raisedFund.thirdTokenFunded;
                }
            }
        }

        // Create campaign result token contract and record raiser, alchemist share and inferrable backer share
        CampaignNoBacker memory campaignNoBacker = GiveUpLib1.getNoBackersCampaign(campaign);
        address payable resultTokenAddress = GiveUpLib1.createCampaignFinalToken(
            mappingCId.resultToken.tokenName,
            mappingCId.resultToken.tokenSymbol,
            campaignNoBacker,
            mappingCId,
            packedVars1.addressVars[0] // contract owner
        );
        require(resultTokenAddress != address(0), "create campaign result token failed");
        resultToken = TokenTemplate1(resultTokenAddress);
        // set whitelisted token addresses correspondingly with GiveUp contract at this moment
        for (uint256 i = 1; i < 4; i++) {
            if (packedVars1.addressVars[i] != address(0)) {
                resultToken.initWhiteListTokenAddr(i, packedVars1.addressVars[i]);
            }
        }

        // sending fund or create liquidity depend on haveFundTarget setting
        if (campaign.cId.haveFundTarget < 100) {
            liquidity = resultToken.addInitialLiquidityETH_1{value: nativeTokenFundAfterTax}(); // already check return value > 0 in the function
        } else if (campaign.cId.haveFundTarget == 100) {
            liquidity = 0;
            (bool success,) = payable(resultTokenAddress).call{value: nativeTokenFundAfterTax}("");
            require(success, "Transfer native token (credited to raiser) to result token contract failed");
        }
    }

    /**
     * performPayout()
     * Called by: payOutCampaign function
     * Will call: createTokenContractForParticipantsSelfWithdraw()
     * performPayout Rule:
     * - haveFundTarget = 100 (donation campaign), Raiser don't need to update Alchemist to pay out. Raiser will receive 100% of the fund while backer and alchemist (if any) will get 100% of campaign token
     * - haveFundTarget < 100, Raiser need to have Alchemist's address to pay out, ALL PARTIES RECEIVE CAMPAIGN TOKEN/ LP TOKEN SHARE, RAISED FUND (focus on native token) WILL BE USED TO CREATE LIQUIDITY POOL. There're 2 sub cases:
     * -- if haveFundTarget = 0, Raiser will receive nothing, Alchemist involved and get LP token = (100 - pctForBackers) * totalSupply / 100.
     * -- if haveFundTarget > 0, Raiser will receive LP token = ((100 - pctForBackers) * haveFundTarget / 100) * totalSupply / 100. Alchemist involved and get percentage = ((100 - pctForBackers) * (100 - haveFundTarget) / 100) * totalSupply / 100.
     * -- In this 2 sub cases, backer will receive LP token = pctForBackers * totalSupply / 100.
     * The performPayout function will also create campaign result token contract upon success. AND EVERY PARTICIPANT MUST TAKE THEIR OWN RESPONSIBILITY TO WITHDRAW THEIR TOKEN SHARE LATER.
     * Please see inline code comment for more detail
     */
    function performPayout(
        Campaign storage campaign,
        MappingCampaignIdTo storage mappingCId,
        PackedVars1 memory packedVars1,
        ContractFunded storage contractFundedInfo,
        address caller
    ) internal returns (TokenTemplate1 resultToken, uint256 liquidity) {
        // Firstly, check if there're any native token raised, if yes turn on paidOut flag of native token and start processing payout
        if (campaign.cFunded.raisedFund.amtFunded > 0) {
            campaign.cFunded.paidOut.nativeTokenPaidOut = true; // prevent reentrancy attack at outside caller function
        }

        // Secondly, call createTokenContractForParticipantsSelfWithdraw() to create token contract for participants self withdraw + create liquidity pool for everyone if haveFundTarget < 100 / transfer all raised native token (after tax) to result token contract if haveFundTarget = 100 for raiser to self-withdraw
        (resultToken, liquidity) = createTokenContractForParticipantsSelfWithdraw(
            campaign,
            mappingCId,
            packedVars1,
            caller
        ); // already check resultToken != address(0) inside this function

        // Thirdly, transfer all whitelisted token to result token contract after having result token contract address
        /**
         * BIG NOTE: PLATFORM DON'T GET FEE FROM WHITELISTED TOKEN CONTRIBUTIONS IF:
         * - business logic use native token as official mean of contribution and whitelisted token as DONATION/TIP. This is the intended design.
         * In the future if business logic change to use whitelisted token as official mean of contribution then they'll be taxed like native token.
         */
        if (campaign.cFunded.raisedFund.firstTokenFunded > 0) {
            ERC20 firstPriorityToken = ERC20(packedVars1.addressVars[1]);
            campaign.cFunded.paidOut.firstTokenPaidOut = true; 

            firstPriorityToken.approve(payable(address(resultToken)), campaign.cFunded.raisedFund.firstTokenFunded);
            firstPriorityToken.transfer(payable(address(resultToken)), campaign.cFunded.raisedFund.firstTokenFunded);
        }

        if (campaign.cFunded.raisedFund.secondTokenFunded > 0) {
            ERC20 secondPrioritytoken = ERC20(packedVars1.addressVars[2]);
            campaign.cFunded.paidOut.secondTokenPaidOut = true;

            secondPrioritytoken.approve(payable(address(resultToken)), campaign.cFunded.raisedFund.secondTokenFunded);
            secondPrioritytoken.transfer(payable(address(resultToken)), campaign.cFunded.raisedFund.secondTokenFunded);
        }

        if (campaign.cFunded.raisedFund.thirdTokenFunded > 0) {
            ERC20 thirdPriorityToken = ERC20(packedVars1.addressVars[3]);
            campaign.cFunded.paidOut.thirdTokenPaidOut = true; 

            thirdPriorityToken.approve(payable(address(resultToken)), campaign.cFunded.raisedFund.thirdTokenFunded);
            thirdPriorityToken.transfer(payable(address(resultToken)), campaign.cFunded.raisedFund.thirdTokenFunded);
        }

        // finally update related storage variable
        campaign.cStatus.campaignStatus = campaignStatusEnum.PAIDOUT;
        mappingCId.resultToken.tokenIndex = contractFundedInfo.totalCampaignToken;
        mappingCId.resultToken.tokenAddr = address(resultToken);
        mappingCId.resultToken.tokenSymbol = resultToken.symbol();
        mappingCId.resultToken.tokenName = resultToken.name();
    }

    /* Note: only ultilize some beginning field of input array, e.g _content array only use 4 first elements
    * NOTE EXCEPTION RULE: if haveFundTarget == 0, then ALL FUND TARGET WILL ALSO == 0 !!! WHATSOEVER
    * TODO: when haveFundTarget = 0,still deploy mechanism for raiser to set campaign fund target and deadline like normal campaign (for management purpose).
    * TODO BIG TODO QUESTION: handle case when raiser address is contract and can not receive native token (e.g: WETH)
    */
    function createCampaign(
        uint256 _haveFundTarget, // percentage for raiser, 0% = non profit/long term, 100=100% = tip/donation/no return ect
        uint256 _pctForBackers, // Note VIP parameter: raiser & alchemist only get the remain after deducting _pctForBackers, e.g: _pctForBackers = 100, raiser & alchemist will get 0% (NOTHING) of fund raised; _pctForBackers = 0, raiser & alchemist will get 100% of fund raised; _pctForBackers = 50, raiser & alchemist will get 50% of fund raised etc.
        string[] memory _content, // 0.campaignType, 1.title, 2.description, 3.image
        string[] memory _options, // can be blank for basic campaign purpose, max 4 options by struct C_Options
        uint256[] memory _timeline, // startAt, deadline
        uint256[] memory _group, // new, read guidance
        uint256[] memory _deList, // new, read guidance
        uint256[] memory _fund, // 0.target, 1.firstTokenTarget, 2.secondTokenTarget, 3.thirdTokenTarget, 4.equivalentUSDTargetß
        uint256 _id, // store settingId from main contract
        Campaign storage campaign
    ) public returns (bool) {
        require( //  _timeline[0] is _startAt param ...
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
            haveFundTarget: _haveFundTarget,
            pctForBackers: _pctForBackers
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
            campaign.cFunded.raisedFund.target = _fund[0];
            campaign.cFunded.raisedFund.firstTokenTarget = _fund[1];
            campaign.cFunded.raisedFund.secondTokenTarget = _fund[2];
            campaign.cFunded.raisedFund.thirdTokenTarget = _fund[3];
            campaign.cFunded.raisedFund.equivalentUSDTarget = _fund[4];
        }

        campaign.cOptions =
            C_Options({option1: _options[0], option2: _options[1], option3: _options[2], option4: _options[3]});

        campaign.cStatus.campaignStatus = campaignStatusEnum.OPEN;

        return true;
    }

    function signAcceptance(Campaign storage campaign, address payable alchemistAddr, string memory _acceptance)
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
            "signer is not the one who has higher share of payout"
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
        mapping(uint256 => mapping(uint256 => address)) storage campaignVoter,
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
                // note: new code that replace voterAddr and may save some gas
                uint256 length = campaign.cFunded.voterCount;
                for (uint256 i = 0; i < length; i++) {
                    if (campaignVoter[_id][i] == msg.sender) {
                        campaignVoter[_id][i] = campaignVoter[_id][length - 1];
                        delete campaignVoter[_id][length - 1];
                        break;
                    }
                }
                campaign.cFunded.voterCount -= 1;

                // // old code of voterAddr to be replaced
                // (, uint256 index) =
                //     GiveUpLib1.findAddressIndex(msg.sender, new address[](0), campaign.cFunded.voterAddr);

                // /* NEED TO TEST DoS when using findAddressIndex function because it use for loop to find index
                // */
                // if (index < campaign.cFunded.voterAddr.length - 1) {
                //     // Move the last element to the index to be removed
                //     campaign.cFunded.voterAddr[index] =
                //         campaign.cFunded.voterAddr[campaign.cFunded.voterAddr.length - 1];
                //     // Remove the last element
                //     campaign.cFunded.voterAddr.pop();
                // } else if (index == campaign.cFunded.voterAddr.length - 1) {
                //     campaign.cFunded.voterAddr.pop();
                // }
            }
        }

        return deleteSuccess;
    }

    /* depend on campaign's status and other conditions that:
    - raiser can DELETE the campaign and REFUND all backer with `RAISER_DELETE_ALL_CODE`
    - everyone can withdraw A SPECIFIC vote option.
    - everyone can withdraw ALL her vote options with `BACKER_WITHDRAW_ALL_CODE`
    */
    function requestRefund(
        PackedVars1 memory packedVars1,
        Campaign storage campaign,
        mapping(uint256 => mapping(address => mapping(uint256 => VoteData))) storage campaignOptionsVoted,
        ContractFunded storage contractFundedInfo,
        MappingCampaignIdTo storage cIdTo,
        mapping(address => string) storage tokenAddrToPriority,
        mapping(uint256 => mapping(uint256 => address)) storage campaignVoter
    )
        internal
        returns (
            string memory reportString,
            bool isTimelockForRefund, // (not yet implement)
            TimeLockStatus returnTimeLockStatus // (not yet implement)
        )
    {
        // Note: packedVars1.addressVars[0] contain platform/ contract owner address
        // that temporary allowed to delete on going campaign so I add it here
        // there's another checking in checkDeletableCampaign() afterward to support the work flow.
        require(
            (
                msg.sender == packedVars1.addressVars[0]
                    || campaign.cStatus.campaignStatus == campaignStatusEnum.REVERTING
                    || (
                        (
                            campaign.cStatus.campaignStatus == campaignStatusEnum.OPEN
                                || campaign.cStatus.campaignStatus == campaignStatusEnum.APPROVED_UNLIMITED
                        )
                            && (
                                campaign.cInfo.deadline < block.timestamp || block.timestamp < campaign.cInfo.startAt
                                    || packedVars1.earlyWithdraw
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

        uint256 totalNumber; // number of contributions to be refunded
        // First performRefund occur when backer withdraw his fund when campaign failed to meet target
        if (packedVars1.uintVars[1] != RAISER_DELETE_ALL_CODE) {
            if (!packedVars1.earlyWithdraw) {
                // Withdrawal when campaign failed (mean it's a natural withdraw, not early withdraw -> we'll not delete vote history)
                (totalNumber,,) =
                    performRefund(packedVars1, campaign, REVERTING, contractFundedInfo, cIdTo, tokenAddrToPriority);
            } else {
                // Early Withdrawal -> need to clear vote history (only clear them in this situation)
                (totalNumber, isTimelockForRefund, returnTimeLockStatus) =
                    performRefund(packedVars1, campaign, EARLY_WITHDRAW, contractFundedInfo, cIdTo, tokenAddrToPriority);

                /////////////// v129 - 240807 ////////////////////////
                /**
                 * Note: below if code is not yet implement but reserve for future reference.
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

                // handle EARLY_WITHDRAW of vote option (V006 10.9)
                if (packedVars1.uintVars[1] == BACKER_WITHDRAW_ALL_CODE) {
                    for (uint256 i = 0; i < 5; i++) {
                        // campaignOptionsVoted[packedVars1.uintVars[0]][msg.sender][i] = VoteData(0,"");  // reset cách 1 ok
                        delete campaignOptionsVoted[packedVars1.uintVars[0]][
                            msg.sender
                        ][i]; // reset cách 2 ok
                    }

                    // note: new code that replace voterAddr and may save some gas
                    // TODO: below for loop need to check for gas optimization
                    uint256 length = campaign.cFunded.voterCount;
                    uint256 _id = packedVars1.uintVars[0];
                    for (uint256 i = 0; i < length; i++) {
                        if (campaignVoter[_id][i] == msg.sender) {
                            campaignVoter[_id][i] = campaignVoter[_id][length - 1];
                            delete campaignVoter[_id][length - 1];
                            break;
                        }
                    }
                    campaign.cFunded.voterCount -= 1;

                    reportString = "Removed ALL vote options";
                } else {
                    if (
                        removeOptionsVoted(
                            packedVars1.uintVars[0],
                            packedVars1.uintVars[1],
                            campaignOptionsVoted,
                            campaignVoter,
                            campaign
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
            if (GiveUpLib1.checkDeletableCampaign(campaign, packedVars1.addressVars[0])) {
                (totalNumber,,) =
                    performRefund(packedVars1, campaign, DELETED, contractFundedInfo, cIdTo, tokenAddrToPriority);
            }
        }

        if (totalNumber > 0) {
            reportString = string(abi.encodePacked("Processed ", toString(totalNumber), " donation(s)"));
            emit GiveUpLib1.GeneralMsg(
                string(
                    abi.encodePacked(
                        "SUCCESSFULLY REFUND cId ",
                        toString(packedVars1.uintVars[0]),
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
     * If the reason is REVERTING (called by a backer), refunds are performed for that backer only after campaign expired with failure.
     * If the reason is EARLY_WITHDRAW (called by a backer), refunds are performed for that backer even when campaign is going on (but not yet success).
     * It simply loop through ALL backer, check refund condition (such as: all or specific option) and perform refund by calling singleRefund.
     * After the refunds are processed, the refundCompleted function is called to update the campaign status.
     * @param _reason The reason for the refund (must be 3 constants: EARLY_WITHDRAW, DELETED or REVERTING).
     * @return totalNumber : The number of contributions to be refunded.
     * @return isTimelockForRefund : true mean backer enter refund process, it'll change some stages in backer's fundInfo variable such as: TimeLockStatus.Registered, TimeLockStatus.Waiting, ... to prevent front running (not yet implement)
     * @return returnTimeLockStatus : The status of the refund process. (not yet implement)
     */
    function performRefund(
        PackedVars1 memory packedVars1,
        Campaign storage campaign,
        string memory _reason,
        ContractFunded storage contractFundedInfo,
        MappingCampaignIdTo storage cIdTo,
        mapping(address => string) storage tokenAddrToPriority
    ) internal returns (uint256 totalNumber, bool isTimelockForRefund, TimeLockStatus returnTimeLockStatus) {

        // if reason is EARLY_WITHDRAW, we will not call refundCompleted function and exit performRefund
        if (keccak256(bytes(_reason)) == keccak256(bytes(EARLY_WITHDRAW))) {
            // (delete old code about timelock)

            for (uint256 i = 0; i < campaign.cFunded.raisedFund.totalDonating; i++) {
                if (campaign.cBacker[i].backer == msg.sender && !campaign.cBacker[i].fundInfo.refunded) {
                    // refund base on backer's vote option code (uintVars[1])
                    if (packedVars1.uintVars[1] == BACKER_WITHDRAW_ALL_CODE) {
                        if (
                            singleRefund(packedVars1, i, true, campaign, contractFundedInfo, cIdTo, tokenAddrToPriority)
                        ) {
                            totalNumber += 1;
                        }
                    } else if (0 <= packedVars1.uintVars[1] && packedVars1.uintVars[1] <= 4) {
                        // code 0-4: backer want to withdraw 1 SPECIFIC vote option => have to find if this option exists, if yes => increase totalNumber variable
                        if (campaign.cBacker[i].voteOption == packedVars1.uintVars[1]) {
                            if (
                                singleRefund(
                                    packedVars1, i, true, campaign, contractFundedInfo, cIdTo, tokenAddrToPriority
                                )
                            ) {
                                totalNumber += 1;
                            }
                        }
                    }
                }
            }
            return (totalNumber, false, returnTimeLockStatus); // don't call refundCompleted because EARLY_WITHDRAW is different.
        }

        // if reason is DELETED or REVERTING will proceed then call refundCompleted function before exit performRefund
        if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
            // refund all backers
            for (uint256 i = 0; i < campaign.cFunded.raisedFund.totalDonating; i++) {
                if (singleRefund(packedVars1, i, false, campaign, contractFundedInfo, cIdTo, tokenAddrToPriority)) {
                    totalNumber += 1;
                }
            }
        } else if (keccak256(bytes(_reason)) == keccak256(bytes(REVERTING))) {
            /**
             * Question: OPTIMIZE REVERTING by combining all donations of a backer if needed ?
             * Todo: test DoS & gas saving when campaign.cFunded.totalDonating is big enough???
             */
            // refund for msg.sender only
            for (uint256 i = 0; i < campaign.cFunded.raisedFund.totalDonating; i++) {
                if (campaign.cBacker[i].backer == msg.sender) {
                    if (singleRefund(packedVars1, i, false, campaign, contractFundedInfo, cIdTo, tokenAddrToPriority)) {
                        totalNumber += 1;
                    }
                }
            }
        }

        // call refundCompleted function depend on totalNumber variable, this part handle status and totalFundedCampaign.
        if (totalNumber > 0) {
            // i.e there're refunds ... -> update campaign status
            refundCompleted(_reason, campaign, contractFundedInfo);
            if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
                contractFundedInfo.totalFundedCampaign -= 1; 
            }
        } else {
            // if there're no refund...
            refundCompleted(_reason, campaign, contractFundedInfo);
        }
        return (totalNumber, false, returnTimeLockStatus);
    }

    // refund
    // TODO: test require(success, "Refund failed"); etc. and think about try catch handle
    function singleRefund(
        PackedVars1 memory packedVars1,
        uint256 i, // index of funds
        bool _earlyWithdraw,
        Campaign storage campaign,
        ContractFunded storage contractFundedInfo,
        MappingCampaignIdTo storage cIdTo,
        mapping(address => string) storage tokenAddrToPriority
    ) internal returns (bool) {
        C_Backer storage fund = campaign.cBacker[i];
        address payable recipient = fund.backer;

        /* NOTICE: AT TESTNET WILL TURN OF INTENDED FEATURE USING penaltyContract to hold withdrawal fund
        */
        // if (_earlyWithdraw) {
        //     recipient = payable(packedVars1.addressVars[1]); // penaltyContract
        // }

        if (
            // check refund for native token (combine check with address(0))
            keccak256(abi.encode(fund.tokenSymbol)) == keccak256(abi.encode(packedVars1.stringVars[0])) && fund.qty > 0
                && fund.fundInfo.refunded == false && fund.tokenAddr == address(0)
        ) {
            // && fund.fundInfo.timeLockStatus == TimeLockStatus.Approved // not yet deploy timelock atm
            fund.fundInfo.refunded = true; // avoid reentrancy attack
            // not reset funds[i].qty to 0 because set refunded to true is enough, keep funds[i].qty as a proof of donating even if campaign is failed and backer withdrew.
            fund.fundInfo.refundTimestamp = block.timestamp; 

            (bool success,) = payable(recipient).call{value: fund.qty}("");
            if (success) {
                contractFundedInfo.cTotalNativeToken -= fund.qty;
                campaign.cFunded.raisedFund.amtFunded -= fund.qty; // deduct to match workflow (case: DELETED)
                campaign.cFunded.raisedFund.presentDonating -= 1;
                cIdTo.BackerNativeTokenFunded[fund.backer] -= fund.qty; 

                if (_earlyWithdraw) {
                    cIdTo.OptionNativeTokenFunded[fund.voteOption] -= fund.qty; 
                }

                return true;
            }
        } else if (
            // check refund for ERC20 token
            keccak256(abi.encode(fund.tokenSymbol)) != keccak256(abi.encode(packedVars1.stringVars[0])) && fund.qty > 0
                && fund.fundInfo.refunded == false
        ) {
            // && fund.fundInfo.timeLockStatus == TimeLockStatus.Approved // not yet deploy timelock atm
            fund.fundInfo.refunded = true;
            fund.fundInfo.refundTimestamp = block.timestamp; 

            ERC20 token = ERC20(fund.tokenAddr); // no need to check whitelist
            token.transfer(recipient, fund.qty);
            if (
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(FIRST_TOKEN))
            ) {
                contractFundedInfo.cTotalFirstToken -= fund.qty;
                campaign.cFunded.raisedFund.firstTokenFunded -= fund.qty; // deduct to match workflow (case: DELETED)
            } else if (
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(SECOND_TOKEN))
            ) {
                contractFundedInfo.cTotalSecondToken -= fund.qty;
                campaign.cFunded.raisedFund.secondTokenFunded -= fund.qty;
            } else if (
                keccak256(abi.encode(tokenAddrToPriority[fund.tokenAddr])) == keccak256(abi.encode(THIRD_TOKEN))
            ) {
                contractFundedInfo.cTotalThirdToken -= fund.qty;
                campaign.cFunded.raisedFund.thirdTokenFunded -= fund.qty;
            }

            // do not deduct totalDonating, deduct presentDonating instead
            campaign.cFunded.raisedFund.presentDonating -= 1;

            cIdTo.BackerTokenFunded[fund.backer][fund.tokenAddr] -= fund.qty; 

            if (_earlyWithdraw) {
                cIdTo.OptionTokenFunded[fund.voteOption][fund.tokenAddr] -= fund.qty; 
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
    function refundCompleted(
        string memory _reason,
        Campaign storage campaign,
        ContractFunded storage contractFundedInfo
    ) internal returns (bool) {
        if (keccak256(bytes(_reason)) == keccak256(bytes(DELETED))) {
            campaign.cStatus.campaignStatus = campaignStatusEnum.DELETED;
        } else if (keccak256(bytes(_reason)) == keccak256(bytes(REVERTING))) {

            if (campaign.cFunded.raisedFund.presentDonating > 0) {
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
