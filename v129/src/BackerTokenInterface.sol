// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// External contract interface
interface BackerTokenInterface {
    /**
     * get Max Mint Percentage Base On Native Token this backer has contributed (such as ETH for Ethereum, Matic for Polygon etc.)
     */
    function getMaxMintPctBaseOnNativeToken(address _backerAddr, uint256 _campaignId) external view returns (uint256);

    // /**
    //  * get Max Mint Amount Base On White List Token this backer has contributed
    //  */
    // function getMaxMintPctBaseOnWLToken(address _backerAddr, uint256 _campaignId, address _whiteListToken)
    //     external
    //     view
    //     returns (uint256);
}
