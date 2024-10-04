// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// GENERAL TOOD: ideas that may go somewhere, everywhere or nowhere
// How to handle slippage
//      Percentage tolerance?
//      Absolute tolerance?
//      Percentage of portfolio tolerance?
// How to decide when it's not worth making a trade, e.g.
//      the total value of the tade is < 0.0001 USD
//      or the trade is < 0.00001% of the portfolio
//      or the cost of gas is beyond a specific limit
// Consider allowing pending deposits to be withdrawn immediately
// Can we have a base_token that is not Eth (as this is required for gas for trades)
// Does having the base_token not present in the portfolio create issues? i.e. greater numbr of trades
// Figure out how to either take a fee to compsenate for trading or similar
// Create the ability to limit deposits to a specific set of addresses
// Consider adding deposit limits
// Five tokens based on the amount deposited to tokenize this contract
// Consider poor liquidity
// Allow withdrawing a percentage of the value remaining

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

/**
 * @dev Generic errors that can be used in many different contracts
 */
interface IGenericErrors {
    /**
     * @dev Indicates that a contract method has yet to be implmeneted
     */
    error NotImplemented();
}

/**
 * @title Fixed Allocation Portfolio
 * @author Dexter Edwards
 * @dev Represents a fixed allocation portfolio of ERC20 tokens in a specified proportion
 */
contract FixedAllocation is IGenericErrors {
    // TODO: RESEARCH why can this not be a simple public property e.g. address public _base_token?
    // why is a manually written getter required for only address types?
    // The token that is to be used as the base of this fixed allocation portfolio
    /**
     * @dev The base token that users can deposit to the contract in, or withdraw from the contract
     */
    address _base_token;

    // Withdrawal requests, these are not processed immedaitely as if the portfolio balance was off
    // someone could potentially be paid more/less than they are due
    mapping(address => uint256) public withdrawal_requests;
    uint256 public total_pending_withdrawals;

    /**
     * @dev The total amount of the base token that has been deposited into this contract
     */
    uint256 public total_depoisted;

    /**
     * @dev The total amount of the base token that was traded into assets on last rebalance
     * @notice This is not equal to total deposited because of pending deposits
     */
    uint256 public total_in_portfolio;

    /**
     * @dev Balances of the portfolio in each asset
     */
    mapping(address => uint256) public balances;

    /**
     * @dev The proportions that each index consitutent represents
     */
    mapping(address => uint) public proportions;

    /**
     * @dev The pending deposits each address has made to this fund
     * @notice This is balnked after each investment cycle
     */
    mapping(address => uint256) public pending_deposits;
    /**
     * @dev The total amount of base token awaiting to be bought into the portfolio on next cycle
     */
    uint256 public total_pending_deposits;

    /**
     * @dev The deposits each address has made to this fund
     * @notice This is strictly increasing and does not compensate for withdrawals (currently()
     */
    mapping(address => uint256) public deposits;

    /**
     * @dev Emitted when base_tokens are depoisted into the portfolio
     *
     * Note that `amount_deposited` may be zero.
     */
    event Deposit(address indexed from, uint256 amount_deposited);

    /**
     * @dev Emitted when tokens are depoisted into the portfolio
     *
     * Note that `pending_amount` may be zero.
     */
    event WithdrawalRequest(address indexed from, uint256 pending_amount);

    // TODO: Is an event needed for the desired trade and actual trade for reconciliation?
    // /**
    //  * @dev Emitted when the portfolio decides to make a buy
    //  * @param token The token that the buy is being exectued on
    //  * @param is_buy If the trade is a buy or a sell
    //  * @param amount The amount (in the token value) that is being traded
    //  * @param base_token_amount The amount in the base token value that is being traded
    //  */
    // event Trade(
    //     address indexed token,
    //     bool indexed is_buy,
    //     uint256 amount,
    //     uint256 base_token_amount
    // );

    constructor(address baseToken, address token1, address token2) {
        // TODO: starting with 2 tokens in an equal split, needs to be generalised later.
        // Step 1, abritary percentages
        // Step 2, arbitary amount of tokens

        // TODO: validate that the addresses provided are all ERC20s
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

    /**
     * @dev The base token that users can deposit to the contract in, or withdraw from the contract
     */
    function base_token() external view returns (address) {
        return _base_token;
    }

    /**
     * @dev Deposits into the contact
     * @param amount amount of the base_token to deposit
     * @notice This does not perform trades, merely transfers the money and marks the deposit as pending
     * @notice Before a withdrawal can be performed the money must be traded and then a withdrawal be performed. Suboptimal.
     */
    function deposit(uint256 amount) public {
        require(
            IERC20(_base_token).transferFrom(msg.sender, address(this), amount)
        );
        deposits[msg.sender] += amount;
        pending_deposits[msg.sender] += amount;
        total_pending_deposits += amount;
        total_depoisted += amount;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev Request withdrawal for the contract calling this function
     * @notice All of the money must be removed at once
     * @notice The money can only be withdrawn during an investment cycle
     * @notice The money can only be withdrawn after a deposit has been invested
     */
    function request_withdrawal() public {
        require(
            deposits[msg.sender] >= 0,
            "Cannot request withdrawal from an account that never deposited"
        );
        // Currently withdrawing everyting
        uint256 amount = deposits[msg.sender];
        withdrawal_requests[msg.sender] = amount;
        // TODO: this is not correct as it does not compensate for deposits between withdrawal and investment cycle
        total_pending_withdrawals += amount;
        emit WithdrawalRequest(msg.sender, amount);
    }

    // TODO: May exceed maxiumum gas with this algo
    /**
     * @dev Processes withdrawals & deposits and rebalances the portfolio
     */
    function rebalance() public {
        revert NotImplemented();
        // BIG TODO: Do we process the withdrawals with the CURRENT value
        // or do we process withdrawals with the DESIRED value??
        // going to do withdrawals from current state I think?
        // theorectically does not matter right? As each way the total amount of base tokens is the same.
        //
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
