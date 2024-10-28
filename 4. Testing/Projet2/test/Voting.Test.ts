import { expect, assert } from "chai";
import hre from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers"; 
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Voting } from "../typechain-types";

describe("Test Voting", function(){
    let owner: HardhatEthersSigner
    let addr1: HardhatEthersSigner
    let addr2: HardhatEthersSigner
    let addr3: HardhatEthersSigner
    let deployedContract: Voting

    // ::::::::::::: Fixtures ::::::::::::: // 
    //Deployment fixture
    async function deployVotingFixture(){
        [owner, addr1, addr2, addr3] = await hre.ethers.getSigners()
        deployedContract = await hre.ethers.deployContract("Voting")
        return {deployedContract, owner, addr1, addr2, addr3}
    }

    //Deployment + proposals added
    async function deployUpToVotingEnabledFixture(){
        ({owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
        await deployedContract.addVoter(addr1.address)
        await deployedContract.addVoter(addr2.address)
        await deployedContract.addVoter(addr3.address)
        await deployedContract.startProposalsRegistering()
        await deployedContract.connect(addr1).addProposal("prop1")
        await deployedContract.connect(addr2).addProposal("prop2")
        await deployedContract.connect(addr3).addProposal("prop3")
        await deployedContract.endProposalsRegistering()
        await deployedContract.startVotingSession()
        return {deployedContract, owner, addr1, addr2, addr3}
    }

    //Deployment  + votes performed
    async function deployUpToVotedFixture(){
        ({owner, addr1, addr2, addr3} = await loadFixture(deployUpToVotingEnabledFixture))
        await deployedContract.connect(addr1).setVote("1")
        await deployedContract.connect(addr2).setVote("2")
        await deployedContract.connect(addr3).setVote("1")
        return {deployedContract, owner, addr1, addr2, addr3}
    }

    // ::::::::::::: Testing contract deployment ::::::::::::: // 
    describe("Initialization", function(){
        it("should deploy the contract and the address deploying the contract should be the owner", async function(){
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
            const theOwner = await deployedContract.owner()
            assert (theOwner == owner.address)
        })
    })

    // ::::::::::::: Testing Voters Registration ::::::::::::: // 
    describe("addVoter", function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
        })

        it("should revert if another adress from the contract owner's is trying to register a voter", async function(){
            await expect(deployedContract.connect(addr1).startProposalsRegistering())
            .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
            .withArgs(addr1.address)
        })

        it("should revert if registration is not open", async function(){
            await deployedContract.startProposalsRegistering()
            await expect(deployedContract.addVoter(addr1.address)).to.be.revertedWith("Voters registration is not open yet")
        })

        it("should emit event and register address to true", async function(){
            await expect(deployedContract.addVoter(addr1.address)).to.emit(deployedContract, "VoterRegistered").withArgs(addr1.address)
            const voter = await deployedContract.connect(addr1).getVoter(addr1.address)
            assert(voter.isRegistered == true)
        })

        it("should revert if the address is already registered", async function(){
            await deployedContract.addVoter(addr1.address)
            await expect(deployedContract.addVoter(addr1.address)).to.be.revertedWith("Already registered")
        })
    })


    // ::::::::::::: Testing Getters ::::::::::::: // 

    describe ("Getters",function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
        })     
        

        describe("getVoter",function(){
            it("should revert if a non registered address is trying to pull voters info", async function(){
                await expect(deployedContract.connect(addr1).getVoter(addr2.address)).to.be.revertedWith("You're not a voter")
            })

            it("should return a voter", async function(){
                await deployedContract.addVoter(addr1.address)
                const voter = await deployedContract.connect(addr1).getVoter(addr1.address)
                assert(voter.isRegistered == true)
                assert(voter.hasVoted == false)
                assert(voter.votedProposalId == 0n)
            })
        })

        describe("getOneProposal", function(){
            it("should revert if a non registered address is trying to view a proposal", async function(){
                await expect(deployedContract.connect(addr1).getOneProposal(addr2.address)).to.be.revertedWith("You're not a voter")
            })

            it("should return a proposal", async function(){
                await deployedContract.addVoter(addr1.address)
                await deployedContract.startProposalsRegistering()
                const proposal = await deployedContract.connect(addr1).getOneProposal(0)
                assert (proposal.description == "GENESIS")
                assert (proposal.voteCount == 0n)
            })
        })
    })

    // ::::::::::::: Testing States ::::::::::::: // 
    describe("States", function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
        })

        //startProposalsRegistering
        describe("startProposalsRegistering", function(){
            it("should revert if startProposalsRegistering is called by a different address from the owner", async function(){
                await expect(deployedContract.connect(addr1).startProposalsRegistering())
                .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
                .withArgs(addr1.address)
            })
    
            it("should revert if workFlowStatus is not in RegisteringVoters state", async function(){
                await deployedContract.startProposalsRegistering()
                await expect(deployedContract.startProposalsRegistering()).to.be.revertedWith("Registering proposals cant be started now")
            })
    
            
            it("should emit WorkflowStatusChange event and assign GENESIS proposal", async function(){
                await deployedContract.addVoter(addr1.address)
                await expect(deployedContract.startProposalsRegistering()).to.emit(deployedContract, "WorkflowStatusChange").withArgs(0, 1)
                const proposal = await deployedContract.connect(addr1).getOneProposal(0)
                assert (proposal.description == "GENESIS")
            })
        })

        //endProposalsRegistering
        describe("endProposalsRegistering", function(){
            it("should revert if endProposalsRegistering is called by a different address from the owner", async function(){
                await expect(deployedContract.connect(addr1).endProposalsRegistering())
                .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
                .withArgs(addr1.address)
            })
    
            it("should revert if workFlowStatus is not in ProposalsRegistrationStarted state", async function(){
                await expect(deployedContract.endProposalsRegistering()).to.be.revertedWith("Registering proposals havent started yet")
            })
    
            
            it("should emit WorkflowStatusChange event", async function(){
                await deployedContract.startProposalsRegistering()
                await expect(deployedContract.endProposalsRegistering()).to.emit(deployedContract, "WorkflowStatusChange").withArgs(1, 2)
            })
        })

        //startVotingSession
        describe("startVotingSession", function(){
            it("should revert if startVotingSession is called by a different address from the owner", async function(){
                await expect(deployedContract.connect(addr1).startVotingSession())
                .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
                .withArgs(addr1.address)
            })
    
            it("should revert if workFlowStatus is not in ProposalsRegistrationEnded state", async function(){
                await expect(deployedContract.startVotingSession()).to.be.revertedWith("Registering proposals phase is not finished")
            })
    
            
            it("should emit WorkflowStatusChange event", async function(){
                await deployedContract.startProposalsRegistering()
                await deployedContract.endProposalsRegistering()
                await expect(deployedContract.startVotingSession()).to.emit(deployedContract, "WorkflowStatusChange").withArgs(2, 3)
            })
        })

        //endVotingSession
        describe("endVotingSession", function(){
            it("should revert if endVotingSession is called by a different address from the owner", async function(){
                await expect(deployedContract.connect(addr1).endVotingSession())
                .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
                .withArgs(addr1.address)
            })
    
            it("should revert if workFlowStatus is not in VotingSessionStarted state", async function(){
                await expect(deployedContract.endVotingSession()).to.be.revertedWith("Voting session havent started yet")
            })
    
            
            it("should emit WorkflowStatusChange event", async function(){
                await deployedContract.startProposalsRegistering()
                await deployedContract.endProposalsRegistering()
                await deployedContract.startVotingSession()
                await expect(deployedContract.endVotingSession()).to.emit(deployedContract, "WorkflowStatusChange").withArgs(3, 4)
            })
        })

    })

    // ::::::::::::: PROPOSAL ::::::::::::: // 
    describe("addProposal", function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
            await deployedContract.addVoter(addr1.address)
        })
        
        it("should revert if addProposal is called by an unregistered address", async function(){
            await expect(deployedContract.addProposal('my proposal')).to.be.revertedWith("You're not a voter")
        })

        it("should revert if workflowStatus is not in ProposalsRegistrationStarted state", async function(){
            await expect(deployedContract.connect(addr1).addProposal('my proposal')).to.be.revertedWith("Proposals are not allowed yet")
        })

        
        it("should revert if nothing is inlcuded in the proposal", async function(){
            await deployedContract.startProposalsRegistering()
            await expect(deployedContract.connect(addr1).addProposal("")).to.be.revertedWith("Vous ne pouvez pas ne rien proposer")
        })

        it("should add a proposal and emit ProposalRegistered event", async function(){
            await deployedContract.startProposalsRegistering()
            await expect(deployedContract.connect(addr1).addProposal("my proposal")).to.emit(deployedContract, "ProposalRegistered").withArgs(1)
            const newProposal = await deployedContract.connect(addr1).getOneProposal(1)
            assert(newProposal.description === "my proposal")
        })

    })

    // ::::::::::::: VOTE ::::::::::::: //
    describe("Vote", function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployVotingFixture))
            await loadFixture(deployUpToVotingEnabledFixture)
        })
        
        it("Only voters should be able to vote", async function(){
            await expect(deployedContract.setVote(1)).to.be.revertedWith("You're not a voter")
        })

        it("should revert if workflowStatus is not in VotingSessionStarted state", async function(){
            await deployedContract.endVotingSession()
            await expect(deployedContract.connect(addr1).setVote(1)).to.be.revertedWith("Voting session havent started yet")
        })

        it("should revert if address has already voted", async function(){
            deployedContract.connect(addr1).setVote(1)
            await expect(deployedContract.connect(addr1).setVote(1)).to.be.revertedWith("You have already voted")
        })

        it("should revert if voting for a proposal id out of nange", async function(){
            await expect(deployedContract.connect(addr1).setVote(10)).to.be.revertedWith("Proposal not found")
        })

        it("should add vote and emit event", async function(){
            await expect(deployedContract.connect(addr1).setVote(1)).to.emit(deployedContract, "Voted").withArgs(addr1.address, 1)
            const voter = await deployedContract.connect(addr1).getVoter(addr1.address)
            const votedProp = voter.votedProposalId
            const votedBool = voter.hasVoted
            assert (votedProp === 1n)
            assert(votedBool === true)
        })
    })

    // ::::::::::::: TALLY VOTES ::::::::::::: //
    describe("tallyVotes", function(){
        beforeEach(async ()=>{
            ({deployedContract, owner, addr1, addr2, addr3} = await loadFixture(deployUpToVotedFixture))
        })
        
        it("should revert if not the owner calls the function", async function(){
            await deployedContract.endVotingSession()
            await expect(deployedContract.connect(addr1).tallyVotes())
            .to.be.revertedWithCustomError(deployedContract,"OwnableUnauthorizedAccount")
            .withArgs(addr1.address)
        })

        it("should revert if workFlowStatus not in VotingSessionEnded", async function(){
            await expect(deployedContract.tallyVotes()).to.be.revertedWith("Current status is not voting session ended")
        })

        it("should set the winning proposal and emit WorkflowStatusChange event", async function(){
            await deployedContract.endVotingSession()
            await expect(deployedContract.tallyVotes()).to.emit(deployedContract, "WorkflowStatusChange").withArgs(4, 5)
            const winningPropId = await deployedContract.winningProposalID()
            assert(winningPropId == 1n)
        })

        
    })

})