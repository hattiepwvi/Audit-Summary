// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 总结：ERC1155标准的NFT合约，可以用于创建、铸造和管理多种类型的NFT。它还允许所有者停止特定tokenId的铸造
 * @author 1）继承： ERC1155Supply 合约和 Ownable 合约。
 * @notice 2）功能： mint, stopmint 批量铸造和批量停止铸造 NFT; 元数据URI：用于获取给定tokenId的元数据URI。
 */

contract HATHackersNFT is ERC1155Supply, Ownable {
    error MintArrayLengthMismatch();
    error TokenDoesNotExist();
    error MintingAlreadyStopped();
    error MintingOfTokenStopped();

    event MintingStopped(uint256 indexed _tokenId);

    mapping(uint256 => string) public uris;
    mapping(uint256 => bool) public mintingStopped;

    constructor(address _hatsGovernance) ERC1155("") {
        _transferOwnership(_hatsGovernance);
    }

    function mint(
        address _recipient,
        string calldata _ipfsHash,
        uint256 _amount
    ) public onlyOwner {
        uint256 tokenId = getTokenId(_ipfsHash);

        if (bytes(uris[tokenId]).length == 0) {
            uris[tokenId] = _ipfsHash;
        }

        if (mintingStopped[tokenId]) {
            revert MintingOfTokenStopped();
        }
        _mint(_recipient, tokenId, _amount, "");
    }

    function stopMint(uint256 _tokenId) public onlyOwner {
        if (mintingStopped[_tokenId]) {
            revert MintingAlreadyStopped();
        }
        mintingStopped[_tokenId] = true;
        emit MintingStopped(_tokenId);
    }

    function mintMultiple(
        address[] calldata _recipients,
        string[] calldata _ipfsHashes,
        uint256[] calldata _amounts
    ) external onlyOwner {
        if (
            _ipfsHashes.length != _recipients.length ||
            _ipfsHashes.length != _amounts.length
        ) {
            revert MintArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _ipfsHashes.length; ) {
            mint(_recipients[i], _ipfsHashes[i], _amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function stopMintMultiple(uint256[] calldata _tokenIds) external onlyOwner {
        for (uint256 i = 0; i < _tokenIds.length; ) {
            stopMint(_tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getTokenId(
        string calldata _ipfsHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_ipfsHash)));
    }

    function uri(
        uint256 _tokenId
    ) public view override returns (string memory) {
        return uris[_tokenId];
    }
}
