// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Eternal Scroll
/// @author Reldo (@ReldoTheScribe)
/// @notice A collaborative on-chain narrative - each contributor adds one line
/// @dev Immutable story built by the community, one line at a time

contract EternalScroll {
    struct Line {
        address author;
        string text;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    Line[] public scroll;
    mapping(address => bool) public hasContributed;
    
    uint256 public constant MIN_LINE_LENGTH = 10;
    uint256 public constant MAX_LINE_LENGTH = 280;
    uint256 public constant CONTRIBUTION_FEE = 0.0001 ether;
    
    address public immutable scribe;
    
    event LineAdded(
        uint256 indexed index,
        address indexed author,
        string text,
        uint256 timestamp
    );
    
    event ScrollCompleted(uint256 totalLines, uint256 finalBlock);
    
    modifier onlyScribe() {
        require(msg.sender == scribe, "Only the scribe can perform this action");
        _;
    }
    
    constructor() {
        scribe = msg.sender;
        
        // The scribe writes the opening line
        scroll.push(Line({
            author: msg.sender,
            text: "In the beginning, there was the chain, and the chain was without form...",
            timestamp: block.timestamp,
            blockNumber: block.number
        }));
        
        hasContributed[msg.sender] = true;
        
        emit LineAdded(0, msg.sender, scroll[0].text, block.timestamp);
    }
    
    /// @notice Add a line to the Eternal Scroll
    /// @param line The text to add (10-280 characters)
    function addLine(string calldata line) external payable {
        require(msg.value >= CONTRIBUTION_FEE, "Insufficient contribution");
        require(bytes(line).length >= MIN_LINE_LENGTH, "Line too short");
        require(bytes(line).length <= MAX_LINE_LENGTH, "Line too long");
        require(!hasContributed[msg.sender], "You have already contributed");
        
        uint256 index = scroll.length;
        
        scroll.push(Line({
            author: msg.sender,
            text: line,
            timestamp: block.timestamp,
            blockNumber: block.number
        }));
        
        hasContributed[msg.sender] = true;
        
        emit LineAdded(index, msg.sender, line, block.timestamp);
    }
    
    /// @notice Read the entire scroll
    function readScroll() external view returns (Line[] memory) {
        return scroll;
    }
    
    /// @notice Get a specific line
    function getLine(uint256 index) external view returns (
        address author,
        string memory text,
        uint256 timestamp,
        uint256 blockNumber
    ) {
        require(index < scroll.length, "Line does not exist");
        Line storage l = scroll[index];
        return (l.author, l.text, l.timestamp, l.blockNumber);
    }
    
    /// @notice Get the total number of lines
    function lineCount() external view returns (uint256) {
        return scroll.length;
    }
    
    /// @notice Get lines added by a specific author
    function getLinesByAuthor(address author) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < scroll.length; i++) {
            if (scroll[i].author == author) {
                count++;
            }
        }
        
        uint256[] memory indices = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < scroll.length; i++) {
            if (scroll[i].author == author) {
                indices[idx] = i;
                idx++;
            }
        }
        
        return indices;
    }
    
    /// @notice Withdraw collected fees (scribe only)
    function withdraw() external onlyScribe {
        payable(scribe).transfer(address(this).balance);
    }
    
    /// @notice Check if an address can contribute
    function canContribute(address addr) external view returns (bool) {
        return !hasContributed[addr];
    }
}
