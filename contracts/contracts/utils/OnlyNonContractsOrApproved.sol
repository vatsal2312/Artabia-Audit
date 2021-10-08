// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../Address.sol";
import "../Ownable.sol";

/**
 * @dev Auxiliary contract that exposes a onlyNonContractsOrApproved
 *      modifier allows only approved contracts to execute a function.
 */
abstract contract OnlyNonContractsOrApproved is Ownable{
  using Address for address;

  mapping(address => bool) approvedContracts;

  /**
   * @dev Adds an approved contract
   *
   * @param _contractAddress the address of the contract to be added
   */
  function addApprovedContract(address _contractAddress) external onlyOwner {
    approvedContracts[_contractAddress] = true;
  }

  /**
   * @dev Allows only for Externally-owned accounts (EOAs)
          or contracts that have been approved by the owner
   */
  modifier onlyNonContractsOrApproved() {
    require(!msg.sender.isContract() || approvedContracts[msg.sender], "only non contracts or approved");
    _;
  }
}
