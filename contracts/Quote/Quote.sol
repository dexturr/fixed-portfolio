// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IQuotable {
    function quote(
        address base_token_address,
        address exchange_token_address
    ) external view returns (uint256);
}

contract MockQuote is IQuotable {
    mapping(address => mapping(address => uint256)) public rates;

    // TODO: should only be allowed by the owner, but as this is a mock IDC
    function add_rate(
        address base_token_address,
        address exchange_token_address,
        uint256 rate
    ) public {
        rates[base_token_address][exchange_token_address] = rate;
    }

    function quote(
        address base_token_address,
        address exchange_token_address
    ) external view returns (uint256) {
        return rates[base_token_address][exchange_token_address];
    }
}
