// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../HATVault.sol";


contract HATVaultV2Mock is HATVault {
    function getVersion() external pure returns(string memory) {
        return "New version!";
    }
}
