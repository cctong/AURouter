import AURouterCore
import Foundation

enum AudioEffectProcessScanner {
    private static let timeoutSeconds: TimeInterval = 15

    nonisolated static func scan() -> [AudioEffectDescriptor] {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/auval")
        process.arguments = ["-a"]
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            guard ProcessDeadline.waitUntilExit(process, seconds: timeoutSeconds) else {
                return []
            }
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return AudioEffectCatalog.parseAUValList(output)
        } catch {
            return []
        }
    }
}
