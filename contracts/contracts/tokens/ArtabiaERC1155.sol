// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../GloballyApprovedOperatorsERC1155.sol";
import "../ERC1155Marketplace/ERC1155OrderMarketplace.sol";
import "../ERC1155Marketplace/ERC1155ListingMarketplace.sol";
import "../ERC1155Marketplace/ERC1155AuctionMarketplace.sol";
import "../Address.sol";
import "../IERC2981.sol";

contract ArtabiaERC1155 is GloballyApprovedOperatorsERC1155, IERC2981 {
  using Address for address;

  mapping(uint256 => address) royaltyReceiver;
  mapping(uint256 => uint8) royaltyPercentage;

  ERC1155OrderMarketplace orderMarketplace;
  ERC1155ListingMarketplace listingMarketplace;
  ERC1155AuctionMarketplace auctionMarketplace;

  constructor(address[] memory marketplaceAddresses) GloballyApprovedOperatorsERC1155("http://localhost:3000/metadata/{id}.json", marketplaceAddresses) {
    orderMarketplace = ERC1155OrderMarketplace(marketplaceAddresses[0]);
    listingMarketplace = ERC1155ListingMarketplace(marketplaceAddresses[1]);
    auctionMarketplace = ERC1155AuctionMarketplace(marketplaceAddresses[2]);
  }

  modifier onlyNonContracts() {
    require(!msg.sender.isContract(), "only non contracts");
    _;
  }

  function mint(uint256 _tokenId, uint256 _tokenQty, uint8 _royaltyPercentage) public onlyNonContracts {
    require(_royaltyPercentage <= 50, "royalty percentage too big");

    _mint(msg.sender, _tokenId, _tokenQty, "");

    royaltyReceiver[_tokenId] = msg.sender;
    royaltyPercentage[_tokenId] = _royaltyPercentage;
  }

  function mintAndCreateOrder(uint256 _tokenId, uint256 _tokenQty, uint8 _royaltyPercentage, uint256 _price) external onlyNonContracts {
    mint(_tokenId, _tokenQty, _royaltyPercentage);
    orderMarketplace.createOrder(address(this), _tokenId, _tokenQty, _price);
  }

  function mintAndCreateListing(uint256 _tokenId, uint256 _tokenQty, uint8 _royaltyPercentage) external onlyNonContracts {
    mint(_tokenId, _tokenQty, _royaltyPercentage);
    listingMarketplace.createListing(address(this), _tokenId, _tokenQty);
  }

  function mintAndCreateAuction(uint256 _tokenId, uint256 _tokenQty, uint8 _royaltyPercentage, uint128 _endsAt) external onlyNonContracts {
    mint(_tokenId, _tokenQty, _royaltyPercentage);
    auctionMarketplace.createAuction(address(this), _tokenId, _tokenQty, _endsAt);
  }

  function royaltyInfo(uint256 _tokenId, uint256 _salePrice) override external view returns (address receiver, uint256 royaltyAmount) {
    return (
      royaltyReceiver[_tokenId],
      _salePrice * royaltyPercentage[_tokenId] / 100
    );
  }

  function supportsInterface(bytes4 interfaceId) override(ERC1155, IERC165) public view returns (bool) {
    return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
  }
}
