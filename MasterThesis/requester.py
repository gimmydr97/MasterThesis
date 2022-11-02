from web3 import Web3,HTTPProvider
from solcx import compile_source
from hexbytes import HexBytes
from rlp import encode
from threading import Thread
import time

def compile_source_file(file_path):
	
    with open(file_path, 'r') as f: 
        source = f.read()
	#restituisce la tupla [abi,bin] per il primo elemento del dizionario e cioè i dati relativi  a tryOnChain	
    return compile_source(source, output_values=["abi", "bin"], solc_version="0.6.0").get('<stdin>:Bridge') 

def deploy_contract(w3, contract_interface):
        tx_hash = w3.eth.contract(
                abi=contract_interface['abi'],
                bytecode=contract_interface['bin']).constructor().transact()
        address = w3.eth.get_transaction_receipt(tx_hash)['contractAddress']
        return address

def RLPEncodeBlockHeader(w3,blockId):

    block = w3.eth.get_block(blockId)
    blockHeader = [
        block.parentHash,
        block.sha3Uncles,
        HexBytes(block.miner),
        block.stateRoot,
        block.transactionsRoot,
        block.receiptsRoot,
        block.logsBloom,
        HexBytes(hex(block.difficulty)),
        HexBytes(hex(block.number)),
        HexBytes(hex(block.gasLimit)),
        HexBytes(hex(block.gasUsed)),
        HexBytes(hex(block.timestamp)),
        block.extraData,
        block.mixHash,
        block.nonce,
        #HexBytes(hex(block.baseFeePerGas)) //parametro aggiunto all'header tra il bloccco 12000000 e 13000000
        #block.size
        #block.totalDifficulty
    ]

    #check that need for the new type of header with baseFeePerGas field 
    if len(block) != 20:
        blockHeader.append(HexBytes(hex(block.baseFeePerGas)))
        
    for i in range(0,len(blockHeader)):
            if blockHeader[i] == HexBytes("0x0") or blockHeader[i] == HexBytes("0x00"):
                blockHeader[i] = HexBytes("0x")

    blockHeader = [
        block.hash,
        HexBytes(encode(blockHeader))
    ]

    return blockHeader



#web3 for deploy the contract on c1
chainAddress = 'http://127.0.0.1:8545'
web3 = Web3(HTTPProvider(chainAddress))
web3.eth.defaultAccount = web3.eth.accounts[0]

#w3 for retrive the block of c2 (in this example is the etherium blockhain) and save they as a Lightweight blockchain on the contract
w3 = Web3(HTTPProvider('https://evocative-stylish-isle.discover.quiknode.pro/6ad754e3368653a2665e62db8659b9f179a3ae43/'))


def sendRequest(bridgeContract,_proofAddress,_key,_blockId):
    #send a verification request to the contract
    txt_hash = bridgeContract.functions.request(_proofAddress, int(_key), int(_blockId)).transact()
    txn_receipt = web3.eth.wait_for_transaction_receipt(txt_hash)
    print(txn_receipt)

    # Listen for the reply and the result.
    requestId = (bridgeContract.functions.getTotal().call()) -1
    event_filter_good = bridgeContract.events.RequestServed.createFilter(fromBlock='latest', argument_filters={'requestId': requestId})
    event_filter_bad = bridgeContract.events.BlockNotFound.createFilter(fromBlock='latest')
    
    received = False

    while not received:
                entries_good = event_filter_good.get_new_entries()
                entries_bad = event_filter_bad.get_new_entries()
                if (len(entries_good) > 0 or len(entries_bad) > 0 ):
                        if(len(entries_good) > 0 ):
                            print(entries_good)
                        else:
                            print(entries_bad)

                        received = True
                else:
                    time.sleep(3)
        
def retriveNewBlock(bridgeContract):

    blockNumber = 0
    event_filter = bridgeContract.events.NewBlockAdded.createFilter(fromBlock='latest')

    while True:
        #se c'è un nuovo blocco (in realtà se l'aggiunta di blocchi è più veloce di un ciclo della funzioni questa condizione non va bene)
        if(blockNumber != w3.eth.block_number):
            
            blockNumber = w3.eth.block_number
            blockHeader = RLPEncodeBlockHeader(w3,blockNumber)

            txt_hash = bridgeContract.functions.saveBlock(blockHeader).transact()
            web3.eth.wait_for_transaction_receipt(txt_hash)
            
            received = False

            while not received:
                        entries = event_filter.get_new_entries()
                        if (len(entries) > 0):
                            received = True
                        else:
                            time.sleep(3)
            time.sleep(5)

    
def main():
    
    print('requester has started!')
    print('usage:\n 1) address for the proof\n 2) key for the proof\n 3) block id')  
    go = 1

    #compile contract and initialize it
    contract_interface = compile_source_file('Contracts/Bridge.sol')
    #deploy contract
    contractAddress = deploy_contract(web3,contract_interface)

    bridgeContract = web3.eth.contract(address=contractAddress, abi=contract_interface["abi"])
    print(w3.eth.block_number)
    t = Thread(target=retriveNewBlock, args=[bridgeContract])
    t.start()
    while go : 
        _proofAddress = input()
        _key = input()
        _blockId = input()
        sendRequest(bridgeContract, _proofAddress,_key,_blockId)

    #0x06012c8cf97BEaD5deAe237070F9587f8E7A266d #0x22666e8ce5299a4D7c5E503F3aCE3AFbEfFD2036
    # 0 
    

if __name__ == "__main__":
    main()