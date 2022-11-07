from web3 import Web3,HTTPProvider
from solcx import compile_source
from web3._utils.encoding import pad_bytes
import asyncio

def compile_source_file(file_path):
        
        with open(file_path, 'r') as f: 
            source = f.read()
        #restituisce la tupla [abi,bin] per il primo elemento del dizionario e cioè i dati relativi  a tryOnChain	
        return compile_source(source, output_values=["abi", "bin"], solc_version="0.6.0").get('<stdin>:Bridge') 

# C2 is the Ethereum mainnet to witch we ask to retrieve the desired variable
w3 = Web3(HTTPProvider('https://evocative-stylish-isle.discover.quiknode.pro/6ad754e3368653a2665e62db8659b9f179a3ae43/'))

# web3 is the Web3 reference to the chain C1 for take a reference to the bride contract
chainAddress = 'http://127.0.0.1:8545'
web3 = Web3(HTTPProvider(chainAddress))
web3.eth.defaultAccount = web3.eth.accounts[0]

#function that asks c2 for the proof related to the value searched by the request 
def handle_event(bridgeContract,event):

    print("hendle the request")
    requestId = event['args']['requestId']
    account = event['args']['account']
    key = event['args']['key']
    blockId = event['args']['blockId']

    
    proof = w3.eth.get_proof(account,[key], blockId)
    """
    print(proof.accountProof)
    print(len(proof.accountProof))
    for elem in proof.accountProof:
        print(len(elem))
    print(proof.storageProof[0].proof)
    print(len(proof.storageProof[0].proof))
    for elem in proof.storageProof[0].proof:
        print(len(elem))
    """
    StateProof = [
        proof.address,
        proof.accountProof,
        proof.storageHash,
        pad_bytes(b'\x00', 32, proof.storageProof[0].key),
        proof.storageProof[0].value,
        proof.storageProof[0].proof
    ]

    #call the verify function of OnChainContract
    txt_hash = bridgeContract.functions.verify(requestId, _stateProof = StateProof, _blockId = blockId).transact()
    txn_receipt = web3.eth.wait_for_transaction_receipt(txt_hash)
    print(txn_receipt)

async def log_loop(contract, event_filter, poll_interval):
    #waiting for RequestLogged events
    while True:
        for e in event_filter.get_new_entries():
            handle_event(contract, e)
        await asyncio.sleep(poll_interval)

def main():
    
    print('enter the contract address')
    contractAddress = input()

    contractPath = 'Contracts/Bridge.sol'
    #compile contract
    contractInterface = compile_source_file(contractPath)

    #reference to the contract
    bridgeContract = web3.eth.contract(address=contractAddress, abi=contractInterface["abi"])

    #event_filter for the RequestLogged event
    event_filter = bridgeContract.events.RequestLogged.createFilter(fromBlock='latest')

    print('Listener has started!\nChain\t: {}\nContract: {}\nAddress\t: {}'.format(
                                  chainAddress, contractPath, contractAddress))

    
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(asyncio.gather(log_loop(bridgeContract, event_filter, 2)))
    finally:
        loop.close()
    
if __name__ == "__main__":
    main()





	

