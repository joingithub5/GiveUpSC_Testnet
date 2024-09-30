// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {C_Backer, FundInfo, TimeLockStatus} from "./GlobalVariables_12x.sol";

// External contract interface
interface BackerTokenInterface {
    /**
     * get the contribution percentage and amount (in native token, such as ETH for Ethereum, Matic for Polygon etc.) of a backer in a specific campaign
     * percentage is normal percentage (e.g 10% = 10) to avoid precision loss.
     */
    function getBackerNativeTokenContribution(address _backerAddr, uint256 _campaignId)
        external
        view
        returns (uint256, uint256);

    /**
     * get backers of a campaign. By default, it ONLY return present backers (i.e. not includes refunded backers, _includeRefunded == false by default).
     */
    function getBackersOfCampaign(uint256 _campaignId, bool _includeRefunded)
        external
        view
        returns (C_Backer[] memory);

    // /**
    //  * get the contribution percentage (in other token ...
    //  */
}
