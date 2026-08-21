import AudioToolbox
import Foundation

public enum AURouterError: LocalizedError, Sendable {
    case coreAudio(operation: String, status: OSStatus)
    case invalidRoute(String)
    case unavailable(String)
    case audioUnit(String)

    public var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status):
            return "\(operation) failed: \(Self.describe(status))"
        case let .invalidRoute(message),
             let .unavailable(message),
             let .audioUnit(message):
            return message
        }
    }

    public static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AURouterError.coreAudio(operation: operation, status: status)
        }
    }

    public static func describe(_ status: OSStatus) -> String {
        if status == kAudioUnitErr_FormatNotSupported {
            return "format not supported (\(status))"
        }
        let value = UInt32(bitPattern: status)
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
           let code = String(bytes: bytes, encoding: .ascii) {
            return "'\(code)' (\(status))"
        }
        return "OSStatus \(status)"
    }
}
