// ++++++++++++++++ Define Contracts ++++++++++++++++ 
const {FUNDATION_ADDRESS, BURN_ADDRESS, GOF_STRATEGY_VENUS } = require('./config');
const knownContracts = require('./known-contracts');
const {writeLog} = require('./log');

const Controller = artifacts.require("GOFControllerV1");
const strategyForVenus = artifacts.require("StrategyForVenus");
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
    for await (const { token, output, pool, router, hgofRouting, tokenRouting } of GOF_STRATEGY_VENUS) {
        let tokenAddress = knownContracts[token][network];
        if (!tokenAddress) {
          throw new Error(`Address of ${token} is not registered on migrations/known-contracts.js!`);
        }
        let outputAddress = knownContracts[output][network];
        if (!outputAddress) {
          throw new Error(`Address of ${output} is not registered on migrations/known-contracts.js!`);
        }
        //  uint256 _pid, address _want, address _output, address _burnAddress
        await deployer.deploy(strategyForVenus, controller.address, tokenAddress, outputAddress, pool, router, BURN_ADDRESS);
        console.log(`[GOF] Deploy GofStrategy[${token}] = ${strategyForVenus.address}`);
        deployments[token] = strategyForVenus.address;

        console.log(`[GOF] set Routing`);

        let swap2GOFRouting = [];
        let swap2TokenRouting = [];

        for (var routing of hgofRouting) {
          swap2GOFRouting.push(knownContracts[routing][network]);
        }

        console.log(`[GOF] set Routing swap2GOFRouting ${swap2GOFRouting}`);

        for (var routing of tokenRouting) {
          swap2TokenRouting.push(knownContracts[routing][network]);
        }

        console.log(`[GOF] set Routing swap2TokenRouting ${swap2TokenRouting}`);

        const strategyImpl = await strategyForVenus.deployed();
        
        await strategyImpl.setSwap2GOF(swap2GOFRouting);
        await strategyImpl.setSwap2Token(swap2TokenRouting);

        console.log(`[GOF] set Routing end`)

    }
    await writeLog(deployments, 'strategy_venus', network);
}