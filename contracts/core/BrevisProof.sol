// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../lib/Ownable.sol";
import "../lib/Lib.sol";
import "../interface/ISMT.sol";
import "../interface/IZkpVerifier.sol";

contract BrevisProof is Ownable {
    uint32 constant PUBLIC_BYTES_START_IDX = 11 * 32; // the first 10 32bytes are groth16 proof (A/B/C/Commitment), the 11th 32bytes is cPub

    mapping(uint64 => IZkpVerifier) public verifierAddresses; // chainid => snark verifier contract address
    mapping(bytes32 => Brevis.ProofData) public proofs;
    ISMT public smtContract;
    address public brevisRequest;

    event VerifierAddressesUpdated(
        uint64[] chainIds,
        IZkpVerifier[] newAddresses
    );
    event SmtContractUpdated(ISMT smtContract);
    event BrevisRequestUpdated(address brevisRequest);

    constructor(ISMT _smtContract) {
        smtContract = _smtContract;
    }

    // this is only to be called by Proxy via delegateCall as initOwner will require _owner is 0
    function init(ISMT _smtContract) external {
        initOwner();
        smtContract = _smtContract;
    }

    // zk proof
    function submitProof(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs
    ) external returns (bytes32 _requestId) {
        require(verifyRaw(_chainId, _proofWithPubInputs), "proof not valid");
        Brevis.ProofData memory data = unpackProofData(_proofWithPubInputs);
        _requestId = data.commitHash;
        require(
            smtContract.isSmtRootValid(_chainId, data.smtRoot),
            "smt root not valid"
        );
        proofs[_requestId].appCommitHash = data.appCommitHash; // save necessary fields only, to save gas
        proofs[_requestId].appVkHash = data.appVkHash;
    }

    modifier onlyBrevisRequest() {
        require(brevisRequest == msg.sender, "not brevisRequest");
        _;
    }

    // op/avs proof
    function submitOpResult(bytes32 _requestId) external onlyBrevisRequest {
        proofs[_requestId].commitHash = _requestId;
    }

    function validateOpRequest(
        bytes32 _requestId,
        uint64 _chainId,
        Brevis.ExtractInfos calldata _info
    ) external view {
        Brevis.ProofData memory data = proofs[_requestId];
        require(data.commitHash != bytes32(0), "proof not exists");
        bytes memory hashes;

        require(
            _info.receipts.length + _info.stores.length + _info.txs.length <=
                100,
            "exceeds max allowed"
        );

        for (uint256 i = 0; i < _info.receipts.length; i++) {
            bytes memory fieldInfos;
            for (uint256 j = 0; j < _info.receipts[i].logs.length; j++) {
                Brevis.LogInfo memory field = _info.receipts[i].logs[j];
                fieldInfos = abi.encodePacked(
                    fieldInfos,
                    keccak256(
                        abi.encodePacked(
                            field.logIndex,
                            field.value,
                            field.valueFromTopic,
                            field.valueIndex,
                            field.contractAddress,
                            field.logTopic0
                        )
                    )
                );
            }

            hashes = abi.encodePacked(
                hashes,
                keccak256(
                    abi.encodePacked(
                        _info.receipts[i].blkNum,
                        _info.receipts[i].receiptIndex,
                        fieldInfos
                    )
                )
            );
        }

        for (uint256 i = 0; i < _info.stores.length; i++) {
            hashes = abi.encodePacked(
                hashes,
                keccak256(
                    abi.encodePacked(
                        _info.stores[i].blockHash,
                        _info.stores[i].account,
                        _info.stores[i].slot,
                        _info.stores[i].slotValue,
                        _info.stores[i].blockNumber
                    )
                )
            );
        }
        for (uint256 i = 0; i < _info.txs.length; i++) {
            hashes = abi.encodePacked(
                hashes,
                keccak256(
                    abi.encodePacked(
                        _info.txs[i].txHash,
                        _info.txs[i].hashOfRawTxData,
                        _info.txs[i].blockHash,
                        _info.txs[i].blockNumber
                    )
                )
            );
        }

        require(
            keccak256(abi.encodePacked(_chainId, hashes)) == data.commitHash,
            "commitHash and info not match"
        );
    }

    function hasProof(bytes32 _requestId) external view returns (bool) {
        return
            proofs[_requestId].commitHash != bytes32(0) ||
            proofs[_requestId].appCommitHash != bytes32(0);
    }

    function getProofAppData(
        bytes32 _requestId
    ) external view returns (bytes32, bytes32) {
        return (proofs[_requestId].appCommitHash, proofs[_requestId].appVkHash);
    }

    function verifyRaw(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs
    ) private view returns (bool) {
        IZkpVerifier verifier = verifierAddresses[_chainId];
        require(address(verifier) != address(0), "chain verifier not set");
        return verifier.verifyRaw(_proofWithPubInputs);
    }

    function unpackProofData(
        bytes calldata _proofWithPubInputs
    ) internal pure returns (Brevis.ProofData memory data) {
        data.commitHash = bytes32(
            _proofWithPubInputs[PUBLIC_BYTES_START_IDX:PUBLIC_BYTES_START_IDX +
                32]
        );
        data.smtRoot = bytes32(
            _proofWithPubInputs[PUBLIC_BYTES_START_IDX +
                32:PUBLIC_BYTES_START_IDX + 2 * 32]
        );
        data.appCommitHash = bytes32(
            _proofWithPubInputs[PUBLIC_BYTES_START_IDX +
                3 *
                32:PUBLIC_BYTES_START_IDX + 4 * 32]
        );
        data.appVkHash = bytes32(
            _proofWithPubInputs[PUBLIC_BYTES_START_IDX +
                4 *
                32:PUBLIC_BYTES_START_IDX + 5 * 32]
        );
    }

    function updateVerifierAddress(
        uint64[] calldata _chainIds,
        IZkpVerifier[] calldata _verifierAddresses
    ) public onlyOwner {
        require(
            _chainIds.length == _verifierAddresses.length,
            "length not match"
        );
        for (uint256 i = 0; i < _chainIds.length; i++) {
            verifierAddresses[_chainIds[i]] = _verifierAddresses[i];
        }
        emit VerifierAddressesUpdated(_chainIds, _verifierAddresses);
    }

    function updateSmtContract(ISMT _smtContract) public onlyOwner {
        smtContract = _smtContract;
        emit SmtContractUpdated(smtContract);
    }

    function updateBrevisRequest(address _brevisRequest) public onlyOwner {
        brevisRequest = _brevisRequest;
        emit BrevisRequestUpdated(_brevisRequest);
    }
}
