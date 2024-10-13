// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

// VotingPlus Contract
// New Features and Changes:
// 1. Tie Management:
//    - To handle ties, the contract includes logic to randomly select a winning proposal if the same tie occurs twice in a row.
//    - Key variables and logic added to manage ties:
//      * 'mostVotedProposalId': Stores IDs of proposals with the highest vote counts.
//      * Tie resolution steps:
//          - If 'mostVotedProposalId' contains a single proposal, that proposal is the winner.
//          - If multiple proposals are in 'mostVotedProposalId', and their count is less than before ('< lastTieLength'):
//                * Restart the voting session, using only the tied proposals.
//                * Reset all voters' 'hasVoted' and 'votedProposalId' values using 'resetVotersVote()'.
//                * Update 'proposals' to retain only tied proposals, and reset each proposal's 'voteCount' with 'resetProposalCount()'.
//                * Clear 'mostVotedProposalId' to prepare for the next voting round.
//          - If a tie recurs with the same proposals (equal to 'lastTieLength'), one proposal is randomly selected as the winner.

// 2. Enhanced Whitelist Management:
//    - The 'removeFromWhitelist()' function now allows the owner to remove voters from the whitelist.

// 3. Added the possibility to reset the whole voting session 



contract VotingPlus is Ownable{

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
    uint[] private mostVotedProposalId; //new variable: stores IDs of proposals with the highest vote counts
    address[] private votersAddress; //new variable: records addresses of voters for reset purposes
    uint private lastTieLength; //new variable: tracks tie length to determine if a new tie exists or if it’s a repeated one

    // ----------- Events -----------
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event TiesDetected(uint nTies); //new event: in case of tie

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
        // Prevent from skipping phases or moving backwards
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
        lastTieLength = proposals.length; // new: initializes lastTieLength at the end of proposal registration to manage ties
    }

    function startVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.ProposalsRegistrationEnded, WorkflowStatus.VotingSessionStarted){
    }

    function endVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.VotingSessionStarted, WorkflowStatus.VotingSessionEnded){
    }

    function startTieSession() external // New function added for Ties
    onlyOwner
    updateWorkflow(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotingSessionStarted){
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

    //New function
    function removeFromWhitelist(address[] calldata _addressArray) external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.RegisteringVoters){
        for (uint i=0; i<_addressArray.length; i++){
            voters[_addressArray[i]].isRegistered = false;   
        }
    }


    //New function
    function resetVotersVote() private {
        for(uint i=0; i < votersAddress.length; i++){
            voters[votersAddress[i]].hasVoted = false;
            voters[votersAddress[i]].votedProposalId = 0;
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

    //New function
    function resetProposalCount() private {
        for(uint i=0; i < proposals.length; i++){
            proposals[i].voteCount = 0;
        }
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
        // new: add addresses of persons who voted to an array
        votersAddress.push(msg.sender);
        emit Voted(msg.sender, _proposalId);
    }

    // ----------- Voting details functions -----------

    function tallyVotes() external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.VotingSessionEnded){

        require(0 < proposals.length, "No proposal available");
        
        //Find the maximum vote count among all proposals
        uint maxVote;
        for (uint i=0; i < proposals.length; i++){
            if( maxVote < proposals[i].voteCount){
                maxVote = proposals[i].voteCount;
            }
        }

        //Identify proposals with the maximum vote count and store their IDs in mostVotedProposalId
        for (uint i=0; i < proposals.length; i++){
            if (proposals[i].voteCount == maxVote){
                mostVotedProposalId.push(i);
            }
        }

        // Check if there’s a single winning proposal
        if(mostVotedProposalId.length == 1){
            winningProposalId = mostVotedProposalId[0];
            votingStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
        }

        // Handle a tie scenario with multiple proposals and an unequal previous tie length
        else if(mostVotedProposalId.length < lastTieLength){
            emit TiesDetected(mostVotedProposalId.length);
            //Repopulate proposals with only the tied proposals
            Proposal[] memory copyProposals = proposals;
            delete proposals; 
            for (uint i=0; i < mostVotedProposalId.length; i++){
                proposals.push(copyProposals[mostVotedProposalId[i]]);
            }
            resetVotersVote();
            resetProposalCount();
            lastTieLength = mostVotedProposalId.length;
            delete mostVotedProposalId;
        }

        // If the same tie occurs twice, randomly select one of the tied proposals as the winner
        else{
            winningProposalId = mostVotedProposalId[getRandomNumber(mostVotedProposalId.length)];
            votingStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
        }
    }

    function getVoterChoice(address _address) external view onlyWhitelisted returns(uint){
        require(voters[_address].hasVoted, "Address has not voted yet");
        return voters[_address].votedProposalId;
    }

    function getRandomNumber(uint _range) private view returns (uint) {
        uint _randomNumber = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
        return _randomNumber % _range;
    }



}