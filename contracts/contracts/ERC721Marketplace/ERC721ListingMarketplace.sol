// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../ERC165Checker.sol";
import "../IERC721.sol";
import "../IERC2981.sol";
import "../ERC721Holder.sol";
import "../Address.sol";
import "../Ownable.sol";
import "../utils/OnlyNonContractsOrApproved.sol";

import "../console.sol";

/**
 * @notice Seller marketplace for ERC721 tokens.
 *         Users are able to create listings for ERC721 tokens
 *         without specifying a set price. These listings can
 *         receive offers by anyone that are guaranteed for 2 days.
 *         After the 2 days, the offeror may choose to withdraw his
 *         offer at any time. Only the biggest offer is stored on the
 *         blockchain and the order owner can choose to accept it or
 *         remove the listing at any time.
 *
 * @dev Supports Marketplace fees and ERC-2981 royalties.
 */
contract ERC721ListingMarketplace is ERC721Holder, OnlyNonContractsOrApproved {
  using Address for address;
  using ERC165Checker for address;

  struct Listing {
    address tokenAddress;
    uint256 tokenId;
    address owner;
    uint128 offer;
    address offeror;
    uint128 offerPlacedAt;
  }

  /**
   * @dev Maps id-hash to Order.
   *      Completed or removed orders are also deleted off the mapping.
   */
  mapping(bytes32 => Listing) public listings;

  /**
   * @notice Address for marketplace fees to be sent to
   */
  address payable public feeDestination;

  /**
   * @notice Percentage fee to be collected from orders
   *
   * @dev Supports 2 decimal points(e.g. 750 = 7.5% fee)
   */
  uint16 public fee = 5_00;

  constructor(address payable _feeDestination) {
    _feeDestination = feeDestination;
  }

  // NOTE: The events currently just emit an id parameter.
  // This will be adjusted according to future front-end
  // requirements.

  /**
   * @dev Fired in createListing()
   *
	 * @param id the id of the listing
   */
  event ListingCreated(
    bytes32 id
  );

  /**
   * @dev Fired in placeOffer()
   *
	 * @param id the id of the listing
   */
  event ListingOfferPlaced(
    bytes32 id
  );

  /**
   * @dev Fired in withdrawOffer()
   *
	 * @param id the id of the listing
   */
  event ListingOfferWithdrawn(
    bytes32 id
  );

  /**
   * @dev Fired in removeListing()
   *
	 * @param id the id of the listing
   */
  event ListingRemoved(
    bytes32 id
  );

  /**
   * @dev Fired in acceptListingOffer()
   *
	 * @param id the id of the listing
   */
  event ListingCompleted(
    bytes32 id
  );

  /**
   * @dev Allows only for listing owner
   *
   * @param _id listing id
   */
  modifier onlyListingOwner(bytes32 _id) {
    require(listings[_id].owner == msg.sender, "only listing owner");
    _;
  }

  /**
   * @dev Allows only for listing offeror
   *
   * @param _id listing id
   */
  modifier onlyListingOfferor(bytes32 _id) {
    require(listings[_id].offeror == msg.sender, "only offeror");
    _;
  }

  /**
   * @dev Allows only if listing has offer
   *
   * @param _id listing id
   */
  modifier onlyIfListingHasOffer(bytes32 _id) {
    require(listings[_id].offeror != address(0), "listing with no offer");
    _;
  }

  /**
   * @notice Creates a listing for an ERC721 token
   *
   * @dev Only approved contracts can call this function
   *
   * @dev tx.origin is used instead of msg.sender throughout this
   *      function as the sender might be an allowed proxy contract.
   *      In that case we want to create the listing for the user who
   *      initiated the transaction and not the intermediary contract.
   *
   * @param _tokenAddress the address of the token to be listed
   * @param _tokenId the id of the token to be listed
   */
  function createListing(address _tokenAddress, uint256 _tokenId) external onlyNonContractsOrApproved returns (bytes32) {
    IERC721(_tokenAddress).safeTransferFrom(tx.origin, address(this), _tokenId);

    bytes32 id = keccak256(abi.encodePacked(_tokenAddress, _tokenId, tx.origin, block.timestamp));

    listings[id] = Listing(
      _tokenAddress,
      _tokenId,
      tx.origin,
      0,
      address(0),
      0
    );

    emit ListingCreated(
      id
    );

    return id;
  }

  /**
   * @notice Places an offer on an existing listing
   *
   * @dev Only approved contracts can call this function
   */
  function placeOffer(bytes32 _id) external payable onlyNonContractsOrApproved {
    Listing storage listing = listings[_id];

    require(msg.value > listing.offer, "offer too low");

    // We must again check whether the offeror is a contract
    // as he may have become one by the time he submitted his offer.
    // We need to ensure he is not a contract since he may have a
    // fallback function that throws and would not allow for this
    // function to complete.
    if(listing.offeror != address(0) && !listing.offeror.isContract()) {
      payable(listing.offeror).transfer(listing.offer);
    }

    listing.offeror = msg.sender;
    listing.offer = uint128(msg.value);
    listing.offerPlacedAt = uint128(block.timestamp);

    emit ListingOfferPlaced(
      _id
    );
  }

  /**
   * @notice Withdraws an offer for a listing
   *
   * @dev Can only be called by the offeror 48 hours
   *      after the offer is made. Contracts cannot
   *      call this function.
   */
  function withdrawOffer(bytes32 _id) external onlyListingOfferor(_id) {
    Listing storage listing = listings[_id];

    require(block.timestamp > listing.offerPlacedAt + 2 days, "withdrawal too early");

    listing.offer = 0;
    listing.offeror = address(0);
    listing.offerPlacedAt = 0;

    payable(msg.sender).transfer(listing.offer);

    emit ListingOfferWithdrawn(
      _id
    );
  }

  /**
   * @notice Removes a listing
   *
   * @dev Can only be called by the listing owner.
   *      Only approved contracts can call this function.
   */
  function removeListing(bytes32 _id) external onlyListingOwner(_id) onlyNonContractsOrApproved {
    Listing memory listing = listings[_id];

    delete listings[_id];

    // We must again check whether the offeror is a contract
    // as he may have become one by the time he submitted his offer.
    // We need to ensure he is not a contract since he may have a
    // fallback function that throws and would not allow for this
    // function to complete.
    if(listing.offeror != address(0) && !listing.offeror.isContract()) {
      payable(listing.offeror).transfer(listing.offer);
    }

    IERC721(listing.tokenAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);

    emit ListingRemoved(
      _id
    );
  }

  /**
   * @notice Accepts the listing's highest offer
   *
   * @dev Can only be called by the listing owner. Marketplace fees
   *      are transferred to feeDestination. Royalties are transferred
   *      to royaltyReceiver (NFT creator if this NFT was created on Artabia)
   *      if the NFT supports ERC-2981.
   *
   * @param _id the id of the order to be removed
   */
  function acceptListingOffer(bytes32 _id) external onlyListingOwner(_id) onlyIfListingHasOffer(_id) onlyNonContractsOrApproved {
    Listing memory listing = listings[_id];

    delete listings[_id];

    address royaltyReceiver;
    uint256 royaltyAmount;

    if(listing.tokenAddress.supportsInterface(type(IERC2981).interfaceId)) {
      (royaltyReceiver, royaltyAmount) = IERC2981(listing.tokenAddress).royaltyInfo(listing.tokenId, listing.offer);
    }

    // We assume the fee destination function is safe to send
    // funds to as it is controlled by the token contract owner
    if(royaltyAmount != 0) {
      payable(royaltyReceiver).transfer(royaltyAmount);
    }

    // We assume the fee destination function is safe to send
    // funds to as it is controlled by the contract owner
    if(fee != 0) {
      feeDestination.transfer(listing.offer * fee / 100_00);
    }

    // The check for whether msg.sender is a contract happens
    // at the start of the function (onlyNonContractsOrApproved modifier)
    payable(msg.sender).transfer(listing.offer * (100_00 - fee) / 100_00 - royaltyAmount);

    // We must again check whether the offeror is a contract
    // as he may have become one by the time he submitted his offer.
    // We need to ensure he is not a contract since he may have a
    // fallback function that throws and would not allow for this
    // function to complete.
    if(!listing.offeror.isContract()) {
      IERC721(listing.tokenAddress).safeTransferFrom(address(this), listing.offeror, listing.tokenId);
    }

    emit ListingCompleted(
      _id
    );
  }

  /**
   * @notice Changes the fee destination address
   *
   * @dev Can only be called by contract owner
   *
   * @param _feeDestination new address to receive marketplace fees
   */
  function changeFeeDestination(address payable _feeDestination) external onlyOwner {
    feeDestination = _feeDestination;
  }

  /**
   * @notice Changes the marketplace fee percentage
   *
   * @dev Can only be called by the contract owner. Maximum fee
   *      is 7.5%
   *
   * @param _fee new fee. Supports 2 decimal points(e.g. 750 = 7.5% fee)
   */
  function changeFee(uint16 _fee) external onlyOwner {
    require(_fee <= 7_50, "too big of a fee");

    fee = _fee;
  }
}
