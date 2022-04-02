import { ethers } from "hardhat"
import { expect } from "chai"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

import { MasterChefPoint } from "../types/MasterChefPoint"
import { ERC20Test } from "../types/ERC20Test"

import { advanceBlock, height } from "./utils"

describe("MasterChefPoint", function () {
    let lp: ERC20Test
    let chef: MasterChefPoint
    let owner: SignerWithAddress
    let alice: SignerWithAddress
    let bob: SignerWithAddress

    before(async function () {
        ;[owner, alice, bob] = await ethers.getSigners()

        const lpFactory = await ethers.getContractFactory("ERC20Test")
        lp = (await lpFactory.connect(owner).deploy("Test LP", "TLP")) as ERC20Test
        await lp.connect(owner).transfer(alice.address, "100000000")
        await lp.connect(owner).transfer(bob.address, "200000000")

        const facory = await ethers.getContractFactory("MasterChefPoint")
        chef = (await facory.connect(owner).deploy(100)) as MasterChefPoint
        await chef.connect(owner).add(1, lp.address)

        await lp.connect(alice).approve(chef.address, "10000000000")
        await lp.connect(bob).approve(chef.address, "10000000000")
    })

    it("basic farm", async function () {
        await chef.connect(alice).deposit(0, "10000000", alice.address)
        expect("0").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("0").to.equal((await chef.totalPoints()).toString())

        await advanceBlock()
        expect("100").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("100").to.equal((await chef.totalPoints()).toString())

        await chef.connect(bob).deposit(0, "10000000", bob.address)
        await advanceBlock()
        expect("250").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("50").to.equal((await chef.pendingPoint(0, bob.address)).toString())

        const currentHeight = await height()
        await chef.connect(owner).terminate(currentHeight.add(5))
        await advanceBlock()

        expect("350").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("150").to.equal((await chef.pendingPoint(0, bob.address)).toString())

        await chef.connect(bob).deposit(0, "30000000", bob.address)
        expect("400").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("200").to.equal((await chef.pendingPoint(0, bob.address)).toString())

        await advanceBlock()
        await advanceBlock()
        await advanceBlock()
        await advanceBlock()
        expect("440").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("360").to.equal((await chef.pendingPoint(0, bob.address)).toString())

        await chef.updatePool(0)
        expect("440").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("360").to.equal((await chef.pendingPoint(0, bob.address)).toString())

        await expect(chef.connect(bob).deposit(0, "10000000", bob.address)).to.be.revertedWith(
            'MasterChefPoint: farm have closed'
        )
        await chef.connect(alice).withdraw(0, "10000000", alice.address)
        expect("100000000").to.equal((await lp.balanceOf(alice.address)).toString())
        expect("440").to.equal((await chef.pendingPoint(0, alice.address)).toString())
        expect("360").to.equal((await chef.pendingPoint(0, bob.address)).toString())
    })
})
