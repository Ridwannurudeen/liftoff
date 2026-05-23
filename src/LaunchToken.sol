// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal fixed-supply launch token. Entire supply is minted to `recipient` at creation.
contract LaunchToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 supply, address recipient)
        ERC20(name_, symbol_)
    {
        _mint(recipient, supply);
    }
}
