// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// struct Constituent {
//     address tokenAddress;
//     uint proportion;
// }

contract FixedAllocation {
    // The token that is to be used as the base of this fixed allocation portfolio
    address _base_token;

    // Withdrawal requests, these are not processed immedaitely as if the portfolio balance was off
    // someone could potentially be paid more/less than they are due
    mapping(address => bool) public withdrawal_requests;

    // The total amount of the base token that has been deposited into this contract
    uint256 public total_depoisted;

    // The proportions that each index consitutent represents
    mapping(address => uint) public proportions;

    // The deposits each address has made to this account
    mapping(address => uint256) public deposits;

    // TODO: starting with 2 tokens in an equal split, needs to be generalised later.
    // Step 1, abritary percentages
    // Step 2, arbitary amount of tokens
    constructor(address baseToken, address token1, address token2) {
        // TODO validate that the addresses provided are all ERC20s
        _base_token = baseToken;
        total_depoisted = 0;
        proportions[token1] = 50;
        proportions[token2] = 50;
        // TODO: will need to be a for loop once this is more generalised
        uint totalProportions = proportions[token1] + proportions[token2];
        require(totalProportions == 100, "More than 100% represented");
    }

    function base_token() external view returns (address) {
        return _base_token;
    }

    function deposit(uint256 amount) public {
        require(
            IERC20(_base_token).transferFrom(msg.sender, address(this), amount)
        );
        deposits[msg.sender] += amount;
        total_depoisted += amount;
    }

    // TODO: Currently they either withdraw everything or nothing.
    // would be nice to specify an amount to withdraw in future
    function request_withdrawal() public {
        require(
            deposits[msg.sender] >= 0,
            "Cannot request withdrawal from an account that never deposited"
        );
        withdrawal_requests[msg.sender] = true;
    }
}
