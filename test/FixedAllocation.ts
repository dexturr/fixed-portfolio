import {
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

const TOTAL_SUPPLY = 100

// TODO: I don't like that the owner is also the owner of all tokens and the tests rely on this
// would be better to have the owner as a hub account and setup an account in the correct state for each test I think

describe("FixedAllocation", function () {
    async function deployTokens() {
        const Token = await hre.ethers.getContractFactory("Token");
        const wEth = await Token.deploy('Weth', "WETH", TOTAL_SUPPLY);
        const tokenA = await Token.deploy('TokenA', "TKA", TOTAL_SUPPLY);
        const tokenB = await Token.deploy('TokenB', "TKB", TOTAL_SUPPLY);
        const [addressA, addressB, wethAddress] = await Promise.all([
            tokenA.getAddress(),
            tokenB.getAddress(),
            wEth.getAddress()
        ])
        return {
            tokenA, tokenB, addressA, addressB, wethAddress, wEth
        }
    }

    // TODO: too much setup for some of these tests. Not enough for others. Start splitting into util functions + other describe blocks
    async function deployBasicFixedAllocation() {
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount] = await hre.ethers.getSigners();
        const { tokenA, tokenB, addressA, addressB, wethAddress, wEth } = await deployTokens()
        const Quote = await hre.ethers.getContractFactory("MockQuote");
        const Exchange = await hre.ethers.getContractFactory("MockExchange");
        const exchange = await Exchange.deploy()
        const quote = await Quote.deploy()
        const [quoteAddress, exchangeAddress] = await Promise.all([
            quote.getAddress(),
            exchange.getAddress(),
        ])

        // Setup 1weth = 2A = 4B
        quote.add_rate(wethAddress, addressA, 2)
        quote.add_rate(wethAddress, addressB, 4)
        quote.add_rate(addressA, addressB, 2)

        // Setup 1weth = 2A = 4B
        exchange.add_rate(wethAddress, addressA, 2)
        exchange.add_rate(wethAddress, addressB, 4)
        exchange.add_rate(addressA, addressB, 2)

        // Construct the ficed allocation contract
        const FixedAllocation = await hre.ethers.getContractFactory("FixedAllocation");
        const fixedAllocation = await FixedAllocation.deploy(wethAddress, addressA, addressB, exchangeAddress, quoteAddress)
        const fixedAllocationAddress = await fixedAllocation.getAddress();
        return {
            tokenA,
            tokenB,
            owner,
            otherAccount,
            fixedAllocation,
            addressA,
            addressB,
            wethAddress,
            wEth,
            fixedAllocationAddress,
            quoteAddress,
            exchnageAddress: exchangeAddress,
            exchange,
            quote
        };
    }

    describe('FixedAllocation', () => {
        it('Should set constructor properties correctly', async () => {
            const { tokenA, tokenB, fixedAllocation, addressA, addressB, wethAddress } = await loadFixture(deployBasicFixedAllocation);
            expect(await tokenA.totalSupply()).to.equal(TOTAL_SUPPLY);
            expect(await tokenB.totalSupply()).to.equal(TOTAL_SUPPLY);
            expect(await fixedAllocation.total_in_portfolio()).to.equal(0)
            expect(await fixedAllocation.proportions(addressA)).to.equal(50n)
            expect(await fixedAllocation.proportions(addressB)).to.equal(50n)
            expect(await fixedAllocation.total_depoisted()).to.equal(0n)
            expect(await fixedAllocation.total_pending_deposits()).to.equal(0)
            expect(await fixedAllocation.base_token()).to.equal(wethAddress)
        });
        describe('Deposits', () => {
            it('increments the total deposited amount and the deposits map when a deposit is made', async () => {
                const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                const amount = TOTAL_SUPPLY / 2
                await fixedAllocation.deposit(amount)
                expect(await fixedAllocation.total_depoisted()).to.equal(amount)
                expect(await fixedAllocation.total_pending_deposits()).to.equal(amount)
                expect(await fixedAllocation.deposits(owner)).to.equal(amount)
                expect(await fixedAllocation.pending_deposits(owner)).to.equal(amount)
            });
            it('emits an event when a user has deposited', async () => {
                const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                const amount = TOTAL_SUPPLY / 2
                await expect(fixedAllocation.deposit(amount))
                    .to.emit(fixedAllocation, "Deposit")
                    .withArgs(owner, amount);
            });
            it('processes multilpe deposits correctly', async () => {
                const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                const amount1 = TOTAL_SUPPLY / 4
                const amount2 = TOTAL_SUPPLY / 2
                const total = amount1 + amount2
                await fixedAllocation.deposit(amount1)
                await fixedAllocation.deposit(amount2)
                expect(await fixedAllocation.total_depoisted()).to.equal(total)
                expect(await fixedAllocation.total_pending_deposits()).to.equal(total)
                expect(await fixedAllocation.deposits(owner)).to.equal(total)
                expect(await fixedAllocation.pending_deposits(owner)).to.equal(total)
            });
            it('rejects a deposit request if the user has insufficent funds', async () => {
                const { fixedAllocation, fixedAllocationAddress, otherAccount, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.connect(otherAccount).approve(fixedAllocationAddress, TOTAL_SUPPLY)
                await expect(fixedAllocation.connect(otherAccount).deposit(1)).to.be.revertedWithCustomError(
                    wEth, "ERC20InsufficientBalance"
                );
                expect(await fixedAllocation.total_depoisted()).to.equal(0)
                expect(await fixedAllocation.total_pending_deposits()).to.equal(0)
                expect(await fixedAllocation.deposits(otherAccount)).to.equal(0)
                expect(await fixedAllocation.pending_deposits(otherAccount)).to.equal(0)
            });
        })
        describe('Withdrawals', () => {
            it('marks a users request for withdrawal when one is processed, increments total ', async () => {
                const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                const amount = TOTAL_SUPPLY / 2
                await fixedAllocation.deposit(amount)
                await fixedAllocation.request_withdrawal()
                expect(await fixedAllocation.withdrawal_requests(owner)).to.equal(true)
            });
            it('emits an event when a user has requested a withdrawal', async () => {
                const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                const amount = TOTAL_SUPPLY / 2
                await fixedAllocation.deposit(amount)
                await expect(fixedAllocation.request_withdrawal())
                    .to.emit(fixedAllocation, "WithdrawalRequest")
                    .withArgs(owner);
            });
            // TODO probably needs to be more of an e2e or integration test really
            // it('process a deposit, withdrawal and then deposit request correctly over multilpe vesting cycles', () => {
            //     // It doesn't because we are storing the withdrawal requests as an amount
            //     // which means that only SOME of the request would be marked for withdrawal
            //     // not all.
            //     //
            //     // Needs withdrawal_requests to be address[], rather than mapping(address => uint256)
            //     expect(false).to.be.equal(true)
            // });
        })
        describe('InitialInvestment', () => {
            it('buys tokens in the correct proportions', async () => {
                const { fixedAllocation, owner, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(10)
                await fixedAllocation.initial_investment()

                expect(await tokenA.balanceOf(fixedAllocation)).to.equal(10) // 2 * (10 * 0.5)
                expect(await tokenB.balanceOf(fixedAllocation)).to.equal(20) // 4 * (10 * 0.5)
                expect(await wEth.balanceOf(fixedAllocation)).to.equal(0)
                expect(await tokenA.balanceOf(exchnageAddress)).to.equal(90)
                expect(await tokenB.balanceOf(exchnageAddress)).to.equal(80)
                expect(await wEth.balanceOf(exchnageAddress)).to.equal(10)
            })
            it('buys tokens in the correct proportions (2)', async () => {
                const { fixedAllocation, owner, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(20)
                await fixedAllocation.initial_investment()

                expect(await tokenA.balanceOf(fixedAllocation)).to.equal(20) // 2 * (20 * 0.5)
                expect(await tokenB.balanceOf(fixedAllocation)).to.equal(40) // 4 * (20 * 0.5)
                expect(await wEth.balanceOf(fixedAllocation)).to.equal(0)
                expect(await tokenA.balanceOf(exchnageAddress)).to.equal(80)
                expect(await tokenB.balanceOf(exchnageAddress)).to.equal(60)
                expect(await wEth.balanceOf(exchnageAddress)).to.equal(20)
            })
            it('buys tokens in the correct proportions when there have been multilpe deposits', async () => {
                const { fixedAllocation, owner, otherAccount, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
                await wEth.connect(otherAccount).approve(fixedAllocationAddress, TOTAL_SUPPLY)
                await wEth.transfer(otherAccount.address, 10)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(20)
                await fixedAllocation.connect(otherAccount).deposit(10)
                await fixedAllocation.initial_investment()

                expect(await tokenA.balanceOf(fixedAllocation)).to.equal(30) // 2 * (30 * 0.5)
                expect(await tokenB.balanceOf(fixedAllocation)).to.equal(60) // 4 * (30 * 0.5)
                expect(await wEth.balanceOf(fixedAllocation)).to.equal(0)
                expect(await tokenA.balanceOf(exchnageAddress)).to.equal(70)
                expect(await tokenB.balanceOf(exchnageAddress)).to.equal(40)
                expect(await wEth.balanceOf(exchnageAddress)).to.equal(30)
            })
            it('emits trade events with correct data', async () => {
                const { fixedAllocation, owner, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, addressA, addressB } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(20)
                const initialInvestmentPromise = fixedAllocation.initial_investment();
                expect(initialInvestmentPromise).to.emit(fixedAllocation, "Trade")
                    .withArgs(addressA, true, 10, 20);
                expect(initialInvestmentPromise).to.emit(fixedAllocation, "Trade")
                    .withArgs(addressB, true, 10, 40);
            })
            it('does not alter any balances if a signle trade cannot be performed', async () => {
                const { fixedAllocation, owner, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, addressA, addressB } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(100)

                expect(await tokenA.balanceOf(fixedAllocation)).to.equal(0)
                expect(await tokenB.balanceOf(fixedAllocation)).to.equal(0)
                expect(await wEth.balanceOf(fixedAllocation)).to.equal(100)
                expect(await tokenA.balanceOf(exchnageAddress)).to.equal(100)
                expect(await tokenB.balanceOf(exchnageAddress)).to.equal(100)
                expect(await wEth.balanceOf(exchnageAddress)).to.equal(0)

                expect(fixedAllocation.initial_investment()).to.revertedWithCustomError(wEth, "ERC20InsufficientBalance")

                expect(await tokenA.balanceOf(fixedAllocation)).to.equal(0)
                expect(await tokenB.balanceOf(fixedAllocation)).to.equal(0)
                expect(await wEth.balanceOf(fixedAllocation)).to.equal(100)
                expect(await tokenA.balanceOf(exchnageAddress)).to.equal(100)
                expect(await tokenB.balanceOf(exchnageAddress)).to.equal(100)
                expect(await wEth.balanceOf(exchnageAddress)).to.equal(0)
            })
            it('can only be called by the owner', async () => {
                const { fixedAllocation, owner, otherAccount, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress, addressA, addressB } = await loadFixture(deployBasicFixedAllocation);
                await tokenA.approve(owner.address, TOTAL_SUPPLY)
                await tokenB.approve(owner.address, TOTAL_SUPPLY)

                // Approve the fix allocation portfolio for our eth deposit
                await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)

                // Seed all the tokens into our mock exchange
                await tokenA.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)
                await tokenB.transferFrom(owner.address, exchnageAddress, TOTAL_SUPPLY)

                await fixedAllocation.deposit(10)

                expect(fixedAllocation.connect(otherAccount).initial_investment()).to.revertedWithCustomError(fixedAllocation, "OwnableUnauthorizedAccount")
            })
        })
        describe('TotalBalance', () => {
            it('gives value of 0 when no tokens are currently in the portfolio', async () => {
                const { fixedAllocation } = await loadFixture(deployBasicFixedAllocation);
                expect(await fixedAllocation.total_portfolio_base_balance()).to.equal(0)
            })
            // it('gives correct balance after an initial investment cycle', async () => {
            //     const { fixedAllocation, wEth, tokenA, tokenB, fixedAllocationAddress, exchnageAddress } = await loadFixture(deployBasicFixedAllocation);
            //     await tokenA.approve(exchnageAddress, TOTAL_SUPPLY)
            //     await tokenB.approve(exchnageAddress, TOTAL_SUPPLY)
            //     await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
            //     const amount = TOTAL_SUPPLY / 2
            //     // TODO: should look into change ethers balance at some point. 
            //     // can this be used in place of a mocked out wEth token accurately?
            //     await fixedAllocation.deposit(amount)
            //     await fixedAllocation.initial_investment()
            //     expect(await fixedAllocation.total_portfolio_base_balance()).to.equal(0)
            // })
        })
        it('throws not implemented error for rebalances', async () => {
            const { fixedAllocation } = await loadFixture(deployBasicFixedAllocation);
            await expect(fixedAllocation.rebalance()).to.be.revertedWithCustomError(fixedAllocation, 'NotImplemented')
        })
    })
});
