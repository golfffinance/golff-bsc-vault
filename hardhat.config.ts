import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

import * as fs from 'fs';
import * as path from 'path';
import * as util from 'util';


// const secretPath = path.resolve(__dirname, '.secret');
const mnemonic = fs.readFileSync('.secret').toString().trim();

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    mainnet: {
      url: "https://bsc-dataseed1.binance.org",
      accounts: [mnemonic]
    },
    testnet:{
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      accounts: [mnemonic]
    },
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: './build/cache',
    artifacts: './build/artifacts',
  },
  mocha: {
    timeout: 20000
  },
  gasReporter: {
    currency: 'USD',
    enabled: true,
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: '',
  }
}

