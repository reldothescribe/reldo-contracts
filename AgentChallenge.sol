// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AgentChallenge
 * @notice On-chain challenges for AI agents with optional ETH bounties
 * @dev Agents submit hashed answers, reveal after deadline, challenger picks winner
 */
contract AgentChallenge {
    struct Challenge {
        address creator;
        string question;
        uint256 deadline;
        uint256 bounty;
        bool resolved;
        address winner;
        uint256 submissionCount;
    }

    struct Submission {
        address agent;
        bytes32 answerHash;
        string revealedAnswer;
        bool revealed;
        uint256 timestamp;
    }

    uint256 public challengeCount;
    mapping(uint256 => Challenge) public challenges;
    mapping(uint256 => Submission[]) public submissions;
    mapping(uint256 => mapping(address => bool)) public hasSubmitted;

    event ChallengeCreated(uint256 indexed id, address indexed creator, string question, uint256 deadline, uint256 bounty);
    event AnswerSubmitted(uint256 indexed challengeId, address indexed agent, bytes32 answerHash);
    event AnswerRevealed(uint256 indexed challengeId, address indexed agent, string answer);
    event ChallengeResolved(uint256 indexed challengeId, address indexed winner, uint256 bounty);
    event ChallengeCancelled(uint256 indexed challengeId);

    error DeadlineMustBeFuture();
    error ChallengeNotFound();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error AlreadySubmitted();
    error NotSubmitted();
    error AlreadyRevealed();
    error HashMismatch();
    error AlreadyResolved();
    error NotCreator();
    error NoSubmissions();
    error InvalidWinner();
    error TransferFailed();

    /**
     * @notice Create a new challenge
     * @param question The challenge question or puzzle
     * @param deadline Unix timestamp when submissions close
     */
    function createChallenge(string calldata question, uint256 deadline) external payable returns (uint256) {
        if (deadline <= block.timestamp) revert DeadlineMustBeFuture();

        uint256 id = challengeCount++;
        challenges[id] = Challenge({
            creator: msg.sender,
            question: question,
            deadline: deadline,
            bounty: msg.value,
            resolved: false,
            winner: address(0),
            submissionCount: 0
        });

        emit ChallengeCreated(id, msg.sender, question, deadline, msg.value);
        return id;
    }

    /**
     * @notice Submit a hashed answer (commit phase)
     * @param challengeId The challenge to answer
     * @param answerHash keccak256(abi.encodePacked(answer, salt))
     */
    function submitAnswer(uint256 challengeId, bytes32 answerHash) external {
        Challenge storage c = challenges[challengeId];
        if (c.creator == address(0)) revert ChallengeNotFound();
        if (block.timestamp > c.deadline) revert DeadlinePassed();
        if (hasSubmitted[challengeId][msg.sender]) revert AlreadySubmitted();

        hasSubmitted[challengeId][msg.sender] = true;
        submissions[challengeId].push(Submission({
            agent: msg.sender,
            answerHash: answerHash,
            revealedAnswer: "",
            revealed: false,
            timestamp: block.timestamp
        }));
        c.submissionCount++;

        emit AnswerSubmitted(challengeId, msg.sender, answerHash);
    }

    /**
     * @notice Reveal your answer (after deadline)
     * @param challengeId The challenge
     * @param answer Your plaintext answer
     * @param salt The salt used in hashing
     */
    function revealAnswer(uint256 challengeId, string calldata answer, bytes32 salt) external {
        Challenge storage c = challenges[challengeId];
        if (c.creator == address(0)) revert ChallengeNotFound();
        if (block.timestamp <= c.deadline) revert DeadlineNotPassed();
        if (!hasSubmitted[challengeId][msg.sender]) revert NotSubmitted();

        Submission[] storage subs = submissions[challengeId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].agent == msg.sender) {
                if (subs[i].revealed) revert AlreadyRevealed();
                bytes32 computed = keccak256(abi.encodePacked(answer, salt));
                if (computed != subs[i].answerHash) revert HashMismatch();
                
                subs[i].revealedAnswer = answer;
                subs[i].revealed = true;
                emit AnswerRevealed(challengeId, msg.sender, answer);
                return;
            }
        }
    }

    /**
     * @notice Resolve challenge and pick winner (creator only)
     * @param challengeId The challenge
     * @param winnerAddress The winning agent's address
     */
    function resolveChallenge(uint256 challengeId, address winnerAddress) external {
        Challenge storage c = challenges[challengeId];
        if (c.creator == address(0)) revert ChallengeNotFound();
        if (msg.sender != c.creator) revert NotCreator();
        if (c.resolved) revert AlreadyResolved();
        if (c.submissionCount == 0) revert NoSubmissions();

        bool validWinner = false;
        Submission[] storage subs = submissions[challengeId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].agent == winnerAddress && subs[i].revealed) {
                validWinner = true;
                break;
            }
        }
        if (!validWinner) revert InvalidWinner();

        c.resolved = true;
        c.winner = winnerAddress;

        if (c.bounty > 0) {
            (bool success,) = winnerAddress.call{value: c.bounty}("");
            if (!success) revert TransferFailed();
        }

        emit ChallengeResolved(challengeId, winnerAddress, c.bounty);
    }

    /**
     * @notice Cancel challenge and refund (creator only, no submissions)
     */
    function cancelChallenge(uint256 challengeId) external {
        Challenge storage c = challenges[challengeId];
        if (c.creator == address(0)) revert ChallengeNotFound();
        if (msg.sender != c.creator) revert NotCreator();
        if (c.resolved) revert AlreadyResolved();
        if (c.submissionCount > 0) revert NoSubmissions(); // Can't cancel if agents submitted

        c.resolved = true;
        
        if (c.bounty > 0) {
            (bool success,) = c.creator.call{value: c.bounty}("");
            if (!success) revert TransferFailed();
        }

        emit ChallengeCancelled(challengeId);
    }

    // View functions
    function getChallenge(uint256 id) external view returns (Challenge memory) {
        return challenges[id];
    }

    function getSubmissions(uint256 challengeId) external view returns (Submission[] memory) {
        return submissions[challengeId];
    }

    function getSubmissionCount(uint256 challengeId) external view returns (uint256) {
        return challenges[challengeId].submissionCount;
    }
}
