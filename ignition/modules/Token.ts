import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TokenModule = buildModule("Token", (m) => {
    const token = m.contract("Token", ['TokenA', "TKA", 100]);
    return { erc20: token };
});

export default TokenModule;
