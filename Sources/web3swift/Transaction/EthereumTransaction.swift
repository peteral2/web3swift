//  web3swift
//
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//

import Foundation
import BigInt

public struct EthereumTransaction: CustomStringConvertible {
    // FIXME: Add Type value https://blog.mycrypto.com/new-transaction-types-on-ethereum
    public var nonce: BigUInt
    public var gasPrice: BigUInt = 0
    public var gasLimit: BigUInt = 0
    
    // MARK: - EIP-1559
    /// Value of the tip to the miner for transaction processing.
    ///
    /// Full amount of this variable goes to a miner.
    public var maxPriorityFeePerGas: BigUInt = 0

    /// Value of the fee for one gas unit
    ///
    /// This value should be greather than sum of:
    /// - `Block.nextBlockBaseFeePerGas` - baseFee which will burnt during the transaction processing
    /// - `self.maxPriorityFeePerGas` - explicit amount of a tip to the miner of the given block which will include this transaction
    ///
    /// If amount of this will be **greather** than sum of `Block.baseFeePerGas` and `maxPriorityFeePerGas`
    /// all exceed funds will be returned to the sender.
    ///
    /// If amount of this will be **lower** than sum of `Block.baseFeePerGas` and `maxPriorityFeePerGas`
    /// miner will recieve amount of the follow equation: `maxFeePerGas - Block.baseFeePerGas` if any, 
    /// where Block is a block to which transaction will be included.
    public var maxFeePerGas: BigUInt = 0
    
    // The destination address of the message, left undefined for a contract-creation transaction.
    public var to: EthereumAddress
    // (optional) The value transferred for the transaction in wei, also the endowment if it’s a contract-creation transaction.
    // TODO - split EthereumTransaction to two classes: with optional and required value property, depends on type of transaction
    public var value: BigUInt?
    public var data: Data
    public var v: BigUInt = 1
    public var r: BigUInt = 0
    public var s: BigUInt = 0
    var chainID: BigUInt? = nil

    public var inferedChainID: BigUInt? {
        get {
            if (self.r == BigUInt(0) && self.s == BigUInt(0)) {
                return self.v
            } else if (self.v == BigUInt(27) || self.v == BigUInt(28) || self.v < BigUInt(35)) {
                return nil
            } else {
                return ((self.v - BigUInt(1)) / BigUInt(2)) - BigUInt(17)
            }
        }
    }
    
    public var intrinsicChainID: BigUInt? { chainID }
    
    public mutating func UNSAFE_setChainID(_ chainID: BigUInt?) {
        self.chainID = chainID
    }

    public var hash: Data? {
        var encoded: Data
        let inferedChainID = self.inferedChainID
        if let inferedChainID = inferedChainID {
            guard let enc = self.self.encode(forSignature: false, chainID: inferedChainID) else { return nil }
            encoded = enc
        } else {
            guard let enc = self.self.encode(forSignature: false, chainID: chainID) else { return nil }
            encoded = enc
        }
        let hash = encoded.sha3(.keccak256)
        return hash
    }
    
    public var description: String {
        var toReturn = ""
        toReturn += "Transaction" + "\n"
        toReturn += "Nonce: " + String(self.nonce) + "\n"
        toReturn += "Gas price: " + String(self.gasPrice) + "\n"
        toReturn += "Gas limit: " + String(describing: self.gasLimit) + "\n"
        toReturn += "Max priority fee per gas: " + String(describing: self.maxPriorityFeePerGas)
        toReturn += "Max fee per gas: " + String(describing: maxFeePerGas)
        toReturn += "To: " + self.to.address + "\n"
        toReturn += "Value: " + String(self.value ?? "nil") + "\n"
        toReturn += "Data: " + self.data.toHexString().addHexPrefix().lowercased() + "\n"
        toReturn += "v: " + String(self.v) + "\n"
        toReturn += "r: " + String(self.r) + "\n"
        toReturn += "s: " + String(self.s) + "\n"
        toReturn += "Intrinsic chainID: " + String(describing:self.chainID) + "\n"
        toReturn += "Infered chainID: " + String(describing:self.inferedChainID) + "\n"
        toReturn += "sender: " + String(describing: self.sender?.address)  + "\n"
        toReturn += "hash: " + String(describing: self.hash?.toHexString().addHexPrefix()) + "\n"
        return toReturn
    }

    public var sender: EthereumAddress? {
        guard let publicKey = self.recoverPublicKey() else { return nil }
        return Web3.Utils.publicToAddress(publicKey)
    }

