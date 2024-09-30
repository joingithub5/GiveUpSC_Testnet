// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {GiveUp129} from "../../src/GiveUp_129.sol";
import "../../src/GlobalVariables_12x.sol";

library TestLib {
    function getLatestCampaign(GiveUp129 giveUp) internal view returns (CampaignNoBacker memory) {
        CampaignNoBacker[] memory campaignsNoBacker = giveUp.getCampaigns();
        CampaignNoBacker memory campaign = campaignsNoBacker[(giveUp.nextCId() - 1) - MAX_RULES];
        return campaign;
    }

    // Hàm chuyển đổi uint thành string
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            bstr[--k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }

    // Thêm các hàm helper khác ở đây
}
