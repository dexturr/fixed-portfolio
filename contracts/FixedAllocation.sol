// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// struct Constituent {
//     address tokenAddress;
//     uint proportion;
// }

contract FixedAllocation {
    uint256 public total_depoisted;
    // The proportions that each index consitutent represents
    mapping(address => uint) public proportions;

    // TODO: starting with 2 tokens in an equal split, needs to be generalised later.
    // Step 1, abritary percentages
    // Step 2, arbitary amount of tokens
    constructor(address token1, address token2) {
        total_depoisted = 0;
        proportions[token1] = 50;
        proportions[token2] = 50;
        uint totalProportions = proportions[token1] + proportions[token2];
        require(totalProportions == 100, "More than 100% represented");
    }
}
