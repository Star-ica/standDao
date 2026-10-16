// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Non-transferable credentials. The owner defines credential types and approves issuers.
/// Issuers hand out credentials, each worth points. Holders with enough reputation can endorse others.
/// There is no transfer function at all, and locked() follows the ERC-5192 convention.
contract SoulboundReputation {
    struct CredentialType { string name; uint256 points; bool active; }
    struct Credential { uint256 typeId; address issuer; uint64 issuedAt; bool revoked; }

    address public owner;
    uint256 public endorseThreshold = 10; // score needed to endorse others
    CredentialType[] private types;
    mapping(address => bool) public isIssuer;
    mapping(address => Credential[]) private held;
    mapping(address => mapping(uint256 => bool)) public hasType; // holder => typeId => active credential
    mapping(address => uint256) public endorsementPoints;
    mapping(address => mapping(address => bool)) public endorsed; // endorser => subject
    mapping(address => uint256) private credentialPoints;

    event TypeAdded(uint256 indexed typeId, string name, uint256 points);
    event Issued(address indexed to, uint256 indexed typeId, address indexed issuer);
    event Revoked(address indexed holder, uint256 index);
    event Endorsed(address indexed from, address indexed to);
    event Locked(uint256 tokenId); // ERC-5192

    modifier onlyOwner() { require(msg.sender == owner, "Only owner"); _; }

    constructor() { owner = msg.sender; isIssuer[msg.sender] = true; }

    function setIssuer(address who, bool ok) external onlyOwner { isIssuer[who] = ok; }
    function setEndorseThreshold(uint256 v) external onlyOwner { endorseThreshold = v; }

    function addType(string calldata name, uint256 points) external onlyOwner returns (uint256 id) {
        id = types.length;
        types.push(CredentialType(name, points, true));
        emit TypeAdded(id, name, points);
    }

    function issue(address to, uint256 typeId) external {
        require(isIssuer[msg.sender], "Not an issuer");
        require(typeId < types.length && types[typeId].active, "Unknown type");
        require(!hasType[to][typeId], "Already holds this credential");
        held[to].push(Credential(typeId, msg.sender, uint64(block.timestamp), false));
        hasType[to][typeId] = true;
        credentialPoints[to] += types[typeId].points;
        emit Issued(to, typeId, msg.sender);
    }

    /// The issuer of a credential, or the owner, can revoke it.
    function revoke(address holder, uint256 index) external {
        Credential storage cr = held[holder][index];
        require(!cr.revoked, "Already revoked");
        require(msg.sender == cr.issuer || msg.sender == owner, "Not allowed");
        cr.revoked = true;
        hasType[holder][cr.typeId] = false;
        credentialPoints[holder] -= types[cr.typeId].points;
        emit Revoked(holder, index);
    }

    function endorse(address subject) external {
        require(subject != msg.sender, "Cannot endorse yourself");
        require(scoreOf(msg.sender) >= endorseThreshold, "Score too low to endorse");
        require(!endorsed[msg.sender][subject], "Already endorsed");
        endorsed[msg.sender][subject] = true;
        endorsementPoints[subject] += 1;
        emit Endorsed(msg.sender, subject);
    }

    function scoreOf(address who) public view returns (uint256) {
        return credentialPoints[who] + endorsementPoints[who];
    }

    /// Use this from other contracts to gate access, e.g. require(rep.meetsScore(user, 20)).
    function meetsScore(address who, uint256 min) external view returns (bool) { return scoreOf(who) >= min; }

    function locked(uint256) external pure returns (bool) { return true; }

    function typeCount() external view returns (uint256) { return types.length; }
    function getType(uint256 id) external view returns (string memory name, uint256 points, bool active) {
        CredentialType storage t = types[id];
        return (t.name, t.points, t.active);
    }
    function credentialCount(address who) external view returns (uint256) { return held[who].length; }
    function getCredential(address who, uint256 i) external view returns (uint256 typeId, address issuer, uint64 issuedAt, bool revoked) {
        Credential storage cr = held[who][i];
        return (cr.typeId, cr.issuer, cr.issuedAt, cr.revoked);
    }
}
