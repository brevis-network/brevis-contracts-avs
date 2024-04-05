// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interface/IBrevisProof.sol";

abstract contract BrevisApp {
    IBrevisProof public immutable brevisProof;

    constructor(IBrevisProof _brevisProof) {
        brevisProof = _brevisProof;
    }

    // zk callback
    function brevisCallback(
        bytes32 _requestId,
        bytes calldata _appCircuitOutput
    ) external {
        (bytes32 appCommitHash, bytes32 appVkHash) = IBrevisProof(brevisProof)
            .getProofAppData(_requestId);
        require(
            appCommitHash == keccak256(_appCircuitOutput),
            "failed to open output commitment"
        );
        handleProofResult(_requestId, appVkHash, _appCircuitOutput);
    }

    function handleProofResult(
        bytes32 _requestId,
        bytes32 _vkHash,
        bytes calldata _appCircuitOutput
    ) internal virtual {
        // to be overrided by custom app
    }

    // op/avs call
    function validateOpRequest(
        bytes32 _requestId,
        uint64 _chainId,
        Brevis.ExtractInfos memory _extractInfos
    ) public view virtual returns (bool) {
        brevisProof.validateOpRequest(_requestId, _chainId, _extractInfos);
        return true;
    }
}
