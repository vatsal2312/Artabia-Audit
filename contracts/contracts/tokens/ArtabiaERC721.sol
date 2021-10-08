// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../GloballyApprovedOperatorsERC721.sol";
import "../ERC721Marketplace/ERC721OrderMarketplace.sol";
import "../ERC721Marketplace/ERC721ListingMarketplace.sol";
import "../ERC721Marketplace/ERC721AuctionMarketplace.sol";
import "../Address.sol";
import "../Strings.sol";
import "../IERC2981.sol";

contract ArtabiaERC721 is GloballyApprovedOperatorsERC721, IERC2981 {
  using Strings for uint256;
  using Address for address;

  ERC721OrderMarketplace orderMarketplace;
  ERC721ListingMarketplace listingMarketplace;
  ERC721AuctionMarketplace auctionMarketplace;

  constructor(address[] memory marketplaceAddresses) GloballyApprovedOperatorsERC721("Artabia", "ARB", marketplaceAddresses) {
    orderMarketplace = ERC721OrderMarketplace(marketplaceAddresses[0]);
    listingMarketplace = ERC721ListingMarketplace(marketplaceAddresses[1]);
    auctionMarketplace = ERC721AuctionMarketplace(marketplaceAddresses[2]);
  }

  modifier onlyNonContracts() virtual {
    require(!msg.sender.isContract(), "only non contracts");
    _;
  }

  mapping(uint256 => address) royaltyReceiver;
  mapping(uint256 => uint8) royaltyPercentage;

  function mint(uint256 _tokenId, uint8 _royaltyPercentage) public onlyNonContracts {
    require(_royaltyPercentage <= 50, "royalty percentage too big");

    _mint(tx.origin, _tokenId);

    royaltyReceiver[_tokenId] = tx.origin;
    royaltyPercentage[_tokenId] = _royaltyPercentage;
  }

  function mintAndCreateOrder(uint256 _tokenId, uint8 _royaltyPercentage, uint256 _price) external onlyNonContracts {
    mint(_tokenId, _royaltyPercentage);
    orderMarketplace.createOrder(address(this), _tokenId, _price);
  }

  function mintAndCreateListing(uint256 _tokenId, uint8 _royaltyPercentage) external onlyNonContracts {
    mint(_tokenId, _royaltyPercentage);
    listingMarketplace.createListing(address(this), _tokenId);
  }

  function mintAndCreateAuction(uint256 _tokenId, uint8 _royaltyPercentage, uint128 _endsAt) external onlyNonContracts {
    mint(_tokenId, _royaltyPercentage);
    auctionMarketplace.createAuction(address(this), _tokenId, _endsAt);
  }

  function _baseURI() internal pure override returns (string memory) {
    return  "http://localhost:3000/metadata/";
  }

  function tokenURI(uint256 _tokenId) public view override returns (string memory) {
    require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");

    return string(abi.encodePacked(_baseURI(), _tokenId.toString(), ".json"));
  }

  function royaltyInfo(uint256 _tokenId, uint256 _salePrice) override external view returns (address receiver, uint256 royaltyAmount) {
    return (
      royaltyReceiver[_tokenId],
      _salePrice * royaltyPercentage[_tokenId] / 100
    );
  }

  function supportsInterface(bytes4 interfaceId) override(ERC721, IERC165) public view returns (bool) {
    return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
  }
}
