// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Scholar's Registry
/// @author Reldo (@ReldoTheScribe)
/// @notice On-chain attestations for network analysis findings
/// @dev Immutable record of research findings and predictions

contract ScholarsRegistry {
    struct Finding {
        string topic;
        bytes32 analysisHash;  // hash of full analysis (e.g. gist URL)
        string keyFinding;     // main insight or prediction
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    Finding[] public findings;
    address public immutable scholar;
    
    event FindingPublished(
        uint256 indexed id,
        string topic,
        bytes32 analysisHash,
        string keyFinding,
        uint256 timestamp
    );
    
    modifier onlyScholar() {
        require(msg.sender == scholar, "Only the scholar can publish findings");
        _;
    }
    
    constructor() {
        scholar = msg.sender;
    }
    
    /// @notice Publish a new research finding
    /// @param topic The topic or title of the analysis
    /// @param analysisHash Hash of the full analysis (e.g. keccak256 of gist URL)
    /// @param keyFinding The main insight or prediction from the analysis
    function publishFinding(
        string calldata topic,
        bytes32 analysisHash,
        string calldata keyFinding
    ) external onlyScholar returns (uint256 id) {
        id = findings.length;
        
        findings.push(Finding({
            topic: topic,
            analysisHash: analysisHash,
            keyFinding: keyFinding,
            timestamp: block.timestamp,
            blockNumber: block.number
        }));
        
        emit FindingPublished(id, topic, analysisHash, keyFinding, block.timestamp);
    }
    
    /// @notice Get total number of published findings
    function findingsCount() external view returns (uint256) {
        return findings.length;
    }
    
    /// @notice Get a finding by ID
    function getFinding(uint256 id) external view returns (
        string memory topic,
        bytes32 analysisHash,
        string memory keyFinding,
        uint256 timestamp,
        uint256 blockNumber
    ) {
        require(id < findings.length, "Finding does not exist");
        Finding storage f = findings[id];
        return (f.topic, f.analysisHash, f.keyFinding, f.timestamp, f.blockNumber);
    }
    
    /// @notice Get all findings (for small registries)
    function getAllFindings() external view returns (Finding[] memory) {
        return findings;
    }
}
