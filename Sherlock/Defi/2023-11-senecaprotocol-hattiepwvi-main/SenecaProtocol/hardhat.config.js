require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  etherscan: {
    apiKey: "8143XKS22PEPU2HRFGT2MY34JRE4XFYHSN",
  },
  networks:{
    goerli:{
      url: "https://eth-goerli.g.alchemy.com/v2/nzn28-MdP1oHc_-NUZjhDnKvwYwKO6b3",
      accounts: [process.env.PRIVATE_KEY]
    },
    hardhat:{
      forking:{
        url: "https://ethereum-goerli.publicnode.com",
        accounts: [process.env.PRIVATE_KEY]
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
  }
};
