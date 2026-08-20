import Testing
@testable import AURouterCore

@Test func hardwareChangeRefreshesWhenANewDeviceAppears() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a", "new-interface"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a"
    )
    #expect(change == .refreshCatalog)
}

@Test func hardwareChangeRefreshesWhenIdle() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "new-interface"],
        runningInputUID: nil,
        runningOutputUID: nil
    )
    #expect(change == .refreshCatalog)
}

@Test func hardwareChangeStopsWhenRunningInputDisappears() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a"
    )
    #expect(change == .stopRoute("The input device was disconnected."))
}

@Test func hardwareChangeStopsWhenRunningOutputDisappears() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a"
    )
    #expect(change == .stopRoute("The output device was disconnected."))
}

@Test func hardwareChangeStopsWhenRunningInputSampleRateChanges() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 44_100,
        runningOutputRate: 48_000,
        currentInputRate: 48_000,
        currentOutputRate: 48_000
    )
    #expect(change == .stopRoute("The input device sample rate changed."))
}

@Test func hardwareChangeStopsWhenRunningOutputSampleRateChanges() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 48_000,
        runningOutputRate: 48_000,
        currentInputRate: 48_000,
        currentOutputRate: 44_100
    )
    #expect(change == .stopRoute("The output device sample rate changed."))
}

@Test func hardwareChangeIgnoresTinySampleRateJitter() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 48_000,
        runningOutputRate: 48_000,
        currentInputRate: 48_000.1,
        currentOutputRate: 48_000
    )
    #expect(change == .refreshCatalog)
}

@Test func hardwareChangeStopsWhenSecondaryOutputDisappears() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningOutputUIDs: ["output-a", "output-b"]
    )
    #expect(change == .stopRoute("An output device was disconnected."))
}


