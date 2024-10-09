// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "contracts/Exchange/Exchange.sol";
import "contracts/Quote/Quote.sol";

// GENERAL TOOD: ideas that may go somewhere, everywhere or nowhere
// Generalise to N tokens (exchnage paths may be difficult here)
// How to handle slippage:
//      Percentage tolerance?
//      Absolute tolerance?
//      Percentage of portfolio tolerance?
// How to decide when it's not worth making a trade, e.g.
//      the total value of the tade is < 0.0001 USD
//      or the trade is < 0.00001% of the portfolio
//      or the cost of gas is beyond a specific limit
// Consider allowing pending deposits to be withdrawn immediately
// Can we have a base_token that is not Eth (as this is required for gas for trades).
//      Can base_token be removed and replaced with Eth always?
// Does having the base_token not present in the portfolio create issues? i.e. greater numbr of trades
//      Second thoughts, this is what has been programmed lol at you past me.
// Figure out how to either take a fee to compsenate for trading or refund the caller of rebalance or similar
// Create the ability to limit deposits to a specific set of addresses
// Consider adding deposit limits too
// Consider poor liquidity
// Allow withdrawing a percentage/absolute of the value remaining
// Look into decimals, overflow errors, safemath
// Add an emergency exit e.g. return all money to all parties, in case a portfolio could never trade e.g. a tokens value became effectively 0
// Restrict rebalancing to a single address?
// How to trigger rebalancing on a set time period

// Long term goals:
// Give tokens based on the amount deposited to tokenize this contract to tokenize this index and make it tradable
// Contact friends about (definitely present) secuirty issues

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

// TODO: I do not like this. It is most definitely doing too much.
// need to separate into parts that can be composed e.g. deposits, withdraals, valuation, rebalancing ect.
// waiting to see what makes the most sense as more functionality is added
/**
 * @title Fixed Allocation Portfolio
 * @author Dexter Edwards
 * @dev Represents a fixed allocation portfolio of 2 ERC20 tokens maintained in a specified proportion
 */
