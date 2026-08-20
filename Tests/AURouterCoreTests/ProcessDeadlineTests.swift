import Foundation
import Testing
@testable import AURouterCore

@Test func processDeadlineKillsAHungSleep() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    let started = Date()
    #expect(ProcessDeadline.waitUntilExit(process, seconds: 0.3) == false)
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(!process.isRunning)
}
