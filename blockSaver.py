from web3 import Web3,HTTPProvider
from hexbytes import HexBytes
from rlp import encode
from solcx import compile_source
import time

def compile_source_file(file_path):
	
    with open(file_path, 'r') as f: 
        source = f.read()
	#restituisce la tupla [abi,bin] per il primo elemento del dizionario e cioè i dati relativi  a tryOnChain	
    return compile_source(source, output_values=["abi", "bin"], solc_version="0.6.0").get('<stdin>:Bridge') 

#w3 for retrive the block of c2 (in this example is the etherium blockhain) and save they as a Lightweight blockchain on the contract
w3 = Web3(HTTPProvider('https://evocative-stylish-isle.discover.quiknode.pro/6ad754e3368653a2665e62db8659b9f179a3ae43/'))

#web3 is the Web3 reference to the chain C1 for take a reference to the bride contract
chainAddress = 'http://127.0.0.1:8545'
web3 = Web3(HTTPProvider(chainAddress))
web3.eth.defaultAccount = web3.eth.accounts[0]

#auxsiliary function that retrive the block header and code it in RLP encode
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

#infinite loop that call saveBlock contract's funcion for keep updated the internal state of the contract 
def retriveNewBlock(bridgeContract):

    blockNumber = 0
    event_filter = bridgeContract.events.NewBlockAdded.createFilter(fromBlock='latest')

    while True:
        #if there is a new block (in realtà se l'aggiunta di blocchi è più veloce di un ciclo della funzioni questa condizione non va bene)
        if(blockNumber != w3.eth.block_number):
            
            blockNumber = w3.eth.block_number
            blockHeader = RLPEncodeBlockHeader(w3,blockNumber)

            txt_hash = bridgeContract.functions.saveBlock(blockHeader).transact()
            txn_receipt = web3.eth.wait_for_transaction_receipt(txt_hash)
            print(txn_receipt)
		
            received = False
            #wait for the NewBlockAdded event that certificate that the block header is saved 
            while not received:
                        entries = event_filter.get_new_entries()
                        if (len(entries) > 0):
                            received = True
                            print(entries)
                        else:
                            time.sleep(3)
            time.sleep(5)

def main():

    contractPath = 'Contracts/Bridge.sol'
    #compile contract
    contractInterface = compile_source_file(contractPath)
    
    #ask for the address of the bridge contract
    print('enter the contract address')
    _contractAddress = input()

    #reference to the contract
    bridgeContract = web3.eth.contract(address=_contractAddress, abi=contractInterface["abi"])

    print('BlockSaver has started!\nContract: {}\nAddress\t: {}'.format( contractPath, _contractAddress))

    retriveNewBlock(bridgeContract)
    
if __name__ == "__main__":
    main()
