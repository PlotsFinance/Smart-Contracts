// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract MerkleDistributor {
    IERC20 public token;
    address public owner;

    uint256 public timeUnit = 5 minutes; // Set to 30 days for production

    struct Distribution {
        bytes32 merkleRoot;    // Merkle root for this distribution
        uint256 cliffPeriod;   // Cliff period before vesting starts
        uint256 tgePercentage; // Initial percentage claimable at TGE
        uint256 totalRounds;   // Total number of vesting rounds
    }

    Distribution[] public distributions;

    mapping(address => mapping(uint256 => uint256)) public claimedAmount; // Tracks claimed amounts
    mapping(address => mapping(uint256 => bool)) public hasClaimed; // Tracks if a user has claimed all tokens in a distribution

    event Claimed(address indexed account, uint256 amount, uint256 distributionIndex);


    constructor(
        bytes32[] memory _merkleRoots,
        uint256[] memory _cliffPeriods,
        uint256[] memory _tgePercentages,
        uint256[] memory _totalRounds
    ) {
        require(
            _merkleRoots.length == _cliffPeriods.length &&
            _merkleRoots.length == _tgePercentages.length &&
            _merkleRoots.length == _totalRounds.length,
            "Input arrays length mismatch"
        );

        owner = msg.sender;

        for (uint256 i = 0; i < _merkleRoots.length; i++) {
            distributions.push(Distribution({
                merkleRoot: _merkleRoots[i],
                cliffPeriod: block.timestamp + (_cliffPeriods[i] * timeUnit),
                tgePercentage: _tgePercentages[i],
                totalRounds: _totalRounds[i]
            }));
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /** @notice Allows users to claim their tokens or others to claim on their behalf */
    function claim(
        address claimant,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint256 distributionIndex
    ) public {
        require(distributionIndex < distributions.length, "Invalid distribution index");
        Distribution storage dist = distributions[distributionIndex];

        // Verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(claimant, amount));
        require(MerkleProof.verify(merkleProof, dist.merkleRoot, node), "Invalid proof");

        // Calculate TGE and vesting amounts
        uint256 tgeAmount = (amount * dist.tgePercentage) / 100;
        uint256 vestingAmount = amount - tgeAmount;

        uint256 totalClaimableAmount;

        if (block.timestamp < dist.cliffPeriod) {
            // Only TGE amount is claimable before cliff ends
            totalClaimableAmount = tgeAmount;
        } else {
            uint256 totalVestingRounds = dist.totalRounds - 1; // Exclude TGE round

            if (totalVestingRounds == 0) {
                // All tokens are claimable at TGE
                totalClaimableAmount = amount;
            } else {
                uint256 perRoundVestingAmount = vestingAmount / totalVestingRounds;

                uint256 elapsedTime = block.timestamp - dist.cliffPeriod;
                uint256 roundsElapsed = elapsedTime / timeUnit;

                // Ensure at least one round is counted if any time has passed
                if (roundsElapsed == 0 && elapsedTime > 0) {
                    roundsElapsed = 1;
                }

                if (roundsElapsed > totalVestingRounds) {
                    roundsElapsed = totalVestingRounds;
                }

                uint256 vestedAmount = perRoundVestingAmount * roundsElapsed;

                totalClaimableAmount = tgeAmount + vestedAmount;
            }
        }

        // Calculate amount to claim
        uint256 amountToClaim = totalClaimableAmount - claimedAmount[claimant][distributionIndex];
        require(amountToClaim > 0, "No tokens to claim");

        // Update claimed amount
        claimedAmount[claimant][distributionIndex] += amountToClaim;

        // Check if fully claimed
        if (claimedAmount[claimant][distributionIndex] == amount) {
            hasClaimed[claimant][distributionIndex] = true;
        }

        // Mint tokens to the claimant
        require(token.mint(claimant, amountToClaim), "Mint failed");

        emit Claimed(claimant, amountToClaim, distributionIndex);
    }

    /** @notice Allows batch claiming for efficiency */
    function multiClaim(
        address[] calldata claimants,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs,
        uint256[] calldata distributionIndexes
    ) external {
        require(
            amounts.length == distributionIndexes.length &&
            amounts.length == merkleProofs.length &&
            claimants.length == amounts.length,
            "Mismatched inputs"
        );

        for (uint256 i = 0; i < amounts.length; i++) {
            claim(claimants[i], amounts[i], merkleProofs[i], distributionIndexes[i]);
        }
    }

    function setToken(address _token) public onlyOwner {
        require(address(token) == address(0), "Token already set");
        token = IERC20(_token);

        owner = address(0);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
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
                // Hash(current computed hash + current proof element)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current proof element + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Verify the computed hash matches the root
        return computedHash == root;
    }
}
