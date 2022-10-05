import { expect } from "chai";
import { Wallet, Provider, Contract, utils } from "zksync-web3";
import * as hre from "hardhat";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { BigNumber, ethers } from "ethers";
import deployPaymaster from "../deploy/deploy-paymaster";

const RICH_WALLET_PK =
  "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110";

describe("Paymaster", () => {
  const deployErc20 = async (wallet: Wallet): Promise<Contract> => {
    const deployer = new Deployer(hre, wallet);
    const erc20Artifact = await deployer.loadArtifact("MyERC20");
    const erc20 = await deployer.deploy(erc20Artifact, [
      "MyToken",
      "MyToken",
      18,
    ]);

    return erc20;
  };

  const deployCustomPaymaster = async (wallet: Wallet): Promise<Contract> => {
    const deployer = new Deployer(hre, wallet);
    const paymasterArtifact = await deployer.loadArtifact("CustomPaymaster");
    const paymaster = await deployer.deploy(paymasterArtifact, [
      wallet.address,
    ]);

    return paymaster;
  };

  const fundPaymaster = async (
    wallet: Wallet,
    paymaster: Contract,
    amount: BigNumber
  ) => {
    const deployer = new Deployer(hre, wallet);
    await (
      await deployer.zkWallet.sendTransaction({
        to: paymaster.address,
        value: amount,
      })
    ).wait();
  };

  it("using paymaster for fees in erc20", async () => {
    const provider = Provider.getDefaultProvider();
    const wallet = new Wallet(RICH_WALLET_PK, provider);
    const erc20 = await deployErc20(wallet);
    const paymaster = await deployCustomPaymaster(wallet);
    await fundPaymaster(wallet, paymaster, ethers.utils.parseEther("1"));

    // mint plenty of erc20 to wallet
    await erc20.mint(wallet.address, ethers.utils.parseEther("100"));

    const emptyWallet = Wallet.createRandom();
    expect((await erc20.balanceOf(emptyWallet.address)).toString()).to.equal(
      "0"
    ); // how to compare bignumber??

    // whitelist token
    const setWhitelistTx = await paymaster
      .connect(wallet)
      .setWhitelistToken(erc20.address, true);
    await setWhitelistTx.wait();
    expect(await paymaster.whiteListedErc20s(erc20.address)).to.equal(true);

    const approvalTokenTx = await erc20
      .connect(wallet)
      .approve(paymaster.address, ethers.constants.MaxUint256);
    await approvalTokenTx.wait();

    // eth balance before
    const ethBalanceBefore = await wallet.getBalance();

    // Encoding the "ApprovalBased" paymaster flow's input
    const paymasterParams = utils.getPaymasterParams(paymaster.address, {
      type: "ApprovalBased",
      token: erc20.address,
      minimalAllowance: ethers.BigNumber.from(1),
      innerInput: new Uint8Array(),
    });

    await (
      await erc20.mint(emptyWallet.address, 100, {
        customData: {
          paymasterParams,
          ergsPerPubdata: utils.DEFAULT_ERGS_PER_PUBDATA_LIMIT,
        },
      })
    ).wait();

    expect((await erc20.balanceOf(emptyWallet.address)).toString()).to.equal(
      "100"
    );

    expect((await wallet.getBalance()).toString()).to.equal(ethBalanceBefore.toString());
  });
});