    public func recoverPublicKey() -> Data? {
        // FIXME: AND not OR condition
        guard r != 0, s != 0 else { return nil }
        // if (self.r == 0 && self.s == 0) {
        //     return nil
        // }
        var normalizedV: BigUInt = 27
        let inferedChainID = self.inferedChainID
        var d: BigUInt = 0

        if self.v >= 35 && self.v <= 38 {
            d = 35
        } else if self.v >= 31 && self.v <= 34 {
            d = 31
        } else if self.v >= 27 && self.v <= 30 {
            d = 27
        }
        if let testID = self.chainID, testID != BigUInt(0) && self.v >= (d + testID + testID) {
            normalizedV = self.v - d - testID - testID
        } else if let testID = inferedChainID, self.v >= (d + testID + testID) {
            normalizedV = self.v - d - testID - testID
        } else {
            if(d > v) { d = 0 }
            normalizedV = self.v - d
        }
        guard let vData = normalizedV.serialize().setLengthLeft(1) else {return nil}
        guard let rData = r.serialize().setLengthLeft(32) else {return nil}
        guard let sData = s.serialize().setLengthLeft(32) else {return nil}
        guard let signatureData = SECP256K1.marshalSignature(v: vData, r: rData, s: sData) else {return nil}
        var hash: Data
        if inferedChainID != nil {
            guard let h = self.hashForSignature(chainID: inferedChainID) else {return nil}
            hash = h
        } else {
            guard let h = self.hashForSignature(chainID: self.chainID) else {return nil}
            hash = h
        }
        guard let publicKey = SECP256K1.recoverPublicKey(hash: hash, signature: signatureData) else {return nil}
        return publicKey
    }

    public var txhash: String? {
        guard sender != nil else { return nil }
        guard let hash = hash else { return nil }
        let txid = hash.toHexString().addHexPrefix().lowercased()
        return txid
    }
    
    public var txid: String? { txhash }
    
    public func encode(forSignature: Bool = false, chainID: BigUInt? = nil) -> Data? {
        if forSignature {
            if chainID != nil  {
                let fields = [self.nonce, self.gasPrice, self.gasLimit, self.to.addressData, self.value!, self.data, chainID!, BigUInt(0), BigUInt(0)] as [AnyObject]
                return RLP.encode(fields)
            } else if self.chainID != nil  {
                let fields = [self.nonce, self.gasPrice, self.gasLimit, self.to.addressData, self.value!, self.data, self.chainID!, BigUInt(0), BigUInt(0)] as [AnyObject]
                return RLP.encode(fields)
            } else {
                let fields = [self.nonce, self.gasPrice, self.gasLimit, self.to.addressData, self.value!, self.data] as [AnyObject]
                return RLP.encode(fields)
            }
        } else {
            let fields = [self.nonce, self.gasPrice, self.gasLimit, self.to.addressData, self.value!, self.data, self.v, self.r, self.s] as [AnyObject]
            return RLP.encode(fields)
        }
    }

    public func encodeAsDictionary(from: EthereumAddress? = nil) -> TransactionParameters? {
        var toString: String? = nil
        switch self.to.type {
        case .normal:
            toString = self.to.address.lowercased()
        case .contractDeployment:
            break
        }
        var params = TransactionParameters(from: from?.address.lowercased(),
                                           to: toString)
        let gasEncoding = self.gasLimit.abiEncode(bits: 256)
        params.gas = gasEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        let gasPriceEncoding = self.gasPrice.abiEncode(bits: 256)
        params.gasPrice = gasPriceEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        let valueEncoding = self.value?.abiEncode(bits: 256)
        params.value = valueEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        if (self.data != Data()) {
            params.data = self.data.toHexString().addHexPrefix()
        } else {
            params.data = "0x"
        }
        return params
    }

    public func hashForSignature(chainID: BigUInt? = nil) -> Data? {
        guard let encoded = self.encode(forSignature: true, chainID: chainID) else {return nil}
        let hash = encoded.sha3(.keccak256)
        return hash
    }

