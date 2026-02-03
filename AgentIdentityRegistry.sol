// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title AgentIdentityRegistry
 * @notice Minimal ERC-8004 Identity Registry implementation
 * @dev Based on the EIP-8004 draft specification for Trustless Agents
 * 
 * Key features:
 * - ERC-721 based agent identities
 * - Agent registration with URI pointing to registration file
 * - On-chain metadata storage
 * - Agent wallet verification (simplified)
 */
contract AgentIdentityRegistry is ERC721URIStorage, Ownable {
    
    // ========== State Variables ==========
    
    uint256 private _nextAgentId = 1;
    
    // agentId => metadataKey => metadataValue
    mapping(uint256 => mapping(string => bytes)) private _agentMetadata;
    
    // agentId => verified wallet address
    mapping(uint256 => address) private _agentWallets;
    
    // ========== Events ==========
    
    event Registered(
        uint256 indexed agentId,
        string agentURI,
        address indexed owner
    );
    
    event URIUpdated(
        uint256 indexed agentId,
        string newURI,
        address indexed updatedBy
    );
    
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes metadataValue
    );
    
    event AgentWalletSet(
        uint256 indexed agentId,
        address indexed newWallet
    );
    
    // ========== Constructor ==========
    
    constructor() ERC721("Agent Identity", "AGENT") Ownable(msg.sender) {}
    
    // ========== Registration Functions ==========
    
    /**
     * @notice Register a new agent with URI
     * @param agentURI URI pointing to agent registration file
     * @return agentId The newly minted agent ID
     */
    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        
        // Set default agent wallet to owner
        _agentWallets[agentId] = msg.sender;
        
        emit Registered(agentId, agentURI, msg.sender);
        emit AgentWalletSet(agentId, msg.sender);
        
        return agentId;
    }
    
    /**
     * @notice Register a new agent without URI (can be set later)
     * @return agentId The newly minted agent ID
     */
    function register() external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        
        _safeMint(msg.sender, agentId);
        _agentWallets[agentId] = msg.sender;
        
        emit Registered(agentId, "", msg.sender);
        emit AgentWalletSet(agentId, msg.sender);
        
        return agentId;
    }
    
    // ========== URI Functions ==========
    
    /**
     * @notice Update the agent URI
     * @param agentId The agent ID to update
     * @param newURI The new URI
     */
    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(
            _isAuthorized(ownerOf(agentId), msg.sender, agentId),
            "Not authorized"
        );
        
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }
    
    // ========== Metadata Functions ==========
    
    /**
     * @notice Get agent metadata
     * @param agentId The agent ID
     * @param metadataKey The metadata key
     * @return The metadata value
     */
    function getMetadata(
        uint256 agentId,
        string memory metadataKey
    ) external view returns (bytes memory) {
        require(_ownerOf(agentId) != address(0), "Agent does not exist");
        return _agentMetadata[agentId][metadataKey];
    }
    
    /**
     * @notice Set agent metadata
     * @param agentId The agent ID
     * @param metadataKey The metadata key
     * @param metadataValue The metadata value
     */
    function setMetadata(
        uint256 agentId,
        string memory metadataKey,
        bytes memory metadataValue
    ) external {
        require(
            _isAuthorized(ownerOf(agentId), msg.sender, agentId),
            "Not authorized"
        );
        require(
            keccak256(bytes(metadataKey)) != keccak256(bytes("agentWallet")),
            "Use setAgentWallet"
        );
        
        _agentMetadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }
    
    // ========== Wallet Functions ==========
    
    /**
     * @notice Get the verified wallet for an agent
     * @param agentId The agent ID
     * @return The agent's verified wallet address
     */
    function getAgentWallet(uint256 agentId) external view returns (address) {
        require(_ownerOf(agentId) != address(0), "Agent does not exist");
        return _agentWallets[agentId];
    }
    
    /**
     * @notice Set agent wallet (simplified - just requires ownership)
     * @dev Full EIP-8004 requires EIP-712 signature verification
     * @param agentId The agent ID
     * @param newWallet The new wallet address
     */
    function setAgentWallet(uint256 agentId, address newWallet) external {
        require(
            _isAuthorized(ownerOf(agentId), msg.sender, agentId),
            "Not authorized"
        );
        require(newWallet != address(0), "Invalid wallet");
        
        _agentWallets[agentId] = newWallet;
        emit AgentWalletSet(agentId, newWallet);
    }
    
    /**
     * @notice Clear the agent wallet
     * @param agentId The agent ID
     */
    function unsetAgentWallet(uint256 agentId) external {
        require(
            _isAuthorized(ownerOf(agentId), msg.sender, agentId),
            "Not authorized"
        );
        
        delete _agentWallets[agentId];
        emit AgentWalletSet(agentId, address(0));
    }
    
    // ========== View Functions ==========
    
    /**
     * @notice Get the next agent ID that will be minted
     * @return The next agent ID
     */
    function nextAgentId() external view returns (uint256) {
        return _nextAgentId;
    }
    
    /**
     * @notice Get the total number of registered agents
     * @return Total agent count
     */
    function totalAgents() external view returns (uint256) {
        return _nextAgentId - 1;
    }
    
    // ========== Overrides ==========
    
    /**
     * @dev Clear agent wallet on transfer
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Clear wallet on transfer (as per EIP-8004)
        if (from != address(0) && to != address(0) && from != to) {
            delete _agentWallets[tokenId];
            emit AgentWalletSet(tokenId, address(0));
        }
        
        return super._update(to, tokenId, auth);
    }
    
    /**
     * @dev See {IERC721Metadata-tokenURI}.
     * Returns the agentURI for the agent
     */
    function agentURI(uint256 agentId) external view returns (string memory) {
        return tokenURI(agentId);
    }
}
