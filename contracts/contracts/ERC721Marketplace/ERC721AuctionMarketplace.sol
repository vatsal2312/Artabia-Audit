// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/OnlyNonContractsOrApproved.sol";

import "hardhat/console.sol";

/**
 * @notice Seller marketplace for ERC721 tokens.
 *         Users are able to create auctions for ERC721 tokens
 *         without specifying a set price. These auctions can
 *         receive bids by anyone that are guaranteed for the auction time.
 *         Only the highest bid is stored on the blockchain and bidders are
 *         refunded automatically when outbid. The highest bid is automatically
 *         accepted at the end of the auction and the auction must be claimed for
 *         the end transfer to happen.
 *
 * @dev Supports Marketplace fees and ERC-2981 royalties.
 */
contract ERC721AuctionMarketplace is ERC721Holder, OnlyNonContractsOrApproved {
  using Address for address;
  using ERC165Checker for address;

  struct Auction {
    address tokenAddress;
    uint256 tokenId;
    address owner;
    uint128 bid;
    address bidder;
    uint128 endsAt;
  }

  /**
   * @dev Maps id-hash to Order.
   *      Completed or removed orders are also deleted off the mapping.
   */
  mapping(bytes32 => Auction) public auctions;

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
    feeDestination = _feeDestination;
  }

  // NOTE: The events currently just emit an id parameter.
  // This will be adjusted according to future front-end
  // requirements.

  /**
   * @dev Fired in createAuction()
   *
	 * @param id the id of the auction
   */
  event AuctionCreated(
    bytes32 id
  );

  /**
   * @dev Fired in bidOnAuction()
   *
	 * @param id the id of the auction
   */
  event AuctionBidPlaced(
    bytes32 id
  );

  /**
   * @dev Fired in removeAuction()
   *
	 * @param id the id of the auction
   */
  event AuctionClaimed(
    bytes32 id
  );

  /**
   * @dev Allows only if auction has not ended
   *
   * @param _id the id of the auction
   */
  modifier onlyIfAuctionNotEnded(bytes32 _id) {
    require(auctions[_id].endsAt >= block.timestamp, "auction ended");
    _;
  }

  /**
   * @dev Allows only if auction has ended
   *
   * @param _id the id of the auction
   */
  modifier onlyIfAuctionEnded(bytes32 _id) {
    require(auctions[_id].endsAt < block.timestamp && auctions[_id].tokenAddress != address(0), "auction not ended");
    _;
  }

  /**
   * @notice Creates an auction for an ERC721 token
   *
   * @dev Only approved contracts can call this function
   *
   * @dev tx.origin is used instead of msg.sender throughout this
   *      function as the sender might be an allowed proxy contract.
   *      In that case we want to create the auction for the user who
   *      initiated the transaction and not the intermediary contract.
   *
   * @param _tokenAddress the address of the token to be auctioned
   * @param _tokenId the id of the token to be auctioned
   * @param _endsAt when the auction ends
   */
  function createAuction(address _tokenAddress, uint256 _tokenId, uint128 _endsAt) external onlyNonContractsOrApproved returns (bytes32) {
    // require(_endsAt >= block.timestamp + 1 days, "ends too early");

    bytes32 id = keccak256(abi.encodePacked(_tokenAddress, _tokenId, tx.origin, _endsAt, block.timestamp));

    IERC721(_tokenAddress).safeTransferFrom(tx.origin, address(this), _tokenId);

    auctions[id] = Auction(
      _tokenAddress,
      _tokenId,
      tx.origin,
      0,
      address(0),
      _endsAt
    );

    emit AuctionCreated(
      id
    );

    return id;
  }

  /**
   * @notice Places a bid on an existing auction
   *
   * @dev Only approved contracts can call this function
   *
   * @param _id the id of the auction
   */
  function bidOnAuction(bytes32 _id) external payable onlyIfAuctionNotEnded(_id) onlyNonContractsOrApproved {
    Auction storage auction = auctions[_id];

    require(msg.value > auction.bid, "bid too low");

    // We must again check whether the offeror is a contract
    // as he may have become one by the time he submitted his offer.
    // We need to ensure he is not a contract since he may have a
    // fallback function that throws and would not allow for this
    // function to complete.
    if(auction.bidder != address(0) && !auction.bidder.isContract()) {
      payable(auction.bidder).transfer(auction.bid);
    }

    auction.bidder = msg.sender;
    auction.bid = uint128(msg.value);

    emit AuctionBidPlaced(
      _id
    );
  }

  /**
   * @notice Claims an auction after it has ended and
   *         makes the appropriate transfers.
   *
   * @dev Only approved contracts can call this function
   *
   * @param _id the id of the auction
   */
  function claimAuction(bytes32 _id) external onlyIfAuctionEnded(_id) {
    Auction memory auction = auctions[_id];

    delete auctions[_id];

    address royaltyReceiver;
    uint256 royaltyAmount;

    (royaltyReceiver, royaltyAmount) = IERC2981(auction.tokenAddress).royaltyInfo(auction.tokenId, auction.bid);

    // We assume the fee destination function is safe to send
    // funds to as it is controlled by the token contract owner
    if(royaltyAmount != 0) {
      payable(royaltyReceiver).transfer(royaltyAmount);
    }

    if(auction.tokenAddress.supportsInterface(type(IERC2981).interfaceId)) {
      (royaltyReceiver, royaltyAmount) = IERC2981(auction.tokenAddress).royaltyInfo(auction.tokenId, auction.bid);
    }

    // We assume the fee destination function is safe to send
    // funds to as it is controlled by the contract owner
    if(fee != 0) {
      feeDestination.transfer(auction.bid * fee / 100_00);
    }

    payable(auction.owner).transfer(auction.bid * (100_00 - fee) / 100_00 - royaltyAmount);

    // We must again check whether the bidder is a contract
    // as he may have become one by the time he submitted his offer.
    // We need to ensure he is not a contract since he may have a
    // fallback function that throws and would not allow for this
    // function to complete.
    if(auction.bidder != address(0) && !auction.bidder.isContract()) {
      IERC721(auction.tokenAddress).safeTransferFrom(address(this), auction.bidder, auction.tokenId);
    }

    emit AuctionClaimed(
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
