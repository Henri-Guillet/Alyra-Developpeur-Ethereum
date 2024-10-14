// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable{

    // ----------- Data Types -----------
    struct Voter{
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal{
        string description;
        uint voteCount;
    }

    enum WorkflowStatus { 
        RegisteringVoters, 
        ProposalsRegistrationStarted, 
        ProposalsRegistrationEnded, 
        VotingSessionStarted, 
        VotingSessionEnded, 
        VotesTallied 
    }

    // ----------- State Variables -----------

    mapping(address => Voter) private voters;
    Proposal[] public proposals;
    WorkflowStatus public votingStatus;
    uint public winningProposalId;

    // ----------- Events -----------
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);

    // ----------- Errors -----------

    error AddressNotWhitelisted(address add);
    error WrongVotingPhase(WorkflowStatus expected, WorkflowStatus current);

    // ----------- Modifiers -----------

    modifier onlyWhitelisted{
        if(!voters[msg.sender].isRegistered){
            revert AddressNotWhitelisted(msg.sender);
        }
        _;
    }

    modifier checkVotingPhase(WorkflowStatus expectedPhase) {
        if (votingStatus != expectedPhase) {
            revert WrongVotingPhase(expectedPhase, votingStatus);
        }
        _;
    }

    modifier updateWorkflow(WorkflowStatus previousPhase, WorkflowStatus nextPhase) {
        // Check if the workflow is in the correct phase before moving to the next
        if (votingStatus != previousPhase) {
            revert WrongVotingPhase(previousPhase, votingStatus);
        }
        votingStatus = nextPhase;
        emit WorkflowStatusChange(previousPhase, nextPhase);
        _;
    }


    // ----------- Constructor ----------- 

    constructor() Ownable(msg.sender){

    }

    // ----------- Voting Workflow -----------

    function startProposalRegistration() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.RegisteringVoters, WorkflowStatus.ProposalsRegistrationStarted){
    }

    function endProposalRegistration() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.ProposalsRegistrationStarted, WorkflowStatus.ProposalsRegistrationEnded){
    }

    function startVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.ProposalsRegistrationEnded, WorkflowStatus.VotingSessionStarted){
    }

    function endVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.VotingSessionStarted, WorkflowStatus.VotingSessionEnded){
    }


    // ----------- Voter Management functions -----------

    function addToWhitelist(address[] calldata _addressArray) external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.RegisteringVoters){
        for (uint i=0; i<_addressArray.length; i++){
            voters[_addressArray[i]].isRegistered = true;
            emit VoterRegistered(_addressArray[i]);
        }
    }

    // ----------- Proposal Management functions -----------

    function registerProposal(string calldata _proposal) external 
    onlyWhitelisted 
    checkVotingPhase(WorkflowStatus.ProposalsRegistrationStarted){
        proposals.push(Proposal(_proposal, 0));
        // proposal ID corresponds to the index in proposals Array
        emit ProposalRegistered(proposals.length - 1);
    }

    // ----------- Voting Management functions -----------

    function vote(uint _proposalId) external 
    onlyWhitelisted 
    checkVotingPhase(WorkflowStatus.VotingSessionStarted){
        require(!voters[msg.sender].hasVoted, "You have already voted");
        require(_proposalId < proposals.length, "Invalid proposal ID");
        voters[msg.sender].hasVoted = true;
        voters[msg.sender].votedProposalId = _proposalId;
        proposals[_proposalId].voteCount += 1;
        emit Voted(msg.sender, _proposalId);
    }

    // ----------- Tally details functions -----------

    function tallyVotes() external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.VotingSessionEnded){
        require(0 < proposals.length, "No proposal available");
        //Use of intermediate variable to use less gas
        uint mostVotedProposalId;
        //In the event of a tie, the first proposal is considered the winner
        for (uint i=0; i < proposals.length; i++){
            if (proposals[mostVotedProposalId].voteCount < proposals[i].voteCount){
                mostVotedProposalId = i;
            }
        }
        winningProposalId = mostVotedProposalId;
        votingStatus = WorkflowStatus.VotesTallied;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
    }


    // ----------- Session Results functions -----------
    
    function getVoterChoice(address _address) external view onlyWhitelisted returns(uint){
        require(voters[_address].hasVoted, "Address has not voted yet");
        return voters[_address].votedProposalId;
    }


}