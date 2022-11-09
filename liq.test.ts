import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Immutables, State } from "./types";
import { FeeAmount, nearestUsableTick, NonfungiblePositionManager, Pool, Position } from "@uniswap/v3-sdk";
import { CurrencyAmount, Percent, Token } from "@uniswap/sdk-core";
import { ERC20, ERC721Enumerable, IUniswapV3Pool, NFTPM } from "../typechain-types";
import { Contract } from "ethers";



describe("UniswapV3", function () {

    async function getPoolImmutables(poolContract: IUniswapV3Pool): Promise <Immutables> {
        const [factory, token0, token1, fee, tickSpacing, maxLiquidityPerTick] = await Promise.all([
            poolContract.factory(),
            poolContract.token0(),
            poolContract.token1(),
            poolContract.fee(),
            poolContract.tickSpacing(),
            poolContract.maxLiquidityPerTick(),
        ])

        const immutables: Immutables = {
            factory,
            token0,
            token1,
            fee,
            tickSpacing,
            maxLiquidityPerTick,
        }
        return immutables
    }
    async function getPoolState(poolContract: IUniswapV3Pool): Promise<State> {
        const [liquidity, slot] = await Promise.all([poolContract.liquidity(), poolContract.slot0()])

        const poolState: State = {
            liquidity,
            sqrtPriceX96: slot[0],
            tick: slot[1],
            observationIndex: slot[2],
            observationCardinality: slot[3],
            observationCardinalityNext: slot[4],
            feeProtocol: slot[5],
            unlocked: slot[6],
        }

        return poolState
    }
    const NFT_POSITON_MANAGER = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
    const UNISWAP_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    const DAI_HOLDER = "0xb527a981e1d415AF696936B3174f2d7aC8D11369"
    const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    const WETH_HOLDER = "0x06920C9fC643De77B99cB7670A944AD31eaAA260"
    const deadline = '1000000000000000000';
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function setup() {
        const [user1, user2, user3, user4] = await ethers.getSigners();
        await user3.sendTransaction({to:DAI_HOLDER, value: ethers.utils.parseEther("100")})
        await user3.sendTransaction({to:WETH_HOLDER, value: ethers.utils.parseEther("100")})
        const daiToken: Token = new Token(1, DAI, 18);
        const wethToken: Token = new Token(1, WETH, 18);
        const weth: ERC20 = await ethers.getContractAt("ERC20", WETH)
        const dai: ERC20 = await ethers.getContractAt("ERC20", DAI)
        const poolAddress = Pool.getAddress(daiToken, wethToken, FeeAmount.MEDIUM);
        const poolContract: IUniswapV3Pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress,)
        const nftPositionManager: NFTPM = await ethers.getContractAt("NFTPM", NFT_POSITON_MANAGER,)
        const [immutables, state] = await Promise.all([getPoolImmutables(poolContract), getPoolState(poolContract)])
        
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [DAI_HOLDER],
        });
        const dai_holder_signer = await ethers.getSigner(DAI_HOLDER)
        await (await dai.connect(dai_holder_signer).transfer(user1.address, dai.balanceOf(DAI_HOLDER))).wait()
        
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [WETH_HOLDER],
        });
        
        const weth_holder_signer = await ethers.getSigner(WETH_HOLDER)
        await (await weth.connect(weth_holder_signer).transfer(user1.address, weth.balanceOf(WETH_HOLDER))).wait()


        const user1DAIBalance = await dai.balanceOf(user1.address)
        const user1WETHBalance = await weth.balanceOf(user1.address)

        await (await dai.connect(user1).approve(NFT_POSITON_MANAGER, user1DAIBalance)).wait()
        await (await weth.connect(user1).approve(NFT_POSITON_MANAGER, user1WETHBalance)).wait()



        const pool = new Pool(
            daiToken,
            wethToken,
            immutables.fee,
            state.sqrtPriceX96.toString(),
            state.liquidity.toString(),
            state.tick
        )
        
        return { daiToken, wethToken, poolContract, state, immutables, pool, user1, user2, dai, weth, poolAddress, nftPositionManager };
    }

    describe("Deployment", function () {

        // it("Test Mint", async function () {
        //     const { dai, weth, pool, state, immutables, user1, poolAddress } = await loadFixture(setup)
        //     // const { user1 } = await loadFixture(setup)
        //     const position = new Position({
        //         pool: pool,
        //         liquidity: parseInt(state.liquidity.toString()) * 0.02,
        //         tickLower: nearestUsableTick(state.tick, immutables.tickSpacing) - immutables.tickSpacing * 2,
        //         tickUpper: nearestUsableTick(state.tick, immutables.tickSpacing) + immutables.tickSpacing * 2,
        //     })
        //     const { calldata, value } = NonfungiblePositionManager.addCallParameters(position, {
        //         slippageTolerance: new Percent(50, 10_000),
        //         deadline: '1000000000000000000',
        //         recipient: user1.address,

        //     })
        //     await user1.sendTransaction({
        //         to: NFT_POSITON_MANAGER,
        //         data: calldata,
        //         value: 0,
        //     });
            
        // });

        it("Test Burn", async function () {
            const { dai, weth, pool, state, immutables, user1, poolAddress, daiToken, wethToken, nftPositionManager } = await loadFixture(setup)
            // const { user1 } = await loadFixture(setup)
            const position = new Position({
                pool: pool,
                liquidity: parseInt(state.liquidity.toString()) * 0.02,
                tickLower: nearestUsableTick(state.tick, immutables.tickSpacing) - immutables.tickSpacing * 2,
                tickUpper: nearestUsableTick(state.tick, immutables.tickSpacing) + immutables.tickSpacing * 2,
            })
            const { calldata, value } = NonfungiblePositionManager.addCallParameters(position, {
                slippageTolerance: new Percent(50, 10_000),
                deadline,
                recipient: user1.address,

            })
            const txResponse = await user1.sendTransaction({
                to: NFT_POSITON_MANAGER,
                data: calldata,
                value,
            });
            // Minted position
            let positionAtToken = await nftPositionManager.positions(await nftPositionManager.tokenOfOwnerByIndex(user1.address, 0))
            console.log(positionAtToken);
            
            const params = {
                tokenId: await nftPositionManager.tokenOfOwnerByIndex(user1.address, 0),
                liquidity: positionAtToken.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline
            }
            
            await nftPositionManager.decreaseLiquidity(params)
            positionAtToken = await nftPositionManager.positions(await nftPositionManager.tokenOfOwnerByIndex(user1.address, 0))
            console.log(positionAtToken);

            // 357106
            // const removeParams = NonfungiblePositionManager.removeCallParameters(position, {
            //     tokenId: 357106,
            //     liquidityPercentage: new Percent(10),
            //     slippageTolerance: new Percent(50, 50),
            //     deadline: "1000000000000000000",
            //     collectOptions: {
            //         expectedCurrencyOwed0: CurrencyAmount.fromRawAmount(daiToken, 0),
            //         expectedCurrencyOwed1: CurrencyAmount.fromRawAmount(wethToken, 0),
            //         recipient: user1.address,
            //     },
            // })
            
            // const txResponseRemove = await user1.sendTransaction({
            //     to: NFT_POSITON_MANAGER,
            //     data: removeParams.calldata,
            //     value: removeParams.value,
            // });
            
            
        });
    });
});