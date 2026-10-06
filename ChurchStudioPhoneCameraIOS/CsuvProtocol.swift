import Foundation

enum CsuvPacketType: UInt8 {
    case config = 1
    case video = 2
    case status = 3
}

enum CsuvProtocol {
    static let magic = Data("CSUV".utf8)
    static let version: UInt8 = 1
    static let headerSize = 24
    static let keyframeFlag: UInt16 = 1
    static let maxPayload = 2 * 1024 * 1024

    static func header(type: CsuvPacketType, flags: UInt16, sequence: UInt32, ptsUs: UInt64, payloadSize: Int) -> Data {
        precondition(payloadSize >= 0 && payloadSize <= maxPayload)
        var out = Data(capacity: headerSize)
        out.append(magic)
        out.append(version)
        out.append(type.rawValue)
        appendBE(flags, to: &out)
        appendBE(sequence, to: &out)
        appendBE(ptsUs, to: &out)
        appendBE(UInt32(payloadSize), to: &out)
        precondition(out.count == headerSize)
        return out
    }

    static func packet(type: CsuvPacketType, flags: UInt16, sequence: UInt32, ptsUs: UInt64, payload: Data) -> Data {
        var out = header(type: type, flags: flags, sequence: sequence, ptsUs: ptsUs, payloadSize: payload.count)
        out.append(payload)
        return out
    }

    private static func appendBE(_ value: UInt16, to data: inout Data) {
        var v = value.bigEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendBE(_ value: UInt32, to data: inout Data) {
        var v = value.bigEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendBE(_ value: UInt64, to data: inout Data) {
        var v = value.bigEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
