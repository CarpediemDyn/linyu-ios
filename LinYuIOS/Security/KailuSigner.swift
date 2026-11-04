import Foundation
import CryptoKit
import CommonCrypto

/// 用来对照 Android 原版签名结果，不会自行提交订单。
enum KailuSigner {
    private static let outerKey = "&key=sign-kailu-855c74a88b8b494187c99b08b8c9a744"

    static func md5(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sign(sessionKey: String, fields: [String: String]) -> String? {
        guard !sessionKey.isEmpty else { return nil }
        let raw = fields.keys.sorted().map { $0 + (fields[$0] ?? "") }.joined()
        let inner = md5(raw + "&key=" + sessionKey)
        return md5(inner + outerKey)
    }

    static func signRateOrder(loginCode: String, telephone: String, deviceId: String,
                              xfModel: String, randomNumber: String) -> String? {
        sign(sessionKey: loginCode, fields: [
            "telephone": telephone, "deviceId": deviceId,
            "xfModel": xfModel, "randomNumber": randomNumber.lowercased()
        ])
    }

    static func signUpload(loginCode: String, telephone: String, xfData: String) -> String? {
        sign(sessionKey: loginCode, fields: [
            "loginCode": loginCode, "telephone": telephone, "xfData": xfData.lowercased()
        ])
    }

    static func signFail(loginCode: String, telephone: String, consumeDate: String) -> String? {
        sign(sessionKey: loginCode, fields: [
            "consumeDate": consumeDate, "loginCode": loginCode, "telephone": telephone
        ])
    }

    static func macType(deviceType: UInt8, a1: UInt8) -> String {
        String(format: "%02x%02x", deviceType, a1)
    }
}

/// 结算 clData 解密算法移植，**尚未经过实机结算验证**。
enum KailuAES {
    private static let key = Data("20210118klcx@002".utf8)

    static func decrypt(base64: String) -> String? {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return nil }
        let decrypted: Data
        if data.count % kCCBlockSizeAES128 == 0, let plain = aesECB(data: data) {
            decrypted = plain
        } else {
            // 与原版兼容：非 AES 块的响应可能已经是明文 Base64。
            decrypted = data
        }
        var bytes = Array(decrypted)
        if let last = bytes.last, last > 0, Int(last) <= bytes.count {
            let padding = Array(bytes.suffix(Int(last)))
            guard padding.allSatisfy({ $0 == last }) else { return nil }
            bytes.removeLast(Int(last))
        }
        if let zero = bytes.firstIndex(of: 0) { bytes = Array(bytes[..<zero]) }
        return String(data: Data(bytes), encoding: .utf8)
    }

    private static func aesECB(data: Data) -> Data? {
        let input = [UInt8](data)
        let keyBytes = [UInt8](key)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = keyBytes.withUnsafeBufferPointer { keyBuffer in
            input.withUnsafeBufferPointer { inputBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode), keyBuffer.baseAddress, keyBuffer.count,
                            nil, inputBuffer.baseAddress, inputBuffer.count,
                            outputBuffer.baseAddress, outputBuffer.count, &written)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(output.prefix(written))
    }
}
