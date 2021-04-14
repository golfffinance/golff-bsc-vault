// ++++++++++++++++ Define Contracts ++++++++++++++++ 
const {FUNDATION_ADDRESS, BURN_ADDRESS, GOF_STRATEGY_MDEX_LP } = require('./config');
const knownContracts = require('./known-contracts');
const {writeLog} = require('./log');

const Controller = artifacts.require("GOFControllerV1");
const strategyForMdexLp = artifacts.require("StrategyForMdexLp");
// ++++++++++++++++  Main Migration ++++++++++++++++ 
const migration = async (deployer, network, accounts) => {
  await Promise.all([
    deploy(deployer, network),
  ]);
};

module.exports = migration;

// ++++++++++++++++  Deploy Functions ++++++++++++++++ 
async function deploy(deployer, network) {
    const deployments = {};
    const controller = await Controller.deployed();
    console.log(`[GOF] Deploy GofStrategy, controller:${controller.address}`);
    for await (const { pid, token, output, liquidityAToken, liquidityBToken, pool, router, hgofRouting, swap2LiquidityARouting, swap2LiquidityBRouting } of GOF_STRATEGY_MDEX_LP) {
        let tokenAddress = knownContracts[token][network];
        if (!tokenAddress) {
          throw new Error(`Address of ${token} is not registered on migrations/known-contracts.js!`);
        }
        let outputAddress = knownContracts[output][network];
        if (!outputAddress) {
          throw new Error(`Address of ${output} is not registered on migrations/known-contracts.js!`);
        }
        let liquidityATokenAddress = knownContracts[liquidityAToken][network];
        if (!liquidityATokenAddress) {
          throw new Error(`Address of ${liquidityAToken} is not registered on migrations/known-contracts.js!`);
        }
        let liquidityBTokenAddress = knownContracts[liquidityBToken][network];
        if (!liquidityBTokenAddress) {
          throw new Error(`Address of ${liquidityBToken} is not registered on migrations/known-contracts.js!`);
        }
        //  uint256 _pid, address _want, address _output, address _burnAddress
        await deployer.deploy(strategyForMdexLp, controller.address, pid, tokenAddress, outputAddress, liquidityATokenAddress, liquidityBTokenAddress, pool, router, BURN_ADDRESS);
        console.log(`[GOF] Deploy GofStrategy[${token}] = ${strategyForMdexLp.address}`);
        deployments[token] = strategyForMdexLp.address;

        console.log(`[GOF] set Routing`);

        let swap2GOFRouting = [];
        let swap2TokenARouting = [];
        let swap2TokenBRouting = [];

        for (var routing of hgofRouting) {
          swap2GOFRouting.push(knownContracts[routing][network]);
        }

        console.log(`[GOF] set Routing swap2GOFRouting ${swap2GOFRouting}`);

        for (var routing of swap2LiquidityARouting) {
          swap2TokenARouting.push(knownContracts[routing][network]);
        }

        for (var routing of swap2LiquidityBRouting) {
          swap2TokenBRouting.push(knownContracts[routing][network]);
        }

        console.log(`[GOF] set Routing swap2TokenRouting ${swap2TokenRouting}`);

        const strategyImpl = await strategyForMdexLp.deployed();
        
        await strategyImpl.setSwap2GOF(swap2GOFRouting);
        await strategyImpl.setSwap2AToken(swap2TokenARouting);
        await strategyImpl.setSwap2BToken(swap2TokenBRouting);

        console.log(`[GOF] set Routing end`)

    }
    await writeLog(deployments, 'strategy_mdex_lp', network);
}