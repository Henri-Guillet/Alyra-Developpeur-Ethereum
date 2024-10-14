// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";


// VotingPlus Contract
// New Features and Changes:
// 1. Session Management:
//    - Added the ability to reset the entire voting session.
//    - Voters, proposals, and winningProposalId are now session-specific.
//    - Introduced 'currentSession' to track the current voting session.
// 2. Enhanced Whitelist Management:
//    - Added 'removeFromWhitelist()' function to allow the owner to remove voters from the whitelist.
// 3. Enhanced Proposal viewing:
//    - Added getSessionAllProposals(), getSessionProposal(), getSessionAllActiveProposals()
// 4. Tie Management:
//    - Implemented logic to handle ties during vote tallying.
//    - Key variables and logic added for tie management:
//      * 'sessionMostVotedProposalIds': Stores IDs of proposals with the highest vote counts per session.
//      * Tie resolution steps:
//          - If there's only one proposal with the highest votes, it wins.
//          - If multiple proposals tie and their count is less than in the previous round:
//              * Update 'sessionActiveProposals' to set only tied proposals as active.
//              * Reset each proposal's 'voteCount' with 'resetProposalCount()'.
//              * Reset all voters' 'hasVoted' and 'votedProposalId' using 'resetVotersVote()'.
//              * Clear 'mostVotedProposalIds' for the next voting round.
//              * Revote using only the tied proposals.
//          - If the same tie occurs twice (same number of tied proposals), randomly select one as the winner.


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

    mapping(uint => mapping(address => Voter)) private sessionVoters; //updated to session-specific voters
    mapping(uint => Proposal[]) private sessionProposals; //updated to session-specific proposals
    mapping(uint => mapping(uint => bool)) private sessionActiveProposals; // new variable: Tracks active proposals per session
    WorkflowStatus public votingStatus; // Current workflow status
    mapping(uint => uint) private sessionWinningProposalId; // Winning proposal per session
    uint[] private mostVotedProposalId; //new variable: stores IDs of proposals with the highest vote counts
    address[] private votersAddress; //new variable: records addresses of voters for reset purposes
    uint private lastTieLength; //new variable: tracks tie length to determine if a new tie exists or if it’s a repeated one
    uint private currentSession; // new variable: tracks the current voting session number

    // ----------- Events -----------
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event TiedProposalsIdentified(uint[] tiedProposalId); // new event: emits the IDs of tied proposals

    // ----------- Errors -----------

    error AddressNotWhitelisted(address add);
    error WrongVotingPhase(WorkflowStatus expected, WorkflowStatus current);

    // ----------- Modifiers -----------

    modifier onlyWhitelisted(uint sessionId){
        if(!sessionVoters[sessionId][msg.sender].isRegistered){
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
        if (votingStatus != previousPhase) { // Check if the workflow is in the correct phase before moving to the next, prevent from skipping phases or moving backwards
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
        lastTieLength = sessionProposals[currentSession].length; // new: initialize tie length
        setSessionProposalToActive(); //new: initialize all proposals as active
    }

    function startVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.ProposalsRegistrationEnded, WorkflowStatus.VotingSessionStarted){
    }

    function endVotingSession() external 
    onlyOwner 
    updateWorkflow(WorkflowStatus.VotingSessionStarted, WorkflowStatus.VotingSessionEnded){
    }

    // New function added for Ties
    function startTieSession() external 
    onlyOwner
    updateWorkflow(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotingSessionStarted){
    }

    // New function 
    function resetSession() external onlyOwner{
        currentSession++;
        delete mostVotedProposalId;
        delete votersAddress;
        emit WorkflowStatusChange(votingStatus, WorkflowStatus.RegisteringVoters);
        votingStatus = WorkflowStatus.RegisteringVoters;   
    }


    // ----------- Voter Management functions -----------

    function addToWhitelist(address[] calldata _addressArray) external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.RegisteringVoters){
        for (uint i=0; i<_addressArray.length; i++){
            sessionVoters[currentSession][_addressArray[i]].isRegistered = true;
            emit VoterRegistered(_addressArray[i]);    
        }
    }

    //New function
    function removeFromWhitelist(address[] calldata _addressArray) external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.RegisteringVoters){
        for (uint i=0; i<_addressArray.length; i++){
            sessionVoters[currentSession][_addressArray[i]].isRegistered = false;   
        }
    }


    //New function
    function resetVotersVote() private {
        for(uint i=0; i < votersAddress.length; i++){
            sessionVoters[currentSession][votersAddress[i]].hasVoted = false;
            sessionVoters[currentSession][votersAddress[i]].votedProposalId = 0;
        }
    }

    // ----------- Proposal Management functions -----------

    function registerProposal(string calldata _proposal) external 
    onlyWhitelisted (currentSession)
    checkVotingPhase(WorkflowStatus.ProposalsRegistrationStarted){
        sessionProposals[currentSession].push(Proposal(_proposal, 0));
        // proposal ID corresponds to the index in proposals Array
        emit ProposalRegistered(sessionProposals[currentSession].length - 1);
    }

    //New function: reset proposals vote count to 0
    function resetProposalCount() private {
        for(uint i=0; i < sessionProposals[currentSession].length; i++){
            sessionProposals[currentSession][i].voteCount = 0;
        }
    }

    //New function: set all proposals to active proposals
    function setSessionProposalToActive() private{
        for (uint i=0; i < sessionProposals[currentSession].length; i++){
            sessionActiveProposals[currentSession][i] = true;
        }
    }

    //New function: get all session proposals
    function getSessionAllProposals(uint _session) external view returns(Proposal[] memory){
        return sessionProposals[_session];
    }

    //New function: get a session specific proposal
    function getSessionProposal(uint _session, uint _proposalId) external view returns(Proposal memory){
        return sessionProposals[_session][_proposalId];
    }
     

    //New function: get all session active proposals
    function getSessionAllActiveProposals() external view returns(Proposal[] memory activeProposals, uint[] memory activeProposalIds){
        //count how many active proposals there are, in order to initialize array with the correct size (.push() is not available on memory var...)
        uint activeCount = 0;
        for (uint i=0; i < sessionProposals[currentSession].length; i++){
            if(sessionActiveProposals[currentSession][i] == true){
                activeCount++;
            }
        }

        // Initialize arrays with the correct size
        activeProposals = new Proposal[](activeCount);
        activeProposalIds = new uint[](activeCount);

        // Populate arrays with active proposals and their IDs
        uint index = 0;
        for (uint i=0; i < sessionProposals[currentSession].length; i++){
            if(sessionActiveProposals[currentSession][i] == true){
                activeProposals[index] = sessionProposals[currentSession][i];
                activeProposalIds[index] = i;
                index++;
            }
        }
    }

    // ----------- Voting Management functions -----------

    function vote(uint _proposalId) external 
    onlyWhitelisted (currentSession)
    checkVotingPhase(WorkflowStatus.VotingSessionStarted){
        require(!sessionVoters[currentSession][msg.sender].hasVoted, "You have already voted");
        require(_proposalId < sessionProposals[currentSession].length, "Invalid proposal ID");
        require(sessionActiveProposals[currentSession][_proposalId] == true, "Voting is not allowed on this proposal. Please choose an eligible proposal.");

        sessionVoters[currentSession][msg.sender].hasVoted = true;
        sessionVoters[currentSession][msg.sender].votedProposalId = _proposalId;
        sessionProposals[currentSession][_proposalId].voteCount += 1;
        votersAddress.push(msg.sender); // new: record the voter's address

        emit Voted(msg.sender, _proposalId);
    }

    // ----------- tally details functions -----------

    function tallyVotes() external 
    onlyOwner 
    checkVotingPhase(WorkflowStatus.VotingSessionEnded){

        require(0 < sessionProposals[currentSession].length, "No proposal available");
        
        // Find the maximum vote count among all active proposals
        uint maxVote;
        for (uint i = 0; i < sessionProposals[currentSession].length; i++) {
            if (
                maxVote < sessionProposals[currentSession][i].voteCount && 
                sessionActiveProposals[currentSession][i] == true
            ) {
                maxVote = sessionProposals[currentSession][i].voteCount;
            }
        }

        //Identify proposals with the maximum vote count and store their IDs in mostVotedProposalId
        for (uint i=0; i < sessionProposals[currentSession].length; i++){
            if (sessionProposals[currentSession][i].voteCount == maxVote){
                mostVotedProposalId.push(i);
            }
        }

        // Check if there’s a single winning proposal
        if(mostVotedProposalId.length == 1){
            sessionWinningProposalId[currentSession] = mostVotedProposalId[0];
            votingStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
        }

        // Handle a tie scenario with multiple proposals and an unequal previous tie length
        else if(mostVotedProposalId.length < lastTieLength){
            emit TiedProposalsIdentified(mostVotedProposalId);
            //Set less voted proposals to inactive
            for (uint i=0; i < sessionProposals[currentSession].length; i++){
                if(!isProposalInMostVoted(i)){
                    sessionActiveProposals[currentSession][i] = false;
                }
            }
            
            resetVotersVote();
            resetProposalCount();
            lastTieLength = mostVotedProposalId.length;
            delete mostVotedProposalId;
        }

        // If the same tie occurs twice, randomly select one of the tied proposals as the winner
        else{
            sessionWinningProposalId[currentSession] = mostVotedProposalId[getRandomNumber(mostVotedProposalId.length)];
            votingStatus = WorkflowStatus.VotesTallied;
            emit WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, WorkflowStatus.VotesTallied);
        }
    }


    //new function: helper
    function isProposalInMostVoted(uint proposalId) private view returns (bool) {
        for (uint i = 0; i < mostVotedProposalId.length; i++) {
            if (mostVotedProposalId[i] == proposalId) {
                return true;
            }
        }
        return false;
    }

    function getRandomNumber(uint _range) private view returns (uint) {
        uint _randomNumber = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
        return _randomNumber % _range;
    }

    // ----------- Session Results functions -----------

    function getSessionVoterChoice(address _address, uint _session) external view onlyWhitelisted (_session) returns(uint){
        require(sessionVoters[_session][_address].hasVoted, "Address has not voted on that session");
        return sessionVoters[_session][_address].votedProposalId;
    }

    function getSessionWinningProposalId(uint _session) external view returns(uint){
        require(_session <= currentSession, "Select a valid session");
        return sessionWinningProposalId[_session];
    }

}