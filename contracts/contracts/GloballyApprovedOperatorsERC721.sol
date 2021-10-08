// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";

/**
 * @notice Allows for globally approved contracts that can transfer the ERC721 tokens without the user's approval
 *
 * @dev Proxies the ERC721 isApprovedForAll function to allow for globally approved contracts
 */
contract GloballyApprovedOperatorsERC721 is ERC721 {
  mapping(address => bool) private globallyApprovedOperators;
  mapping(address => mapping(address => bool)) private operatorApprovals;

  constructor(string memory _name, string memory _symbol, address[] memory _globallyApprovedOperators) ERC721(_name, _symbol) {
    for(uint256 i = 0; i < _globallyApprovedOperators.length; i++) {
      globallyApprovedOperators[_globallyApprovedOperators[i]] = true;
    }
  }

  function setApprovalForAll(address operator, bool approved) public virtual override {
    require(operator != _msgSender(), "ERC721: approve to caller");

    operatorApprovals[_msgSender()][operator] = approved;
    emit ApprovalForAll(_msgSender(), operator, approved);
  }

  function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
    return globallyApprovedOperators[operator] || operatorApprovals[owner][operator];
  }
}
