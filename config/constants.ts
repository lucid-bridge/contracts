import { BigNumber } from "ethers";

type CHAIN_IDS_TYPE = {
  ETHEREUM: {
    MAINNET: BigNumber;
    RINKEBY: BigNumber;
    GOERLI: BigNumber;
    KOVAN: BigNumber;
  };

  OPTIMISM: {
    OPTIMISM_MAINNET: BigNumber;
    OPTIMISM_TESTNET: BigNumber;
  };
};

export const CHAIN_IDS: CHAIN_IDS_TYPE = {
  ETHEREUM: {
    MAINNET: BigNumber.from("1"),
    RINKEBY: BigNumber.from("4"),
    GOERLI: BigNumber.from("5"),
    KOVAN: BigNumber.from("42"),
  },

  OPTIMISM: {
    OPTIMISM_MAINNET: BigNumber.from("10"),
    OPTIMISM_TESTNET: BigNumber.from("69"),
  },
};
