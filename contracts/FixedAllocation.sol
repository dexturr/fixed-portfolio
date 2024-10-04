// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// GENERAL TOOD:
// How to handle slippage
// How to decide when it's not worth making a trade, e.g. the total value of the tade is < 0.0001 USD or the trade is < 0.00001% of the portfolio

// May be useful when tring to generalise the constructor?
// perhaps a type for each token would be useful in general?
// struct Constituent {
//     address tokenAddress;
//     uint proportion;
//     address valuationAddress;
//      Not sure, if this is a good idea, for >2 tokens then there comes path finding logic and a single property is not enough...
//      Could use a dijkstra's where length of vertex = cost of trade
//      Maybe we just assume there is the most liquidity between base_token and every other token, e.g. in the base_token = eth case this is likely to be true
//      What's the pragmatic choice here?
//     address exchangeAddress??
// }

contract FixedAllocation {
    // TODO: RESEARCH why can this not be a simple public property e.g. address public _base_token?
    // why is a manually written getter required for only address types?
    // The token that is to be used as the base of this fixed allocation portfolio
    address _base_token;

    // Withdrawal requests, these are not processed immedaitely as if the portfolio balance was off
    // someone could potentially be paid more/less than they are due
    mapping(address => uint256) public withdrawal_requests;
    uint256 public total_pending_withdrawals;

    // The total amount of the base token that has been deposited into this contract
    uint256 public total_depoisted;

    // The total amount of the base token that was traded into assets on last rebalance
    uint256 public total_in_portfolio;

    // Balances of the portfolio in each asset
    mapping(address => uint256) public balances;

    // The proportions that each index consitutent represents
    mapping(address => uint) public proportions;

    // The pending deposits each address has made to this fund
    mapping(address => uint256) public pending_deposits;
    uint256 public total_pending_deposits;

    // The deposits each address has made to this fund
    mapping(address => uint256) public deposits;

    // TODO: starting with 2 tokens in an equal split, needs to be generalised later.
    // Step 1, abritary percentages
    // Step 2, arbitary amount of tokens
    constructor(address baseToken, address token1, address token2) {
        // TODO validate that the addresses provided are all ERC20s
        _base_token = baseToken;
        total_depoisted = 0;
        total_pending_deposits = 0;
        proportions[token1] = 50;
        proportions[token2] = 50;
        balances[token1] = 0;
        balances[token2] = 0;
        // TODO: will need to be a for loop once this is more generalised
        uint totalProportions = proportions[token1] + proportions[token2];
        require(totalProportions == 100, "More than 100% represented");
    }

    function base_token() external view returns (address) {
        return _base_token;
    }

    // TEST: add test case for same address depositing multilpe times in a single period
    function deposit(uint256 amount) public {
        require(
            IERC20(_base_token).transferFrom(msg.sender, address(this), amount)
        );
        deposits[msg.sender] += amount;
        pending_deposits[msg.sender] += amount;
        total_pending_deposits += amount;
        total_depoisted += amount;
    }

    // TODO: Currently they either withdraw everything or nothing.
    // would be nice to specify an amount to withdraw in future
    function request_withdrawal() public {
        require(
            deposits[msg.sender] >= 0,
            "Cannot request withdrawal from an account that never deposited"
        );
        // Currently withdrawing everyting rather than a single thing
        withdrawal_requests[msg.sender] = deposits[msg.sender];
        total_pending_withdrawals += deposits[msg.sender];
    }

    function rebalance() public {
        // BIG TODO: Do we process the withdrawals with the CURRENT value
        // or do we process withdrawals with the DESIRED value??
        // going to do withdrawals from current state I think?
        // theorectically does not matter right? As each way the total amount of base tokens is the same.
        //
        // LATER TODO: refund caller (in some way)
        // TODO: process new money in
        // uint256 total_new_money = 0
        // for (uint256 index = 0; index < pending_deposits.length; index++) {
        // }
        //
        //
        // TODO: process withdrawal deltas (based on deposits too micro dark pool)
        // TODO: estimate portfolio value
        // TODO: decide on exchange values
        // TODO: actually do the exchange
        // TODO: resets total value in portfolio again
        // TODO: process actual withdrawals
        // TODO: set withdrawals as processed
        // TODO: set deposits as processed
        // TODO: validate everything (in all the steps above as well)
    }
}
