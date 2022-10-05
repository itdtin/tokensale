import { utils, Wallet } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";


// Before run deploy you must set PrimaryKey of the deployer wallet and token address
// The HardCap of token sale will be calculated automatically via TOKEN_PER_NATIVE and token balance of the contract when you startSale

export default async function (hre: HardhatRuntimeEnvironment) {
    console.log(`Running deploy script for the TokenSale contract`);

    const walletPrimaryKey = "" //ToDo PK
    const tokenAdddress = "0xf4c9913282E45AF9694Bc247C4952E4a762A2Cb6" //todo token address,

    // Todo Sale params
    const minReserve = ethers.utils.parseEther("0.0005")
    const maxReserve = ethers.utils.parseEther("2.5")
    const tokensPerNative = ethers.utils.parseEther("1000")
    const vestingPeriodCounter = 86400; // 1 day
    const vestingPeriod = 86400 * 100; // 100 days
    const lockPeriod = 86400 * 5; // 5 days

    // Initialize the wallet.
    const wallet = new Wallet(walletPrimaryKey);

    // Create deployer object and load the artifact of the contract we want to deploy.
    const deployer = new Deployer(hre, wallet);
    const artifact = await deployer.loadArtifact("TokenSale");

    // Deposit some funds to L2 in order to be able to perform L2 transactions.
    const depositAmount = ethers.utils.parseEther("0.001");
    const depositHandle = await deployer.zkWallet.deposit({
        to: deployer.zkWallet.address,
        token: utils.ETH_ADDRESS,
        amount: depositAmount,
    });
    // Wait until the deposit is processed on zkSync
    await depositHandle.wait();

    const saleContract = await deployer.deploy(artifact, [
        tokenAdddress,
        minReserve,
        maxReserve,
        tokensPerNative,
        vestingPeriod,
        vestingPeriodCounter,
        lockPeriod
    ]);

    // Show the contract info.
    const contractAddress = saleContract.address;
    console.log(`${artifact.contractName} was deployed to ${contractAddress}`);

    console.log("Constructor params ABI: ", saleContract.interface.encodeDeploy([
        tokenAdddress,
        minReserve,
        maxReserve,
        tokensPerNative,
        vestingPeriod,
        vestingPeriodCounter,
        lockPeriod
    ]))
}