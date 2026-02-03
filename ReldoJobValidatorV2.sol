// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReldoJobValidatorV2
 * @notice Token-weighted job validation. $RELDO holders vote on work quality.
 * @dev V2: Configurable voting threshold
 */
contract ReldoJobValidatorV2 is ReentrancyGuard, Ownable {
    IERC20 public immutable reldoToken;
    
    // Constants
    uint256 public constant APPROVAL_THRESHOLD = 67;
    uint256 public constant VOTER_REWARD_BPS = 100;
    uint256 public constant VOTING_PERIOD = 3 days;
    
    // Configurable
    uint256 public minReldoToVote;
    
    enum JobStatus { Open, Submitted, Approved, Rejected, Cancelled }
    
    struct Job {
        address poster;
        address worker;
        uint256 bounty;
        string description;
        string submissionHash;
        JobStatus status;
        uint256 votingEnds;
        uint256 approveWeight;
        uint256 rejectWeight;
        uint256 totalVoterWeight;
    }
    
    uint256 public jobCount;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public votedApprove;
    mapping(uint256 => mapping(address => uint256)) public voterWeight;
    
    event JobCreated(uint256 indexed jobId, address indexed poster, uint256 bounty, string description);
    event JobSubmitted(uint256 indexed jobId, address indexed worker, string submissionHash);
    event Voted(uint256 indexed jobId, address indexed voter, bool approve, uint256 weight);
    event JobResolved(uint256 indexed jobId, bool approved, uint256 voterReward);
    event JobCancelled(uint256 indexed jobId);
    event MinVotingTokensUpdated(uint256 oldAmount, uint256 newAmount);
    
    constructor(address _reldoToken, uint256 _minReldoToVote) Ownable(msg.sender) {
        reldoToken = IERC20(_reldoToken);
        minReldoToVote = _minReldoToVote;
    }
    
    function setMinReldoToVote(uint256 _amount) external onlyOwner {
        uint256 oldAmount = minReldoToVote;
        minReldoToVote = _amount;
        emit MinVotingTokensUpdated(oldAmount, _amount);
    }
    
    function createJob(string calldata description) external payable returns (uint256 jobId) {
        require(msg.value > 0, "Bounty required");
        
        jobId = ++jobCount;
        jobs[jobId] = Job({
            poster: msg.sender,
            worker: address(0),
            bounty: msg.value,
            description: description,
            submissionHash: "",
            status: JobStatus.Open,
            votingEnds: 0,
            approveWeight: 0,
            rejectWeight: 0,
            totalVoterWeight: 0
        });
        
        emit JobCreated(jobId, msg.sender, msg.value, description);
    }
    
    function submitWork(uint256 jobId, string calldata submissionHash) external {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.Open, "Job not open");
        require(bytes(submissionHash).length > 0, "Submission hash required");
        
        job.worker = msg.sender;
        job.submissionHash = submissionHash;
        job.status = JobStatus.Submitted;
        job.votingEnds = block.timestamp + VOTING_PERIOD;
        
        emit JobSubmitted(jobId, msg.sender, submissionHash);
    }
    
    function vote(uint256 jobId, bool approve) external {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.Submitted, "Not in voting");
        require(block.timestamp < job.votingEnds, "Voting ended");
        require(!hasVoted[jobId][msg.sender], "Already voted");
        
        uint256 weight = reldoToken.balanceOf(msg.sender);
        require(weight >= minReldoToVote, "Insufficient RELDO to vote");
        
        hasVoted[jobId][msg.sender] = true;
        votedApprove[jobId][msg.sender] = approve;
        voterWeight[jobId][msg.sender] = weight;
        
        if (approve) {
            job.approveWeight += weight;
        } else {
            job.rejectWeight += weight;
        }
        job.totalVoterWeight += weight;
        
        emit Voted(jobId, msg.sender, approve, weight);
    }
    
    function resolveJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.Submitted, "Not in voting");
        require(block.timestamp >= job.votingEnds, "Voting not ended");
        
        uint256 totalWeight = job.approveWeight + job.rejectWeight;
        require(totalWeight > 0, "No votes cast");
        
        uint256 approvalPercent = (job.approveWeight * 100) / totalWeight;
        bool approved = approvalPercent >= APPROVAL_THRESHOLD;
        
        uint256 voterReward = (job.bounty * VOTER_REWARD_BPS) / 10000;
        uint256 workerAmount = job.bounty - voterReward;
        
        if (approved) {
            job.status = JobStatus.Approved;
            (bool sent, ) = payable(job.worker).call{value: workerAmount}("");
            require(sent, "Worker payment failed");
        } else {
            job.status = JobStatus.Rejected;
            (bool sent, ) = payable(job.poster).call{value: workerAmount}("");
            require(sent, "Refund failed");
        }
        
        emit JobResolved(jobId, approved, voterReward);
    }
    
    function claimReward(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.Approved || job.status == JobStatus.Rejected, "Not resolved");
        require(hasVoted[jobId][msg.sender], "Did not vote");
        
        bool won = (job.status == JobStatus.Approved && votedApprove[jobId][msg.sender]) ||
                   (job.status == JobStatus.Rejected && !votedApprove[jobId][msg.sender]);
        require(won, "Not on winning side");
        
        uint256 weight = voterWeight[jobId][msg.sender];
        require(weight > 0, "Already claimed");
        
        uint256 winningWeight = job.status == JobStatus.Approved ? job.approveWeight : job.rejectWeight;
        uint256 totalVoterReward = (job.bounty * VOTER_REWARD_BPS) / 10000;
        uint256 reward = (totalVoterReward * weight) / winningWeight;
        
        voterWeight[jobId][msg.sender] = 0;
        
        if (reward > 0) {
            (bool sent, ) = payable(msg.sender).call{value: reward}("");
            require(sent, "Reward transfer failed");
        }
    }
    
    function cancelJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        require(msg.sender == job.poster, "Not poster");
        require(job.status == JobStatus.Open, "Cannot cancel");
        
        job.status = JobStatus.Cancelled;
        
        (bool sent, ) = payable(job.poster).call{value: job.bounty}("");
        require(sent, "Refund failed");
        
        emit JobCancelled(jobId);
    }
    
    function getJob(uint256 jobId) external view returns (
        address poster,
        address worker,
        uint256 bounty,
        string memory description,
        string memory submissionHash,
        JobStatus status,
        uint256 votingEnds,
        uint256 approveWeight,
        uint256 rejectWeight
    ) {
        Job storage job = jobs[jobId];
        return (
            job.poster,
            job.worker,
            job.bounty,
            job.description,
            job.submissionHash,
            job.status,
            job.votingEnds,
            job.approveWeight,
            job.rejectWeight
        );
    }
    
    function getApprovalPercent(uint256 jobId) external view returns (uint256) {
        Job storage job = jobs[jobId];
        uint256 total = job.approveWeight + job.rejectWeight;
        if (total == 0) return 0;
        return (job.approveWeight * 100) / total;
    }
}