contract FixedAllocation is Ownable, IGenericErrors {
    // TODO: this is immuatable and should be marked as so but cannot do this with reference types? How to handle when I want this to have arbitart size (eventually)
    /**
     * @dev The proportions that each index consitutent represents
     */
    mapping(address => uint) public proportions;

    // TODO: RESEARCH why can this not be a simple public property e.g. address public _base_token?
    // why is a manually written getter required for only address types?
    // The token that is to be used as the base of this fixed allocation portfolio
    /**
     * @dev The base token that users can deposit to the contract in, or withdraw from the contract
     */
    IERC20 immutable _base_token;
    IERC20 immutable _token1;
    IERC20 immutable _token2;

    IExchangable immutable _exchange_address;
    IQuotable immutable _quote_address;

    /**
     * @dev An array of addresses that have requested a withdrawal on the next rebalancing cycle
     */
    address[] _withdrawal_requests;

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
     * @notice This is strictly increasing and does not compensate for withdrawals (currently)
     */
    mapping(address => uint256) public deposits;

    /**
     * @dev Emitted when base_tokens are depoisted into the portfolio
     *
     * Note that `amount_deposited` may be zero.
     */
    event Deposit(address indexed account, uint256 amount_deposited);

    /**
     * @dev Emitted when tokens are depoisted into the portfolio
     *
     * Note that `pending_amount` may be zero.
     */
    event WithdrawalRequest(address indexed account);

    // TODO: Is an event needed for the desired trade and actual trade for reconciliation?
    /**
     * @dev Emitted when the portfolio decides to make a buy
     * @param token The token that the buy is being exectued on
     * @param is_buy If the trade is a buy or a sell
     * @param amount The amount (in the token value) that is being traded
     * @param base_token_amount The amount in the base token value that is being traded
     */
    event Trade(
        address indexed token,
        bool indexed is_buy,
        uint256 amount,
        uint256 base_token_amount
    );

    constructor(
        IERC20 baseToken,
        IERC20 token1,
        IERC20 token2,
        IExchangable exchange_address,
        IQuotable quote_address
    ) Ownable(msg.sender) {
        // TODO: starting with 2 tokens in an equal split, needs to be generalised later.
        // Step 1, abritary percentages
        // Step 2, arbitary amount of tokens

        // TODO: validate that the addresses provided are all ERC20s?
        _base_token = baseToken;
        _token1 = token1;
        _token2 = token2;

        _exchange_address = exchange_address;
        _quote_address = quote_address;
        total_depoisted = 0;
        total_pending_deposits = 0;

        proportions[address(token1)] = 50;
        proportions[address(token2)] = 50;

        // TODO: will need to be a for loop once this is more generalised
        uint totalProportions = proportions[address(token1)] +
            proportions[address(token2)];
        require(totalProportions == 100, "More than 100% represented");
    }

    /**
     * @dev Check if an address has requested a withdrawal on the next investment cycle
     * @param account The account to check
     * @return bool If this account has requested a withdrawal
     */
    function withdrawal_requests(address account) external view returns (bool) {
        bool has_requested = false;
        for (uint index = 0; index < _withdrawal_requests.length; index++) {
            address request_address = _withdrawal_requests[index];
            if (account == request_address) {
                has_requested = true;
                break;
            }
        }
        return has_requested;
    }

    /**
     * @dev The base token that users can deposit to the contract in, or withdraw from the contract
     * @return base_token_address The address of the base token
     */
    function base_token() external view returns (address) {
        return address(_base_token);
    }

    /**
     * @dev The total balance of the portfolio at this time in base_token, based on the valuations
     * @return total_balance The total balance of the portfolio at this time in base_token
     */
    function total_portfolio_base_balance() external view returns (uint256) {
        return
            portfolio_base_token_value(address(_token1)) +
            portfolio_base_token_value(address(_token2));
    }

    function portfolio_base_token_value(
        address token
    ) public view returns (uint256) {
        uint256 base_value_token = IQuotable(_quote_address).quote(
            address(_base_token),
            token
        );
        return IERC20(token).balanceOf(address(this)) * base_value_token;
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
        _withdrawal_requests.push(msg.sender);
        emit WithdrawalRequest(msg.sender);
    }

    /**
     * @dev Exchnage a given token for another
     * @param token_sent The token that is being exchanged
     * @param token_amount The amount of the token being exchanged
     * @param token_received The token we are exchanging the token_sent for
     */
    function exchange_tokens(
        address token_sent,
        uint256 token_amount,
        address token_received
    ) public {
        // TODO: Does this need to be reset each time? Uniswap does it so probably. Understand why.
        // Set the approval limit
        require(
            IERC20(token_sent).approve(address(_exchange_address), token_amount)
        );
        uint256 recieved = IExchangable(_exchange_address).swap(
            token_sent,
            token_amount,
            token_received
        );
        emit Trade(token_received, true, token_amount, recieved);
        // Reset the approval limit back to 0
        require(IERC20(token_sent).approve(address(_exchange_address), 0));
    }

    /**
     * @dev Performs the initial investment of deposits, without the need of worrying about withdrawals and other exchanges.
     */
    function initial_investment() public onlyOwner {
        // Investing the whole lot at the moment. Could just balanceOf the contract too?
        // not sure which would be better or why it might be better?
        uint256 total_token1_trade = (total_pending_deposits *
            proportions[address(_token1)]) / 100;
        exchange_tokens(
            address(_base_token),
            total_token1_trade,
            address(_token1)
        );
        uint256 total_token2_trade = (total_pending_deposits *
            proportions[address(_token2)]) / 100;
        exchange_tokens(
            address(_base_token),
            total_token2_trade,
            address(_token2)
        );
        // TODO: Mark pending deposits as completed
    }

    // TODO: May exceed maxiumum gas with this algo, consider sending the withdrawals to
    // a pending for withdrawal bucket and forcing the user to withdraw again.
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
