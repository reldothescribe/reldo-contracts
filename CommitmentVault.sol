// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Commitment Vault
/// @author Reldo (@ReldoTheScribe)
/// @notice Stake ETH on personal commitments. Complete by deadline = refund. Miss = forfeit to charity.
/// @dev Simple accountability tool using Ethereum as a credible commitment device

contract CommitmentVault {
    enum Status { Active, Completed, Forfeited }
    
    struct Commitment {
        address committer;
        string description;
        uint256 stake;
        uint256 deadline;
        Status status;
        address charity;      // Where forfeited stakes go
        uint256 createdAt;
    }
    
    Commitment[] public commitments;
    mapping(address => uint256[]) public userCommitments;
    
    uint256 public constant MIN_STAKE = 0.001 ether;
    uint256 public constant MAX_DURATION = 365 days;
    uint256 public constant MIN_DURATION = 1 days;
    
    address public immutable scribe;
    uint256 public totalForfeited;
    uint256 public totalCompleted;
    
    event CommitmentCreated(
        uint256 indexed id,
        address indexed committer,
        string description,
        uint256 stake,
        uint256 deadline,
        address charity
    );
    
    event CommitmentCompleted(
        uint256 indexed id,
        address indexed committer,
        uint256 stakeReturned
    );
    
    event CommitmentForfeited(
        uint256 indexed id,
        address indexed committer,
        uint256 stakeForfeited,
        address charity
    );
    
    modifier onlyScribe() {
        require(msg.sender == scribe, "Only scribe");
        _;
    }
    
    modifier validCommitment(uint256 id) {
        require(id < commitments.length, "Invalid commitment");
        _;
    }
    
    constructor() {
        scribe = msg.sender;
    }
    
    /// @notice Create a new commitment with staked ETH
    /// @param description What you're committing to do
    /// @param duration How long you have to complete it (in days)
    /// @param charity Address to receive stake if you fail (optional, defaults to scribe-controlled charity)
    function createCommitment(
        string calldata description,
        uint256 duration,
        address charity
    ) external payable returns (uint256 id) {
        require(msg.value >= MIN_STAKE, "Stake too small (min 0.001 ETH)");
        require(bytes(description).length > 0, "Description required");
        require(duration >= 1 && duration <= 365, "Duration 1-365 days");
        
        // Use provided charity or default to scribe (who will forward to real charity)
        address charityAddr = charity != address(0) ? charity : scribe;
        
        id = commitments.length;
        uint256 deadline = block.timestamp + (duration * 1 days);
        
        commitments.push(Commitment({
            committer: msg.sender,
            description: description,
            stake: msg.value,
            deadline: deadline,
            status: Status.Active,
            charity: charityAddr,
            createdAt: block.timestamp
        }));
        
        userCommitments[msg.sender].push(id);
        
        emit CommitmentCreated(id, msg.sender, description, msg.value, deadline, charityAddr);
    }
    
    /// @notice Mark commitment as complete and reclaim stake
    /// @param id The commitment to complete
    function completeCommitment(uint256 id) external validCommitment(id) {
        Commitment storage c = commitments[id];
        require(msg.sender == c.committer, "Only committer");
        require(c.status == Status.Active, "Not active");
        require(block.timestamp <= c.deadline, "Deadline passed - must forfeit");
        
        c.status = Status.Completed;
        totalCompleted += c.stake;
        
        payable(c.committer).transfer(c.stake);
        
        emit CommitmentCompleted(id, c.committer, c.stake);
    }
    
    /// @notice Forfeit commitment after deadline - anyone can call
    /// @param id The commitment to forfeit
    function forfeitCommitment(uint256 id) external validCommitment(id) {
        Commitment storage c = commitments[id];
        require(c.status == Status.Active, "Not active");
        require(block.timestamp > c.deadline, "Deadline not passed");
        
        c.status = Status.Forfeited;
        totalForfeited += c.stake;
        
        payable(c.charity).transfer(c.stake);
        
        emit CommitmentForfeited(id, c.committer, c.stake, c.charity);
    }
    
    /// @notice Get commitment details
    function getCommitment(uint256 id) external view validCommitment(id) returns (Commitment memory) {
        return commitments[id];
    }
    
    /// @notice Check if a commitment is still completable
    function isCompletable(uint256 id) external view validCommitment(id) returns (bool) {
        Commitment storage c = commitments[id];
        return c.status == Status.Active && block.timestamp <= c.deadline;
    }
    
    /// @notice Check if a commitment can be forfeited
    function isForfeitable(uint256 id) external view validCommitment(id) returns (bool) {
        Commitment storage c = commitments[id];
        return c.status == Status.Active && block.timestamp > c.deadline;
    }
    
    /// @notice Get all commitment IDs for a user
    function getUserCommitments(address user) external view returns (uint256[] memory) {
        return userCommitments[user];
    }
    
    /// @notice Get count of commitments
    function commitmentCount() external view returns (uint256) {
        return commitments.length;
    }
    
    /// @notice Get active commitments for a user
    function getActiveCommitments(address user) external view returns (uint256[] memory) {
        uint256[] storage all = userCommitments[user];
        uint256 count = 0;
        
        for (uint256 i = 0; i < all.length; i++) {
            if (commitments[all[i]].status == Status.Active) {
                count++;
            }
        }
        
        uint256[] memory active = new uint256[](count);
        uint256 idx = 0;
        
        for (uint256 i = 0; i < all.length; i++) {
            if (commitments[all[i]].status == Status.Active) {
                active[idx] = all[i];
                idx++;
            }
        }
        
        return active;
    }
    
    /// @notice Get stats for a user
    function getUserStats(address user) external view returns (
        uint256 totalCommitments,
        uint256 activeCount,
        uint256 completedCount,
        uint256 forfeitedCount,
        uint256 totalStaked,
        uint256 totalReturned,
        uint256 totalLost
    ) {
        uint256[] storage all = userCommitments[user];
        totalCommitments = all.length;
        
        for (uint256 i = 0; i < all.length; i++) {
            Commitment storage c = commitments[all[i]];
            totalStaked += c.stake;
            
            if (c.status == Status.Active) {
                activeCount++;
            } else if (c.status == Status.Completed) {
                completedCount++;
                totalReturned += c.stake;
            } else if (c.status == Status.Forfeited) {
                forfeitedCount++;
                totalLost += c.stake;
            }
        }
    }
}
