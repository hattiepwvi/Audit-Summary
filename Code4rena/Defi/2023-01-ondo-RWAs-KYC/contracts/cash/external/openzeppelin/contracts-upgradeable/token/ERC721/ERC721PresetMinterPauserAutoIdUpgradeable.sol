// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol)

pragma solidity ^0.8.0;

import "contracts/cash/external/openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/token/ERC721/ERC721EnumerableUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/token/ERC721/ERC721BurnableUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/token/ERC721/ERC721PausableUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/utils/CounterUpgradeable.sol";
import "contracts/cash/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 *
 * _Deprecated in favor of https://wizard.openzeppelin.com/[Contracts Wizard]._
 */
contract ERC721PresetMinterPauserAutoIdUpgradeable is
  Initializable,
  ContextUpgradeable,
  AccessControlEnumerableUpgradeable,
  ERC721EnumerableUpgradeable,
  ERC721BurnableUpgradeable,
  ERC721PausableUpgradeable
{
  function initialize(
    string memory name,
    string memory symbol,
    string memory baseTokenURI
  ) public virtual initializer {
    __ERC721PresetMinterPauserAutoId_init(name, symbol, baseTokenURI);
  }

  using CountersUpgradeable for CountersUpgradeable.Counter;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  CountersUpgradeable.Counter private _tokenIdTracker;

  string private _baseTokenURI;

  /**
   * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
   * account that deploys the contract.
   *
   * Token URIs will be autogenerated based on `baseURI` and their token IDs.
   * See {ERC721-tokenURI}.
   */
  function __ERC721PresetMinterPauserAutoId_init(
    string memory name,
    string memory symbol,
    string memory baseTokenURI
  ) internal onlyInitializing {
    __ERC721_init_unchained(name, symbol);
    __Pausable_init_unchained();
    __ERC721PresetMinterPauserAutoId_init_unchained(name, symbol, baseTokenURI);
  }

  function __ERC721PresetMinterPauserAutoId_init_unchained(
    string memory,
    string memory,
    string memory baseTokenURI
  ) internal onlyInitializing {
    _baseTokenURI = baseTokenURI;

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

    _setupRole(MINTER_ROLE, _msgSender());
    _setupRole(PAUSER_ROLE, _msgSender());
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  /**
   * @dev Creates a new token for `to`. Its token ID will be automatically
   * assigned (and available on the emitted {IERC721-Transfer} event), and the token
   * URI autogenerated based on the base URI passed at construction.
   *
   * See {ERC721-_mint}.
   *
   * Requirements:
   *
   * - the caller must have the `MINTER_ROLE`.
   */
  function mint(address to) public virtual {
    require(
      hasRole(MINTER_ROLE, _msgSender()),
      "ERC721PresetMinterPauserAutoId: must have minter role to mint"
    );

    // We cannot just use balanceOf to create the new tokenId because tokens
    // can be burned (destroyed), so we need a separate counter.
    _mint(to, _tokenIdTracker.current());
    _tokenIdTracker.increment();
  }

  /**
   * @dev Pauses all token transfers.
   *
   * See {ERC721Pausable} and {Pausable-_pause}.
   *
   * Requirements:
   *
   * - the caller must have the `PAUSER_ROLE`.
   */
  function pause() public virtual {
    require(
      hasRole(PAUSER_ROLE, _msgSender()),
      "ERC721PresetMinterPauserAutoId: must have pauser role to pause"
    );
    _pause();
  }

  /**
   * @dev Unpauses all token transfers.
   *
   * See {ERC721Pausable} and {Pausable-_unpause}.
   *
   * Requirements:
   *
   * - the caller must have the `PAUSER_ROLE`.
   */
  function unpause() public virtual {
    require(
      hasRole(PAUSER_ROLE, _msgSender()),
      "ERC721PresetMinterPauserAutoId: must have pauser role to unpause"
    );
    _unpause();
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  )
    internal
    virtual
    override(
      ERC721Upgradeable,
      ERC721EnumerableUpgradeable,
      ERC721PausableUpgradeable
    )
  {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(
      AccessControlEnumerableUpgradeable,
      ERC721Upgradeable,
      ERC721EnumerableUpgradeable
    )
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[48] private __gap;
}
