from web3 import Web3,HTTPProvider
from solcx import compile_source
import time

def compile_source_file(file_path):
	
    with open(file_path, 'r') as f: 
        source = f.read()
	#returns the [abi,bin] tuple for the first element of the dictionary, i.e. the data related to Bridge	
    return compile_source(source, output_values=["abi", "bin"], solc_version="0.6.0").get('<stdin>:Bridge') 

def deploy_contract(w3, contract_interface):
	#if you want to use bridge with sliding window or array put size parameter in the constructor() call function.
        tx_hash = w3.eth.contract(
                abi=contract_interface['abi'],
                bytecode=contract_interface['bin']).constructor().transact() 
        address = w3.eth.get_transaction_receipt(tx_hash)['contractAddress']
        return address


#web3 for take the reference to the contract deployed on c1
chainAddress = 'http://127.0.0.1:8545'
web3 = Web3(HTTPProvider(chainAddress))
web3.eth.defaultAccount = web3.eth.accounts[0]

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
    #waiting for the event RequestServed or BlockNotFound
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
def main():
     
    go = 1

    #compile contract and initialize it
    contract_interface = compile_source_file('Contracts/Bridge.sol')

    #deploy contract
    contractAddress = deploy_contract(web3, contract_interface)
    print('requester has started!\nAddress\t: {}'.format(contractAddress))
    bridgeContract = web3.eth.contract(address = contractAddress, abi=contract_interface["abi"])
    
    print('usage:\n 1) address for the proof\n 2) key for the proof\n 3) block id') 
    while go : 
        _proofAddress = input()
        _key = input()
        _blockId = input()
        sendRequest(bridgeContract, _proofAddress,_key,_blockId)

    #0x06012c8cf97BEaD5deAe237070F9587f8E7A266d #0x22666e8ce5299a4D7c5E503F3aCE3AFbEfFD2036
    # 0 
    
if __name__ == "__main__":
    main()
