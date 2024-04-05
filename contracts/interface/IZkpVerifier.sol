// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IZkpVerifier {
    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[2] commitment;
    }

    function verifyRaw(bytes calldata proofData) external view returns (bool r);
}
