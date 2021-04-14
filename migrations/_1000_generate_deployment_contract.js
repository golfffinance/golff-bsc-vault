const knownContracts = require('./known-contracts');
const { GOF_VAULT } = require('./config');

const fs = require('fs');
const path = require('path');
const util = require('util');
const { type } = require('io-ts');

const writeFile = util.promisify(fs.writeFile);

const ERC20 = artifacts.require("ERC20");

function strategyContracts() {
    return fs.readdirSync(path.resolve(__dirname, '../contracts/strategy'))
      .filter(filename => filename.startsWith('StrategyFor'))
      .map(filename => filename.replace('.sol', ''));
}

const exportedContracts = [
  'GOFControllerV1',
];

module.exports = async (deployer, network, accounts) => {
  const deployments = {};

  for (const name of exportedContracts) {
    const contract = artifacts.require(name);
    deployments[name] =  contract.address
  }

  const vaultsDeployments = require(`../build/deployments.vaults.${network}`);
  const strategyLavaDeployments = require(`../build/deployments.strategy_mdex.${network}`);
  for await (const { token, symbol, earnLowerlimit } of GOF_VAULT) {
      let tokenAddress = knownContracts[token][network];
      if (!tokenAddress) {
        throw new Error(`Address of ${token} is not registered on migrations/known-contracts.js!`);
      }
      let key = token.toLowerCase();
      
      let tokenContract = await ERC20.at(tokenAddress);
      let decimals = await tokenContract.decimals();
      console.log(`token = ${tokenAddress}  decimals = ${decimals}`)
      deployments[key] = {};
      deployments[key]['tokenAddress'] = tokenAddress;
      deployments[key]['tokenDecimals'] = parseInt(decimals.toString());
      deployments[key]['earnedMiddleToken'] = key;
      deployments[key]['earnedMiddleAddress'] = tokenAddress;
      deployments[key]['earnContractAddress'] = vaultsDeployments[token];
      deployments[key]['strategyContractAddress'] = strategyLavaDeployments[token]||strategyLendDeployments[token];
  }
  const deploymentPath = path.resolve(__dirname, `../deployments/${network}.json`);
  await writeFile(deploymentPath, JSON.stringify(deployments, null, 2));

  console.log(`Exported deployments into ${deploymentPath}`);
};
