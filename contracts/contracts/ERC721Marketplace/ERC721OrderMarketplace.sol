// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../utils/OnlyNonContractsOrApproved.sol";

import "hardhat/console.sol";

/**
 * @notice Seller marketplace for ERC721 tokens.
 *         Users are able to list ERC721 tokens for sale
 *         at set prices. The orders can also be removed
 *         by the order owner and anyone can buy.
 *
 * @dev Supports Marketplace fees and ERC-2981 royalties.
 */
contract ERC721OrderMarketplace is ERC721Holder, OnlyNonContractsOrApproved {
  using ERC165Checker for address;

  struct Order {
    address tokenAddress;
    uint256 tokenId;
    address owner;
    uint256 price;
  }

  /**
   * @dev Maps id-hash to Order.
   *      Completed or removed orders are also deleted off the mapping.
   */
  mapping(bytes32 => Order) public orders;

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
   * @dev Fired in createOrder()
   *
	 * @param id the id of the order
   */
  event OrderCreated(
    bytes32 id
  );

  /**
   * @dev Fired in removeOrder()
	 *
	 * @param id the id of the order
   */
  event OrderRemoved(
    bytes32 id
  );

  /**
   * @dev Fired in removeOrder()
	 *
	 * @param id the address that created the order
   */
  event OrderCompleted(
    bytes32 id
  );

  /**
   * @dev Allows only an order's owner
   *
   * @param _id the id of the order's token
   */
  modifier onlyOrderOwner(bytes32 _id) {
    require(orders[_id].owner == msg.sender, "only order owner");
    _;
  }

  /**
   * @notice Creates an order for an ERC721 token on the marketplace.
   *         The order is good 'til canceled (GTC)
   *
   * @param _tokenAddress the address of the token to be sold
   * @param _tokenId the id of the token to be sold
   * @param _price the price for the token
   */
  function createOrder(address _tokenAddress, uint256 _tokenId, uint256 _price) external returns (bytes32) {
    IERC721(_tokenAddress).safeTransferFrom(tx.origin, address(this), _tokenId);

    bytes32 id = keccak256(abi.encodePacked(_tokenAddress, _tokenId, _price, tx.origin, block.timestamp));

    orders[id] = Order(
      _tokenAddress,
      _tokenId,
      tx.origin,
      _price
    );

    emit OrderCreated(
      id
    );

    return id;
  }

  /**
   * @notice Removes an order from the marketplace
   *
   * @dev Can only be called by an order owner
   *
   * @param _id the id of the order to be removed
   */
  function removeOrder(bytes32 _id) external onlyOrderOwner(_id) {
    Order memory order = orders[_id];

    delete orders[_id];

    IERC721(order.tokenAddress).safeTransferFrom(address(this), msg.sender, order.tokenId);

    emit OrderRemoved(
      _id
    );
  }

  /**
   * @notice Buys an order at the price set by the order owner
   *
   * @dev Can only be called by the offer owner. Marketplace fees
   *      are transferred to feeDestination. Royalties are transferred
   *      to royaltyReceiver (NFT creator if this NFT was created on Artabia)
   *      if the NFT supports ERC-2981.
   *
   * @param _id the id of the order to be removed
   */
  function buyOrder(bytes32 _id) external payable {
    Order memory order = orders[_id];

    delete orders[_id];

    require(msg.value == order.price, 'incorrect price');

    IERC721(order.tokenAddress).safeTransferFrom(address(this), msg.sender, order.tokenId);

    address royaltyReceiver = address(0);
    uint256 royaltyAmount = 0;

    if(order.tokenAddress.supportsInterface(type(IERC2981).interfaceId)) {
      (royaltyReceiver, royaltyAmount) = IERC2981(order.tokenAddress).royaltyInfo(order.tokenId, msg.value);
    }

    if(royaltyAmount != 0) {
      payable(royaltyReceiver).transfer(royaltyAmount);
    }

    if(fee != 0) {
      feeDestination.transfer(msg.value * fee / 100_00);
    }

    payable(order.owner).transfer(msg.value * (100_00 - fee) / 100_00 - royaltyAmount);

    emit OrderCompleted(
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
