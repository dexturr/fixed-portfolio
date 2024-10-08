// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IExchangable {
    function swap(
        address token_sent,
        uint256 amount,
        address token_received
    ) external returns (uint256);
}

contract MockExchange is IExchangable {
    mapping(address => mapping(address => uint256)) public rates;

    // TODO: should only be allowed by the owner, but as this is a mock IDC
    function add_rate(
        address base_token_address,
        address exchange_token_address,
        uint256 rate
    ) public {
        rates[base_token_address][exchange_token_address] = rate;
    }

    function swap(
        address token_sent,
        uint256 amount,
        address token_received
    ) external returns (uint256) {
        uint256 exchanged_amount = amount * rates[token_sent][token_received];
        require(
            IERC20(token_sent).transferFrom(msg.sender, address(this), amount)
        );
        require(
            IERC20(token_received).transferFrom(
                address(this),
                msg.sender,
                exchanged_amount
            )
        );
        return exchanged_amount;
    }
}
