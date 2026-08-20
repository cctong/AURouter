import Foundation

public enum ProcessDeadline {
    public static func waitUntilExit(_ process: Process, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.isRunning else { return true }
        process.terminate()
        let forceBy = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < forceBy {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.interrupt()
        }
        return false
    }
}
