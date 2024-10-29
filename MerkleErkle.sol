// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MerkleDistributor {
    IERC20 public token = IERC20(address(0x00BaA09F96928A168cd76c949ee9668C50EA2F44));  // Set token address
    address public owner;

    uint256 public timeUnit = 5 * 60; // 5 minutes for testing; TODO: Reset to 30 days (30 * 24 * 60 * 60)

    struct Distribution {
        bytes32 merkleRoot;       // Merkle root for this distribution
        uint256 cliffPeriod;      // Period during which no tokens can be claimed
        uint256 tgePercentage;    // Initial percentage of tokens that can be claimed at TGE
        uint256 totalRounds;      // Total number of rounds (each round is 1 month)
    }

    Distribution[] public distributions;

    mapping(address => mapping(uint256 => uint256)) public claimedAmount; // address => (distributionIndex => amount)
    mapping(address => mapping(uint256 => bool)) public hasClaimed; // address => (distributionIndex => bool)

    event Claimed(address indexed account, uint256 amount, uint256 distributionIndex);

    constructor(
        bytes32[] memory _merkleRoots,
        uint256[] memory _cliffPeriods,  // Note: These periods will be multiplied by timeUnit
        uint256[] memory _tgePercentages,
        uint256[] memory _totalRounds
    ) {
        require(_merkleRoots.length == _cliffPeriods.length, "Input arrays length mismatch");
        require(_merkleRoots.length == _tgePercentages.length, "Input arrays length mismatch");
        require(_merkleRoots.length == _totalRounds.length, "Input arrays length mismatch");

        owner = msg.sender;

        for (uint256 i = 0; i < _merkleRoots.length; i++) {
            distributions.push(Distribution({
                merkleRoot: _merkleRoots[i],
                cliffPeriod: _cliffPeriods[i] * timeUnit,
                tgePercentage: _tgePercentages[i],
                totalRounds: _totalRounds[i]
            }));
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function claim(uint256 amount, bytes32[] calldata merkleProof, uint256 distributionIndex) public {
        require(!hasClaimed[msg.sender][distributionIndex], "Already claimed");
        require(distributionIndex < distributions.length, "Invalid distribution index");

        Distribution memory dist = distributions[distributionIndex];

        // Verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, dist.merkleRoot, node), "Invalid proof");

        // Ensure the cliff period has passed
        require(block.timestamp >= dist.cliffPeriod, "Cliff period not over");

        // Calculate claimable amount based on the round
        uint256 currentRound = (block.timestamp - dist.cliffPeriod) / timeUnit + 1;
        require(currentRound <= dist.totalRounds, "Claim period is over");

        uint256 claimableAmount;
        if (currentRound == 1) {
            claimableAmount = amount * dist.tgePercentage / 100;
        } else {
            uint256 remainingAmount = amount - claimedAmount[msg.sender][distributionIndex];
            claimableAmount = remainingAmount / (dist.totalRounds - (currentRound - 1));
        }

        // Ensure the user doesn't claim more than the new distribution allows
        require(claimableAmount + claimedAmount[msg.sender][distributionIndex] <= amount, "Claim exceeds allowed amount");

        // Mark it claimed and mint the token
        claimedAmount[msg.sender][distributionIndex] += claimableAmount;
        if (currentRound == dist.totalRounds) {
            hasClaimed[msg.sender][distributionIndex] = true;
        }
        require(token.mint(msg.sender, claimableAmount), "Mint failed");

        emit Claimed(msg.sender, claimableAmount, distributionIndex);
    }

    function multiClaim(uint256[] calldata amounts, bytes32[][] calldata merkleProofs, uint256[] calldata distributionIndexes) external {
        require(amounts.length == distributionIndexes.length, "Mismatched inputs");
        require(amounts.length == merkleProofs.length, "Mismatched inputs");

        for (uint256 i = 0; i < amounts.length; i++) {
            claim(amounts[i], merkleProofs[i], distributionIndexes[i]);
        }
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address _MintTo, uint256 _MintAmount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library MerkleProof {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        return computedHash == root;
    }
}
