import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

const TOTAL_SUPPLY = 100

describe("FixedAllocation", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployBasicFixedAllocation() {
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount] = await hre.ethers.getSigners();

        const Token = await hre.ethers.getContractFactory("Token");
        const wEth = await Token.deploy('Weth', "WETH", TOTAL_SUPPLY);
        const tokenA = await Token.deploy('TokenA', "TKA", TOTAL_SUPPLY);
        const tokenB = await Token.deploy('TokenB', "TKB", TOTAL_SUPPLY);
        const [addressA, addressB, wethAddress] = await Promise.all([
            tokenA.getAddress(),
            tokenB.getAddress(),
            wEth.getAddress()
        ])
        const FixedAllocation = await hre.ethers.getContractFactory("FixedAllocation");
        const fixedAllocation = await FixedAllocation.deploy(wethAddress, addressA, addressB)
        const fixedAllocationAddress = await fixedAllocation.getAddress();
        return { tokenA, tokenB, owner, otherAccount, fixedAllocation, addressA, addressB, wethAddress, wEth, fixedAllocationAddress };
    }

    describe('FixedAllocation', () => {
        it('Should set constructor properties correctly', async () => {
            const { tokenA, tokenB, fixedAllocation, addressA, addressB, wethAddress } = await loadFixture(deployBasicFixedAllocation);
            expect(await tokenA.totalSupply()).to.equal(TOTAL_SUPPLY);
            expect(await tokenB.totalSupply()).to.equal(TOTAL_SUPPLY);
            expect(await fixedAllocation.proportions(addressA)).to.equal(50n)
            expect(await fixedAllocation.proportions(addressB)).to.equal(50n)
            expect(await fixedAllocation.total_depoisted()).to.equal(0n)
            expect(await fixedAllocation.base_token()).to.equal(wethAddress)
        })
        it('increments the total deposited amount and the deposits map when a deposit is made', async () => {
            const { fixedAllocation, fixedAllocationAddress, owner, wEth } = await loadFixture(deployBasicFixedAllocation);
            await wEth.approve(fixedAllocationAddress, TOTAL_SUPPLY)
            await fixedAllocation.deposit(1)
            expect(await fixedAllocation.total_depoisted()).to.equal(1)
            expect(await fixedAllocation.deposits(owner)).to.equal(1)
        })
    })
});
