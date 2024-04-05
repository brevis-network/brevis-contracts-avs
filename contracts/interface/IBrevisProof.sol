// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../lib/Lib.sol";

interface IBrevisProof {
    function submitProof(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs
    ) external returns (bytes32 _requestId);

    function hasProof(bytes32 _requestId) external view returns (bool);

    // return appCommitHash and appVkHash
    function getProofAppData(
        bytes32 _requestId
    ) external view returns (bytes32, bytes32);

    function submitOpResult(bytes32 _requestId) external;

    function validateOpRequest(
        bytes32 _requestId,
        uint64 _chainId,
        Brevis.ExtractInfos calldata _info
    ) external view;
}
