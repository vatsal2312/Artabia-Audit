// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155.sol";

/**
 * @notice Allows for globally approved contracts that can transfer the ERC1155 tokens without the user's approval
 *
 * @dev Proxies the ERC1155 isApprovedForAll function to allow for globally approved contracts
 */
contract GloballyApprovedOperatorsERC1155 is ERC1155 {
  mapping(address => bool) private globallyApprovedOperators;
  mapping(address => mapping(address => bool)) private operatorApprovals;

  constructor(string memory _uri, address[] memory _globallyApprovedOperators) ERC1155(_uri) {
    for(uint256 i = 0; i < _globallyApprovedOperators.length; i++) {
      globallyApprovedOperators[_globallyApprovedOperators[i]] = true;
    }
  }

  function setApprovalForAll(address operator, bool approved) public virtual override {
    require(operator != _msgSender(), "ERC1155: setting approval status for self");

    operatorApprovals[_msgSender()][operator] = approved;
    emit ApprovalForAll(_msgSender(), operator, approved);
  }

  function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
    return globallyApprovedOperators[operator] || operatorApprovals[owner][operator];
  }
}
