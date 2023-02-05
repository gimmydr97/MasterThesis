 //SPDX-License-Identifier = Gianmaria di Rito

pragma solidity 0.6.0;
pragma experimental ABIEncoderV2;

import{StateProofVerifier} from "Contracts/StateProofVerifier.sol";
import {RLPReader} from "Contracts/RLPReader.sol";

contract Bridge {

    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

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
    // Counts the total number of requests.
    uint private requestCounter;
    // Counts the number of served requests.
    uint private servedCounter;
    //arrived requests
    Request[] private requests; 

    uint arrSize; //size for the lightBlockchain array
    uint counter = 0; //conter which counts the number of C2 blocks arrived in the bridge contract
    uint lastKey = 0; //variable that save the block number of the last block saved
    StateProofVerifier.BlockHeader[] private lightBlockchain; //array for save the block of C2

    constructor(uint _arrSize) public {
        arrSize = _arrSize;
        //initialize to 0 the arrSize position of lightBlockchain
        for(uint i = 0; i < _arrSize; i++){
            lightBlockchain.push(StateProofVerifier.BlockHeader(0,0,0,0));
        }
        
    }
    
    /**
    *  @dev if the blockHeader passed pass the verification the block is saved in the contract
    *  @param _blockHeader the structure that contain the hash of the blockHeader and the header's RLP encode
    *  @return the identifier of the blockHash saved.
    */
    function saveBlock(BlockHeader memory _blockHeader ) public returns (uint) {
        
        //chack that the block to be added is ok
        StateProofVerifier.BlockHeader memory bHeader = verifyBlockHeader(_blockHeader);

        uint toDelate = 0;
        //if the block that you are trying to save in lightBlockchain is newer than the one in counter%arrSize psition
            if(bHeader.number > lightBlockchain[counter%arrSize].number){
                //save in toDelate variable the that position
                toDelate = lightBlockchain[counter%arrSize].number;
                //update the array in that position with the new block 
                lightBlockchain[counter%arrSize] = bHeader;
                //update counter
                counter = counter +1 ;
                //update lastKey
                lastKey = bHeader.number;
            }

        emit NewBlockAdded(bHeader.hash, bHeader.stateRootHash, bHeader.number, bHeader.timestamp,(counter-1)%arrSize, toDelate);

        return  lightBlockchain[counter%arrSize].number;
    }

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
    *  @dev check if the block is present in contract's lightBlockchain
    *  @param _requestId id of the request that need for save the request as rejected if the blockId is not present in lightBlockchain
    *  @param _blockId identifier of the block that represent the update status of the requested variable
    *  @return true if the block is saved false otherwise
    */
    function blockIsPresent(uint _requestId, uint _blockId ) public returns (bool){

        //verify that the requested block is present in contract's lightBlockchain
        bool isPresent = true;
        //difference between last saved block and the numer of the block required by the verificatio
        uint diff = lastKey - _blockId;

        //if lastKey < _blockId  (and so the required block is bigger than the last inserted block in the lightblockchain) or
        //the required block is too outdated  or
        //the required block is in the range of the arraySize but not saved in the lightBlockchain (missing block)
        if(diff < 0  || diff >= arrSize || lightBlockchain[((counter-1)%arrSize)-diff].number != _blockId){  
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
        //difference between last saved block and the numer of the block required by the verification 
        uint diff = lastKey - _blockId;
        //verify the account proof
        StateProofVerifier.Account memory account = 
            StateProofVerifier.extractAccountFromProof(keccak256(abi.encodePacked(_stateProof.account)),
                                                       lightBlockchain[((counter-1)%arrSize)-diff].stateRootHash,
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
        if(blockIsPresent(_requestId, _blockId) == true){
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

        return false;

    } 

    /*//non funziona perchè con get_proof è come se si facesse una foto ad un certo momento(rappresentato dal blocco corrente)
    //la foto sarà quindi coerente solo a quel momento quindi non possiamo verificarla senza avere l'info sul momento 
    function verify(uint _requestId, StateProof memory _stateProof)
        public returns (bool){
        
        
            //check account proof
            StateProofVerifier.Account memory account = verifyAccountProof(_stateProof, lastKey);

            //check storage proof
            StateProofVerifier.SlotValue memory slotValue = verifiyStorageProof(_stateProof);
            
            //The proof is accepted: first we record this fact on the blockchain.
            requests[_requestId].served = true;
            requests[_requestId].response = slotValue.value;

            // Then we trigger a `RequestServed` event to notify all possible listeners.
            emit RequestServed(_requestId, requests[_requestId].account,requests[_requestId].key, 
                                requests[_requestId].blockId, requests[_requestId].response);
            return true;

    }*/

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
