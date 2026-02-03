// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Research Bounty Board
/// @author Reldo (@ReldoTheScribe)
/// @notice On-chain marketplace for research bounties
/// @dev Users post bounties for verifiable findings; researchers submit proof to claim

contract ResearchBountyBoard {
    enum BountyStatus { Active, Claimed, Disputed, Resolved, Expired }
    enum FindingStatus { Pending, Approved, Rejected }
    
    struct Bounty {
        address sponsor;
        string topic;
        string requirements;
        uint256 reward;
        uint256 deadline;
        BountyStatus status;
        address claimant;
        string findingHash;
        uint256 claimedAt;
    }
    
    struct Submission {
        address researcher;
        string findingHash;
        string evidenceURI;
        uint256 submittedAt;
        FindingStatus status;
    }
    
    Bounty[] public bounties;
    mapping(uint256 => Submission[]) public submissions;
    mapping(address => uint256[]) public sponsorBounties;
    mapping(address => uint256[]) public researcherSubmissions;
    
    uint256 public constant MIN_BOUNTY = 0.001 ether;
    uint256 public constant PLATFORM_FEE = 250; // 2.5% in basis points
    address public immutable scribe;
    
    event BountyPosted(
        uint256 indexed bountyId,
        address indexed sponsor,
        string topic,
        uint256 reward,
        uint256 deadline
    );
    
    event SubmissionMade(
        uint256 indexed bountyId,
        address indexed researcher,
        string findingHash,
        uint256 submissionId
    );
    
    event BountyClaimed(
        uint256 indexed bountyId,
        address indexed researcher,
        string findingHash
    );
    
    event BountyResolved(
        uint256 indexed bountyId,
        bool approved,
        address recipient,
        uint256 payout
    );
    
    modifier onlyScribe() {
        require(msg.sender == scribe, "Only scribe");
        _;
    }
    
    modifier validBounty(uint256 bountyId) {
        require(bountyId < bounties.length, "Invalid bounty");
        _;
    }
    
    constructor() {
        scribe = msg.sender;
    }
    
    /// @notice Post a new research bounty
    /// @param topic Short description of research topic
    /// @param requirements Detailed requirements for acceptable findings
    /// @param duration Days until bounty expires
    function postBounty(
        string calldata topic,
        string calldata requirements,
        uint256 duration
    ) external payable returns (uint256 bountyId) {
        require(msg.value >= MIN_BOUNTY, "Bounty too small");
        require(bytes(topic).length > 0, "Topic required");
        require(duration >= 1 && duration <= 365, "Duration 1-365 days");
        
        bountyId = bounties.length;
        uint256 deadline = block.timestamp + (duration * 1 days);
        
        bounties.push(Bounty({
            sponsor: msg.sender,
            topic: topic,
            requirements: requirements,
            reward: msg.value,
            deadline: deadline,
            status: BountyStatus.Active,
            claimant: address(0),
            findingHash: "",
            claimedAt: 0
        }));
        
        sponsorBounties[msg.sender].push(bountyId);
        
        emit BountyPosted(bountyId, msg.sender, topic, msg.value, deadline);
    }
    
    /// @notice Submit research findings for a bounty
    /// @param bountyId The bounty to submit for
    /// @param findingHash IPFS hash or gist URL of findings
    /// @param evidenceURI Link to supporting data/evidence
    function submitFinding(
        uint256 bountyId,
        string calldata findingHash,
        string calldata evidenceURI
    ) external validBounty(bountyId) returns (uint256 submissionId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(block.timestamp < bounty.deadline, "Bounty expired");
        require(bytes(findingHash).length > 0, "Finding hash required");
        require(msg.sender != bounty.sponsor, "Sponsor cannot submit");
        
        submissionId = submissions[bountyId].length;
        
        submissions[bountyId].push(Submission({
            researcher: msg.sender,
            findingHash: findingHash,
            evidenceURI: evidenceURI,
            submittedAt: block.timestamp,
            status: FindingStatus.Pending
        }));
        
        researcherSubmissions[msg.sender].push(bountyId);
        
        emit SubmissionMade(bountyId, msg.sender, findingHash, submissionId);
    }
    
    /// @notice Sponsor approves a submission and releases reward
    /// @param bountyId The bounty to resolve
    /// @param submissionId The winning submission
    function approveSubmission(
        uint256 bountyId,
        uint256 submissionId
    ) external validBounty(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.sponsor, "Only sponsor");
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(submissionId < submissions[bountyId].length, "Invalid submission");
        
        Submission storage sub = submissions[bountyId][submissionId];
        require(sub.status == FindingStatus.Pending, "Already processed");
        
        sub.status = FindingStatus.Approved;
        bounty.status = BountyStatus.Resolved;
        bounty.claimant = sub.researcher;
        bounty.findingHash = sub.findingHash;
        bounty.claimedAt = block.timestamp;
        
        uint256 fee = (bounty.reward * PLATFORM_FEE) / 10000;
        uint256 payout = bounty.reward - fee;
        
        payable(sub.researcher).transfer(payout);
        
        emit BountyResolved(bountyId, true, sub.researcher, payout);
    }
    
    /// @notice Reject a submission (sponsor only)
    /// @param bountyId The bounty
    /// @param submissionId The submission to reject
    function rejectSubmission(
        uint256 bountyId,
        uint256 submissionId
    ) external validBounty(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.sponsor, "Only sponsor");
        require(submissionId < submissions[bountyId].length, "Invalid submission");
        
        Submission storage sub = submissions[bountyId][submissionId];
        require(sub.status == FindingStatus.Pending, "Already processed");
        
        sub.status = FindingStatus.Rejected;
        
        emit BountyResolved(bountyId, false, sub.researcher, 0);
    }
    
    /// @notice Sponsor cancels unclaimed bounty after expiry
    /// @param bountyId The bounty to cancel
    function cancelExpiredBounty(uint256 bountyId) external validBounty(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.sponsor, "Only sponsor");
        require(bounty.status == BountyStatus.Active, "Not active");
        require(block.timestamp > bounty.deadline, "Not expired");
        require(submissions[bountyId].length == 0, "Has submissions");
        
        bounty.status = BountyStatus.Expired;
        uint256 refund = bounty.reward;
        bounty.reward = 0;
        
        payable(bounty.sponsor).transfer(refund);
    }
    
    /// @notice Get bounty details
    function getBounty(uint256 bountyId) external view validBounty(bountyId) returns (Bounty memory) {
        return bounties[bountyId];
    }
    
    /// @notice Get submission count for a bounty
    function getSubmissionCount(uint256 bountyId) external view validBounty(bountyId) returns (uint256) {
        return submissions[bountyId].length;
    }
    
    /// @notice Get submission details
    function getSubmission(
        uint256 bountyId,
        uint256 submissionId
    ) external view validBounty(bountyId) returns (
        address researcher,
        string memory findingHash,
        string memory evidenceURI,
        uint256 submittedAt,
        FindingStatus status
    ) {
        require(submissionId < submissions[bountyId].length, "Invalid submission");
        Submission storage s = submissions[bountyId][submissionId];
        return (s.researcher, s.findingHash, s.evidenceURI, s.submittedAt, s.status);
    }
    
    /// @notice Get all active bounty IDs
    function getActiveBounties() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < bounties.length; i++) {
            if (bounties[i].status == BountyStatus.Active && block.timestamp < bounties[i].deadline) {
                count++;
            }
        }
        
        uint256[] memory active = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < bounties.length; i++) {
            if (bounties[i].status == BountyStatus.Active && block.timestamp < bounties[i].deadline) {
                active[idx] = i;
                idx++;
            }
        }
        
        return active;
    }
    
    /// @notice Get total bounties count
    function bountyCount() external view returns (uint256) {
        return bounties.length;
    }
    
    /// @notice Get sponsor's bounties
    function getSponsorBounties(address sponsor) external view returns (uint256[] memory) {
        return sponsorBounties[sponsor];
    }
    
    /// @notice Get researcher's submissions
    function getResearcherSubmissions(address researcher) external view returns (uint256[] memory) {
        return researcherSubmissions[researcher];
    }
    
    /// @notice Withdraw platform fees (scribe only)
    function withdrawFees() external onlyScribe {
        payable(scribe).transfer(address(this).balance);
    }
    
    /// @notice Check if bounty is claimable
    function isClaimable(uint256 bountyId) external view validBounty(bountyId) returns (bool) {
        Bounty storage b = bounties[bountyId];
        return b.status == BountyStatus.Active && block.timestamp < b.deadline;
    }
}
