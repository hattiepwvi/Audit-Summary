/**
    SenUSD
    
    Website: https://senecaprotocol.com/
    Twitter: twitter.com/SenecaUSD
    Telegram: t.me/seneca_protocol
    Linktree: https://linktr.ee/senecaprotocol
**/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./token/oft/v2/fee/OFTWithFee.sol";

/**
 * @title SenUSD
 * @author blockchainPhysicst
 * @notice SenUSD inherits from OFT, which enables senUSD to create a Layer Zero bridge to other chains for the senUSD token in the future
 */

// Interface for interacting with the BentoBox protocol.
interface IBentoBoxV1 {
    /**
     * @dev Emitted when a deposit is made to the BentoBox.
     */
    event LogDeposit(address indexed token, address indexed from, address indexed to, uint256 amount, uint256 share);
        
    /**
     * @dev Handles deposits to the BentoBox, returning the amount and share of the deposit.
     * @param token_ The token to deposit.
     * @param from The address to transfer the tokens from.
     * @param to The address on whose behalf to deposit.
     * @param amount The amount of tokens to deposit.
     * @param share The share of the deposit.
     * @return amountOut The actual amount deposited.
     * @return shareOut The share of the deposited amount.
     */
    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
}

/**
 * @dev Extension of {OFTWithFee} that adds minting and burning functionality for a stablecoin.
 */
contract SenecaUSD is OFTWithFee {
    /// @notice Custom error for attempting to perform an action with an amount of zero.
    error SenecaUSD__AmountMustBeMoreThanZero();
    /// @notice Custom error for when a user tries to burn more tokens than they have in their balance.
    error SenecaUSD__BurnAmountExceedsBalance();
    /// @notice Custom error for when user attempts an action to zero address
    error SenecaUSD__NotZeroAddress();
    
    /// @dev Administrative address but ownership will be transferred to multisig
    address public admin;

    /**
     * @dev Struct to keep track of the minting state.
     */
    struct Minting {
        uint128 time;  // Timestamp of the last minting.
        uint128 amount; // Amount minted at last minting.
    }

    // Record of the last minting action.
    Minting public lastMint;
    // Constants governing the minting mechanism.
    uint256 private constant MINTING_PERIOD = 24 hours;
    uint256 private constant MINTING_INCREASE = 15000;
    uint256 private constant MINTING_PRECISION = 1e5;
    uint256 public supply;

    /**
     * @dev Sets up the token with an endpoint for Layer Zero functionalities.
     * @param _lzEndpoint The Layer Zero endpoint address.
     */
    constructor(address _lzEndpoint) OFTWithFee("SenecaUSD", "SenUSD", 18, _lzEndpoint) {
        admin = msg.sender;
        supply = totalSupply();
    }

    /**
     * @dev Burns `_amount` tokens from the caller's account.
     * @param _amount The quantity of tokens to burn.
     */
    function burn(uint256 _amount) public onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert SenecaUSD__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert SenecaUSD__BurnAmountExceedsBalance();
        }
        _burn(msg.sender, _amount);
    }

    /**
     * @dev Mints `_amount` tokens and assigns them to `_to`, increasing the total supply.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(_to != address(0), "SENUSD: no mint to zero address");

        uint256 totalMintedAmount = uint256(lastMint.time < block.timestamp - MINTING_PERIOD ? 0 : lastMint.amount) + _amount;
        uint256 tempSupply = totalSupply() * MINTING_INCREASE / MINTING_PRECISION;
        require(totalSupply() == 0 || tempSupply >= totalMintedAmount);

        lastMint.time = uint128(block.timestamp);
        lastMint.amount = uint128(totalMintedAmount);

        supply = totalSupply() + _amount;
        _mint(_to, _amount);
    }

    /**
     * @dev Mints tokens and then deposits them into a BentoBox for
     * */
    function mintToBentoBox(
        address clone,
        uint256 amount,
        IBentoBoxV1 bentoBox
    ) public onlyOwner {
        mint(address(bentoBox), amount);
        bentoBox.deposit(IERC20(address(this)), address(bentoBox), clone, amount, 0);
    }
}
