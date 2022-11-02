 //SPDX-License-Identifier = Gianmaria di Rito

pragma solidity 0.6.0;
pragma experimental ABIEncoderV2;

import{StateProofVerifier} from "Contracts/StateProofVerifier.sol";
import {RLPReader} from "Contracts/RLPReader.sol";

contract Bridge {

    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;


    // Counts the total number of requests.
    uint private requestCounter;
    // Counts the number of served requests.
    uint private servedCounter;

    struct BlockHeader{
        bytes32 hash;   //hash of the block used to verify its correctness 
        bytes RLPHeader; //rlp encoding of the block header to be checked
    }

    struct StateProof {
        
        address account; // Address of the C2 contract
        bytes [] accountProof; // Proof that certifies the existence of the contract
        bytes32 storageRoot; // 
        bytes key; //
        bytes value; //
        bytes [] storageProof; // Proof that certifies the existence of the variable inside the contract
    }

    struct Request {
    address account; // Address of the C2 contract we want to read data from.
    uint key; // Numeric identifier of the C2 variable we want to read.
    uint blockId; // Identifier of the C2 block we want to read data from.
    uint date; // Timestamp of the request.
    bool served;  // Equals true if the request has been served, false otherwise.
    uint256 response; // The value associated with the variable.
    }

    Request[] private requests;
    mapping(uint => StateProofVerifier.BlockHeader) private lightBlockchain;
    

    /**
    *  @dev This event is emitted whenever a new request is created
    *  and saved inside the contract.
    */
    event RequestLogged(
        uint indexed requestId, // Request identifier
        address account, // Address of C2 contract
        uint key, // Numeric identifier of the variable
        uint blockId // Identifier of C2 block
    );

    event RequestServed(
    uint indexed requestId, // Request identifier
    address account, // Address of C2 contract
    uint key, // Numeric identifier of the variable
    uint blockId, // Identifier of C2 block
    uint256 reply // Response received by C2 node
    );

    event NewBlockAdded(
    bytes32 hash,
    bytes32 stateRootHash,
    uint256 number,
    uint256 timestamp
    );

    event BlockNotFound(
        uint256 number
    );

    /**
    *  @dev This data structure keeps track of all requests.
    *  NOTICE: the id of a request coincides with its index in the array.
    */
    function getTotal() public view returns (uint) {
        return requestCounter;
    }

    /**
    *  @dev Returns the number of served requests.
    *  @return the total number of requests served by the contract
    */
    function getServed() public view returns (uint) {
        return servedCounter;
    }

    /**
    *  @dev Returns the number of pending (i.e., not served) requests.
    *  @return the total number of pending requests
    */
    function getPending() public view returns (uint) {
        return requestCounter-servedCounter;
    }

    /**
    *  @dev Returns the request with the given identifier.
    *  @param id identifier of the request
    *  @return the request with the specified identifier
    */
    function getRequest(uint id) public view returns (Request memory) {
        // Check if the supplied index is legal.
        require(0 <= id && id < requests.length, "Error: invalid request id.");
        return requests[id];
    }
    
    function getBlock(uint blockId) public view returns (StateProofVerifier.BlockHeader memory) {
        return lightBlockchain[blockId];
    }

    function saveBlock(BlockHeader memory _blockHeader ) public returns (uint) {
        //verify that the blockHeader are ok 
        StateProofVerifier.BlockHeader memory bHeader = 
            StateProofVerifier.verifyBlockHeader(_blockHeader.hash, _blockHeader.RLPHeader);
        lightBlockchain[bHeader.number] = bHeader;
        emit NewBlockAdded(bHeader.hash, bHeader.stateRootHash, bHeader.number, bHeader.timestamp);
        return  lightBlockchain[bHeader.number].number;
    }

    function request(address _account, uint _key, uint _blockId) public returns (uint) {
        Request memory r;
        uint requestId = requestCounter;
        r.account = _account;
        r.key = _key;
        r.blockId = _blockId;
        r.date = block.timestamp;
        r.served = false;
        requests.push(r);
        emit RequestLogged(requestId, _account, _key, _blockId);
        requestCounter++;
        return requestId;
    }

    //tramite web3 chiamando web3.eth.get_proof(account,position,blockNumber) ottengo l'address
    //tramite web3 chiamando web3.eth.getBlock(blockNumber) ottengo la verifica sui dati del blocco e da esso posso ricavare lo stateRoot
    function verify(
        uint _requestId,
        StateProof memory _stateProof,
        uint _blockId 
    ) public returns (bool){
        /*
        //verify that the blockHeader are ok 
        StateProofVerifier.BlockHeader memory bHeader = 
            StateProofVerifier.verifyBlockHeader(_blockHeader.hash, _blockHeader.RLPHeader);
        */
        if (lightBlockchain[_blockId].number == 0){
            emit BlockNotFound(_blockId);
            return false;
        }
        

        //parse the account proof
        RLPReader.RLPItem[] memory accountProof = parseProofToRlpReader(_stateProof.accountProof);

        //verify the account proof
        StateProofVerifier.Account memory account = 
            StateProofVerifier.extractAccountFromProof(keccak256(abi.encodePacked(_stateProof.account)),
                                                       lightBlockchain[_blockId].stateRootHash,
                                                       accountProof);
        //parse the storage proof
        RLPReader.RLPItem[] memory storageProof = parseProofToRlpReader(_stateProof.storageProof);

        //verify the storage proof
        StateProofVerifier.SlotValue memory slotValue = 
            StateProofVerifier.extractSlotValueFromProof(keccak256(abi.encodePacked(_stateProof.key)),
                                                         _stateProof.storageRoot,
                                                         storageProof);

        //The proof is accepted: first we record this fact on the blockchain.
        requests[_requestId].served = true;
        requests[_requestId].response = slotValue.value;
        // Then we trigger a `RequestServed` event to notify all possible listeners.
        emit RequestServed(_requestId, requests[_requestId].account,requests[_requestId].key, 
                            requests[_requestId].blockId, requests[_requestId].response);
        return true;

    } 

    function parseProofToRlpReader(bytes[] memory _proof) internal pure returns (RLPReader.RLPItem[] memory){
        RLPReader.RLPItem[] memory proof = new RLPReader.RLPItem[](_proof.length);
        for (uint i = 0; i < _proof.length; i++) {
            proof[i] = RLPReader.toRlpItem(_proof[i]);
        }
        return proof;
    }


}
