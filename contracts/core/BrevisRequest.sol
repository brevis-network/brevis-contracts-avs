// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../lib/FeeVault.sol";
import "../interface/IBrevisProof.sol";
import "../interface/IBrevisApp.sol";
import "../interface/IBrevisEigen.sol";

contract BrevisRequest is FeeVault {
    uint256 public requestTimeout;
    IBrevisProof public brevisProof;
    IBrevisEigen public brevisEigen;

    enum RequestStatus {
        Pending,
        ZkAttested,
        OpSubmitted,
        OpQueryDataSubmitted,
        OpDisputing,
        OpDisputed,
        OpAttested,
        Refunded
    }

    enum Option {
        ZkMode,
        OpMode_MIMC,
        OpMode_KECCAK
    }

    struct Request {
        uint256 deadline;
        uint256 fee;
        address refundee;
        IBrevisApp callback;
        RequestStatus status;
        Option option;
    }
    mapping(bytes32 => Request) public requests;

    event RequestTimeoutUpdated(uint256 from, uint256 to);
    event RequestSent(
        bytes32 requestId,
        address sender,
        uint256 fee,
        IBrevisApp callback,
        Option option
    );
    event RequestFulfilled(bytes32 requestId);
    event RequestRefunded(bytes32 requestId);

    constructor(
        address _feeCollector,
        IBrevisProof _brevisProof,
        IBrevisEigen _brevisEigen
    ) FeeVault(_feeCollector) {
        brevisProof = _brevisProof;
        brevisEigen = _brevisEigen;
    }

    // this is only to be called by Proxy via delegateCall as initOwner will require _owner is 0
    function init(
        address _feeCollector,
        IBrevisProof _brevisProof,
        IBrevisEigen _brevisEigen
    ) external {
        initOwner();
        feeCollector = _feeCollector;
        brevisProof = _brevisProof;
        brevisEigen = _brevisEigen;
    }

    function setBrevisEigen(IBrevisEigen _brevisEigen) external onlyOwner {
        brevisEigen = _brevisEigen;
    }

    function sendRequest(
        bytes32 _requestId,
        address _refundee,
        IBrevisApp _callback,
        Option _option
    ) external payable {
        require(requests[_requestId].deadline == 0, "request already in queue");
        require(_refundee != address(0), "refundee not provided");
        requests[_requestId] = Request(
            block.timestamp + requestTimeout,
            msg.value,
            _refundee,
            _callback,
            RequestStatus.Pending,
            _option
        );
        emit RequestSent(_requestId, msg.sender, msg.value, _callback, _option);
    }

    // zk mode
    function fulfillRequest(
        bytes32 _requestId,
        uint64 _chainId,
        bytes calldata _proof,
        bytes calldata _appCircuitOutput
    ) external {
        require(
            !IBrevisProof(brevisProof).hasProof(_requestId),
            "proof already generated"
        );

        bytes32 reqIdFromProof = IBrevisProof(brevisProof).submitProof(
            _chainId,
            _proof
        ); // will be reverted when proof is not valid
        require(_requestId == reqIdFromProof, "requestId and proof not match");
        requests[_requestId].status = RequestStatus.ZkAttested;

        emit RequestFulfilled(_requestId);

        address app = address(requests[_requestId].callback);
        if (app != address(0)) {
            // No matter if the call is success or not. The relayer should set correct gas limit.
            // If the call exceeds the gasleft(), as the proof data is saved ahead,
            // anyone can still call the app.callback directly to proceed
            app.call(
                abi.encodeWithSelector(
                    IBrevisApp.brevisCallback.selector,
                    _requestId,
                    _appCircuitOutput
                )
            );
        }
    }

    function refund(bytes32 _requestId) public {
        require(block.timestamp > requests[_requestId].deadline);
        require(
            !IBrevisProof(brevisProof).hasProof(_requestId),
            "proof already generated"
        );
        require(requests[_requestId].deadline != 0, "request not in queue");
        requests[_requestId].deadline = 0; //reset deadline, then user is able to send request again
        (bool sent, ) = requests[_requestId].refundee.call{
            value: requests[_requestId].fee,
            gas: 50000
        }("");
        require(sent, "send native failed");
        requests[_requestId].status = RequestStatus.Refunded;
        emit RequestRefunded(_requestId);
    }

    function setRequestTimeout(uint256 _timeout) external onlyOwner {
        uint256 oldTimeout = requestTimeout;
        requestTimeout = _timeout;
        emit RequestTimeoutUpdated(oldTimeout, _timeout);
    }

    // op/avs mode
    enum AskForType {
        NULL,
        QueryData,
        Proof
    }

    struct RequestExt {
        uint256 canChallengeBefore;
        AskForType askFor;
        uint256 shouldRespondBefore;
    }
    mapping(bytes32 => RequestExt) public requestExts;
    mapping(bytes32 => bytes32) public keccakToMimc;

    uint256 public challengeWindow; // in seconds
    uint256 public responseTimeout;
    event ChallengeWindowUpdated(uint256 from, uint256 to);
    event ResponseTimeoutUpdated(uint256 from, uint256 to);

    function setChallengeWindow(uint256 _challengeWindow) external onlyOwner {
        uint256 oldChallengeWindow = challengeWindow;
        challengeWindow = _challengeWindow;
        emit ChallengeWindowUpdated(oldChallengeWindow, _challengeWindow);
    }

    function setResponseTimeout(uint256 _responseTimeout) external onlyOwner {
        uint256 oldResponseTimeout = responseTimeout;
        responseTimeout = _responseTimeout;
        emit ResponseTimeoutUpdated(oldResponseTimeout, _responseTimeout);
    }

    function queryRequestStatus(
        bytes32 _requestId
    ) external view returns (RequestStatus) {
        if (
            (requests[_requestId].status == RequestStatus.OpSubmitted ||
                requests[_requestId].status ==
                RequestStatus.OpQueryDataSubmitted) &&
            requestExts[_requestId].canChallengeBefore <= block.timestamp
        ) {
            return RequestStatus.OpAttested;
        }

        if (
            requests[_requestId].status == RequestStatus.OpDisputing &&
            requestExts[_requestId].shouldRespondBefore <= block.timestamp
        ) {
            return RequestStatus.OpDisputed;
        }

        return requests[_requestId].status;
    }

    event OpRequestsFulfilled(bytes32[] requestIds, bytes[] queryURLs);

    // Op functions
    function fulfillOpRequests(
        bytes32[] calldata _requestIds,
        bytes[] calldata _queryURLs
    ) external {
        require(_requestIds.length > 0, "invalid requestIds");
        require(_requestIds.length == _queryURLs.length);

        // must already verified in brevisEigen
        brevisEigen.mustVerified(_requestIds);

        for (uint i = 0; i < _requestIds.length; i++) {
            bytes32 reqId = _requestIds[i];
            require(
                !IBrevisProof(brevisProof).hasProof(reqId),
                "proof already generated"
            );
            brevisProof.submitOpResult(reqId);
            requests[reqId].status = RequestStatus.OpSubmitted;
            requestExts[reqId].canChallengeBefore =
                block.timestamp +
                challengeWindow;
        }

        emit OpRequestsFulfilled(_requestIds, _queryURLs);
    }

    event AskFor(bytes32 indexed requestId, AskForType askFor, address from);
    event QueryDataPost(bytes32 indexed requestId);
    event ProofPost(bytes32 indexed requestId);

    function askForQueryData(bytes32) external payable {
        revert("not implemented");
    }

    function postQueryData(bytes32, bytes calldata) external pure {
        revert("not implemented");
    }

    // after postQueryData with OpMode_MIMC
    function challengeQueryData(bytes calldata) external pure {
        revert("not implemented");
    }

    function askForProof(bytes32) external payable {
        revert("not implemented");
    }

    function postProof(bytes32, uint64, bytes calldata) external pure {
        revert("not implemented");
    }
}