    public static func fromRaw(_ raw: Data) -> EthereumTransaction? {
        guard let totalItem = RLP.decode(raw) else {return nil}
        guard let rlpItem = totalItem[0] else {return nil}
        switch rlpItem.count {
        case 9?:
            guard let nonceData = rlpItem[0]!.data else {return nil}
            let nonce = BigUInt(nonceData)
            guard let gasPriceData = rlpItem[1]!.data else {return nil}
            let gasPrice = BigUInt(gasPriceData)
            guard let gasLimitData = rlpItem[2]!.data else {return nil}
            let gasLimit = BigUInt(gasLimitData)
            var to: EthereumAddress
            switch rlpItem[3]!.content {
            case .noItem:
                to = EthereumAddress.contractDeploymentAddress()
            case .data(let addressData):
                if addressData.count == 0 {
                    to = EthereumAddress.contractDeploymentAddress()
                } else if addressData.count == 20 {
                    guard let addr = EthereumAddress(addressData) else {return nil}
                    to = addr
                } else {
                    return nil
                }
            case .list(_, _, _):
                return nil
            }
            guard let valueData = rlpItem[4]!.data else {return nil}
            let value = BigUInt(valueData)
            guard let transactionData = rlpItem[5]!.data else {return nil}
            guard let vData = rlpItem[6]!.data else {return nil}
            let v = BigUInt(vData)
            guard let rData = rlpItem[7]!.data else {return nil}
            let r = BigUInt(rData)
            guard let sData = rlpItem[8]!.data else {return nil}
            let s = BigUInt(sData)
            return EthereumTransaction.init(nonce: nonce, gasPrice: gasPrice, gasLimit: gasLimit, to: to, value: value, data: transactionData, v: v, r: r, s: s)
        case 6?:
            return nil
        default:
            return nil
        }
    }

    static func createRequest(method: JSONRPCmethod, transaction: EthereumTransaction, transactionOptions: TransactionOptions?) -> JSONRPCrequest? {
        let onBlock = transactionOptions?.callOnBlock?.stringValue
        var request = JSONRPCrequest()
        //  var tx = transaction
        request.method = method
        let from = transactionOptions?.from
        guard var txParams = transaction.encodeAsDictionary(from: from) else {return nil}
        if method == .estimateGas || transactionOptions?.gasLimit == nil {
            txParams.gas = nil
        }
        var params = [txParams] as Array<Encodable>
        if method.requiredNumOfParameters == 2 && onBlock != nil {
            params.append(onBlock as Encodable)
        }
        let pars = JSONRPCparams(params: params)
        request.params = pars
        if !request.isValid {return nil}
        return request
    }

    static func createRawTransaction(transaction: EthereumTransaction) -> JSONRPCrequest? {
        guard transaction.sender != nil else {return nil}
        guard let encodedData = transaction.encode() else {return nil}
        let hex = encodedData.toHexString().addHexPrefix().lowercased()
        var request = JSONRPCrequest()
        request.method = JSONRPCmethod.sendRawTransaction
        let params = [hex] as Array<Encodable>
        let pars = JSONRPCparams(params: params)
        request.params = pars
        if !request.isValid {return nil}
        return request
    }
}

extension EthereumTransaction {
    init(to: EthereumAddress, data: Data, options: TransactionOptions) {
        let defaults = TransactionOptions.defaultOptions
        let merged = defaults.merge(options)
        nonce = 0
        
        if let gP = merged.gasPrice {
            switch gP {
            case .manual(let value):
                self.gasPrice = value
            default:
                self.gasPrice = BigUInt("5000000000")
            }
        }

        if let gL = merged.gasLimit {
            switch gL {
            case .manual(let value):
                self.gasLimit = value
            default:
                self.gasLimit = BigUInt(UInt64(21000))
            }
        }

        if let value = merged.value {
            self.value = value
        }

        self.to = to
        self.data = data
    }

}

public extension EthereumTransaction {
    init(gasPrice: BigUInt, gasLimit: BigUInt, to: EthereumAddress, value: BigUInt, data: Data) {
        self.nonce = BigUInt(0)
        self.gasPrice = gasPrice
        self.gasLimit = gasLimit
        self.value = value
        self.data = data
        self.to = to
    }
    
    func mergedWithOptions(_ options: TransactionOptions) -> EthereumTransaction {
        var tx = self

        if let gP = options.gasPrice {
            switch gP {
            case .manual(let value):
                tx.gasPrice = value
            default:
                tx.gasPrice = BigUInt("5000000000")
            }
        }

        if let gL = options.gasLimit {
            switch gL {
            case .manual(let value):
                tx.gasLimit = value
            case .limited(let value):
                tx.gasLimit = value
            default:
                tx.gasLimit = BigUInt(UInt64(21000))
            }
        }

        if options.value != nil {
            tx.value = options.value!
        }
        if options.to != nil {
            tx.to = options.to!
        }
        return tx
    }

}
