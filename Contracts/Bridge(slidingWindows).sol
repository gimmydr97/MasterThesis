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

    //internal state
    Request[] private requests; //arrived requests 
    mapping(uint => StateProofVerifier.BlockHeader) private lightBlockchain; //block headers of C2 chain
    uint windSize = 10;
    uint[10] window; 
    uint counter = 0;

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

    /** 
    *  @dev This event is emitted whenever a logged request is served by the verify function
    */
    event RequestServed(
    uint indexed requestId, // Request identifier
    address account, // Address of C2 contract
    uint key, // Numeric identifier of the variable
    uint blockId, // Identifier of C2 block
    uint256 reply // Response received by C2 node
    );

    /** 
    *  @dev This event is emitted whenever a new header pass the verification 
    *  and is added to the lightBlockchain of the contract
    */
    event NewBlockAdded(
    bytes32 hash,
    bytes32 stateRootHash,
    uint256 number,
    uint256 timestamp,
    uint256 pos,
    uint256 delblock

    );

    /** 
    *  @dev This event is emitted whenever a header not pass the verification
    *  and so the request is rejected by the contract
    */
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
    *  @return the total number of requests served by the contract
    */
    function getServed() public view returns (uint) {
        return servedCounter;
    }

    /**
    *  @return the number of pending (i.e., not served) requests.
    */
    function getPending() public view returns (uint) {
        return requestCounter-servedCounter;
    }

    /**
    *  @param id identifier of the request
    *  @return the request with the specified identifier
    */
    function getRequest(uint id) public view returns (Request memory) {
        // Check if the supplied index is legal.
        require(0 <= id && id < requests.length, "Error: invalid request id.");
        return requests[id];
    }
    
    /**
    *  @param blockId identifier of the required blockHeader
    *  @return the blockHeader of the specified blockId
    */
    function getBlock(uint blockId) public view returns (StateProofVerifier.BlockHeader memory) {
        return lightBlockchain[blockId];
    }

    /**
    *  @param _account of the contract on C2 of which we want the information
    *  @param _key index of the information in the contract on C2
    *  @param _blockId identifier of the block that represent the update status of the requested variable
    *  @return the identifier of the request that was taken in charge.
    */
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

    /**
    *  @dev if the blockHeader passed pass the verification the block is saved in the contract
    *  @param _blockHeader the structure that contain the hash of the blockHeader and the header's RLP encode
    *  @return the identifier of the blockHash saved.
    */
    function saveBlock(BlockHeader memory _blockHeader ) public returns (uint) {
        
        //chack that the block to be added is ok
        StateProofVerifier.BlockHeader memory bHeader = verifyBlockHeader(_blockHeader);

        //add the checked block header to the lightBlockchain in sliding window mode:
        //save the block number that have to go out from the window 
        uint toDelate = window[counter%windSize];
        //update the window with the new block that have to enter in the wondow
        window[counter%windSize] = bHeader.number;
        //delete form the lightblockchain the block that have to go out from the window 
        delete lightBlockchain[toDelate];
        //insert in the lightblockchain the block that have to enter in the window
        lightBlockchain[window[counter%windSize]] = bHeader;
        //update the counter of block inserted
        counter = counter + 1;
        
        emit NewBlockAdded(bHeader.hash, bHeader.stateRootHash, bHeader.number, bHeader.timestamp,counter%windSize, toDelate);

        return  lightBlockchain[bHeader.number].number;
    }

    /**
    *  @dev verification that see if the block is present in contract's lightBlockchain
    *  @param _requestId id of the request that need for save the request as rejected if the blockId is not present in lightBlockchain
    *  @param _blockId identifier of the block that represent the update status of the requested variable
    *  @return true if the block is saved false otherwise
    */
    function blockIsPresent(uint _requestId, uint _blockId ) public returns (bool){

        bool isPresent = true;

        //verify that the requested block is present in contract's lightBlockchain
        if (lightBlockchain[_blockId].number == 0){
            emit BlockNotFound(_blockId);
            isPresent = false;

            //The request is saved as served but rejected with response = 0
            requests[_requestId].served = true;
            requests[_requestId].response = 0;
        }

        return isPresent;
    }

    /**
    *  @dev verification for block header. 
    *  @param _blockHeader the structure that contain the hash of the blockHeader and the header's RLP encode
    *  @return the parsed header if it pass the check
    */
    function verifyBlockHeader (BlockHeader memory _blockHeader ) 
                public returns (StateProofVerifier.BlockHeader memory){

        //parse the block header
        StateProofVerifier.BlockHeader memory header = 
                                       StateProofVerifier.parseBlockHeader(_blockHeader.RLPHeader);

        //checks that the hash field passed as a paramenter, matches the has computed via kekka256 of the RLP encoding
        require(_blockHeader.hash == header.hash,  "blockhash mismatch"); 

        return header;
    }

    /**
    *  @dev verification for account proof 
    *  @param _stateProof the structure that contain all the fields arrived from the C2 chain proof request
    *  @param _blockId identifier of the block that represent the update status of the requested variable
    *  @return the parsed account if it pass the check
    */
    function verifyAccountProof(StateProof memory _stateProof, uint _blockId) 
                public returns (StateProofVerifier.Account memory){

        //parse the account proof
        RLPReader.RLPItem[] memory accountProof = parseProofToRlpReader(_stateProof.accountProof);

        //verify the account proof
        StateProofVerifier.Account memory account = 
            StateProofVerifier.extractAccountFromProof(keccak256(abi.encodePacked(_stateProof.account)),
                                                       lightBlockchain[_blockId].stateRootHash,
                                                       accountProof);
        return account;
    }

    /**
    *  @dev verification for storage proof
    *  @param _stateProof the structure that contain all the fields arrived from the C2 chain proof request
    *  @return the value searched if the storage proof pass the check
    */
    function verifiyStorageProof(StateProof memory _stateProof)
                public returns (StateProofVerifier.SlotValue memory){

        //parse the storage proof
        RLPReader.RLPItem[] memory storageProof = parseProofToRlpReader(_stateProof.storageProof);

        //verify the storage proof
        StateProofVerifier.SlotValue memory slotValue = 
            StateProofVerifier.extractSlotValueFromProof(keccak256(abi.encodePacked(_stateProof.key)),
                                                         _stateProof.storageRoot,
                                                         storageProof);
        return slotValue;
    }

    /**
    *  @dev verification for all the state proof
    *  @param _requestId the id of the request that we serve with this function 
    *  @param _stateProof the structure that contain all the fields arrived from the C2 chain proof request
    *  @param _blockId identifier of the block that represent the update status of the requested variable
    *  @return true If all verifications are passed
    */
    function verify(uint _requestId, StateProof memory _stateProof, uint _blockId )
            public returns (bool){
        
        //check that the block[_blockId] is present in the "lightBlockchain" of the contract 
        require(blockIsPresent(_requestId, _blockId) == true, "block is not present in the lightBlockchain");

        //check account proof
        StateProofVerifier.Account memory account = verifyAccountProof(_stateProof, _blockId);

        //check storage proof
        StateProofVerifier.SlotValue memory slotValue = verifiyStorageProof(_stateProof);
        
        //The proof is accepted: first we record this fact on the blockchain.
        requests[_requestId].served = true;
        requests[_requestId].response = slotValue.value;

        // Then we trigger a `RequestServed` event to notify all possible listeners.
        emit RequestServed(_requestId, requests[_requestId].account,requests[_requestId].key, 
                            requests[_requestId].blockId, requests[_requestId].response);
        return true;

    } 

    /**
    *  @dev auxiliary function that parse a generic proof in a list of RLP encode
    *  @param _proof list that rapresent the proof for the requested value 
    *  @return the proof in the RLPItem list form
    */
    function parseProofToRlpReader(bytes[] memory _proof) internal pure returns (RLPReader.RLPItem[] memory){
        RLPReader.RLPItem[] memory proof = new RLPReader.RLPItem[](_proof.length);
        for (uint i = 0; i < _proof.length; i++) {
            proof[i] = RLPReader.toRlpItem(_proof[i]);
        }
        return proof;
    }


}
