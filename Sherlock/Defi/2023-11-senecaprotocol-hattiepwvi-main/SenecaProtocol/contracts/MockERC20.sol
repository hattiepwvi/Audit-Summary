// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./MockERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @dev Mock contract for ERC20 token, for testing purposes.
 * @notice Allows for minting, burning, and internal transfers for test accounts.
 */
contract ERC20Mock is ERC20 {
    /**
     * @dev Creates a new mock ERC20 token and mints initial balance to a specified account.
     * @param name The name of the mock ERC20 token.
     * @param symbol The symbol of the mock ERC20 token.
     * @param initialAccount The account that will receive the initial token supply.
     * @param initialBalance The amount of tokens to mint initially.
     */
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    /**
     * @dev Public function to mint tokens to a specified account.
     * @param account The account in which to mint the tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /**
     * @dev Public function to burn tokens from a specified account.
     * @param account The account from which to burn the tokens.
     * @param amount The number of tokens to burn.
     */
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    /**
     * @dev Public function to perform internal transfers, can only be called by the contract.
     * @param from The account from which to transfer tokens.
     * @param to The account to which to transfer tokens.
     * @param value The amount of tokens to transfer.
     */
    function transferInternal(
        address from,
        address to,
        uint256 value
    ) public {
        _transfer(from, to, value);
    }

    /**
     * @dev Public function to perform internal approvals, can only be called by the contract.
     * @param owner The owner of the tokens to approve.
     * @param spender The spender to approve for token withdrawal.
     * @param value The number of tokens to approve.
     */
    function approveInternal(
        address owner,
        address spender,
        uint256 value
    ) public {
        _approve(owner, spender, value);
    }
}