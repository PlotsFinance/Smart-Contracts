// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MerkleDistributor {
    IERC20 public token = IERC20(address(0x00BaA09F96928A168cd76c949ee9668C50EA2F44));  // Set token address
    bytes32 public merkleRoot = bytes32(0xcc441908cae76b8dd0cf700c92601d421378476e4cc67221cfa8379640806f26);  // Set merkleRoot
    address public owner;
    
    uint256 public startTime;
    uint256 constant ROUND_DURATION = 900;  // Duration of each round (15 minutes)
    uint256 constant TOTAL_ROUNDS = 7;  // TGE + 6 rounds

    mapping(address => uint256) public claimedAmount;
    mapping(address => bool) public hasClaimed;

    event Claimed(address indexed account, uint256 amount);
    event MerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);

    constructor() {
        owner = msg.sender;
        startTime = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newMerkleRoot;
        emit MerkleRootUpdated(oldRoot, newMerkleRoot);
    }

    function claim(uint256 amount, bytes32[] calldata merkleProof) external {
        require(!hasClaimed[msg.sender], "Already claimed");

        // Verify the merkle proof (commented out for now).
        // bytes32 node = keccak256(abi.encodePacked(StringUtils.concatenate(msg.sender, amount)));
        // require(MerkleProof.verify(merkleProof, merkleRoot, node), "Invalid proof");

        // Calculate claimable amount based on the round
        uint256 currentRound = (block.timestamp - startTime) / ROUND_DURATION + 1;
        require(currentRound <= TOTAL_ROUNDS, "Claim period is over");

        uint256 claimableAmount;
        if (currentRound == 1) {
            claimableAmount = amount * 20 / 100;
        } else {
            uint256 remainingAmount = amount - claimedAmount[msg.sender];
            claimableAmount = remainingAmount / (TOTAL_ROUNDS - (currentRound - 1));
        }

        // Mark it claimed and send the token
        claimedAmount[msg.sender] += claimableAmount;
        if (currentRound == TOTAL_ROUNDS) {
            hasClaimed[msg.sender] = true;
        }
        require(token.transfer(msg.sender, claimableAmount), "Transfer failed");

        emit Claimed(msg.sender, claimableAmount);
    }
}

library StringUtils {
    function concatenate(address account, uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(toString(account), uint2str(amount)));
    }

    function toString(address account) internal pure returns (string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            bstr[--k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(uint256 amount) external returns (bool);
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

