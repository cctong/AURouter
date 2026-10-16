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

@Test func hardwareChangeRestartsWhenRunningInputSampleRateChanges() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 44_100,
        runningOutputRate: 48_000,
        currentInputRate: 48_000,
        currentOutputRate: 48_000
    )
    #expect(change == .restartRoute("The input device sample rate changed."))
}

@Test func hardwareChangeRestartsWhenRunningOutputSampleRateChanges() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 48_000,
        runningOutputRate: 48_000,
        currentInputRate: 48_000,
        currentOutputRate: 44_100
    )
    #expect(change == .restartRoute("The output device sample rate changed."))
}

@Test func hardwareChangeStopsWhenOutputDisappearsEvenIfInputRateChanged() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 44_100,
        runningOutputRate: 48_000,
        currentInputRate: 48_000
    )
    #expect(change == .stopRoute("The output device was disconnected."))
}

@Test func hardwareChangeRestartsWhenSecondaryOutputRateChanges() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a", "output-b"],
        runningInputUID: "input-a",
        runningOutputUID: "output-a",
        runningInputRate: 48_000,
        runningOutputRate: 48_000,
        currentInputRate: 48_000,
        currentOutputRate: 48_000,
        runningOutputUIDs: ["output-a", "output-b"],
        runningOutputRates: [
            "output-a": 48_000,
            "output-b": 48_000
        ],
        currentOutputRates: [
            "output-a": 48_000,
            "output-b": 44_100
        ]
    )
    #expect(change == .restartRoute("An output device sample rate changed."))
}

@Test func hardwareChangeRefreshesWhenSampleRatesChangeWhileIdle() {
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: nil,
        runningOutputUID: nil,
        currentInputRate: 44_100,
        currentOutputRate: 48_000,
        currentOutputRates: ["output-a": 48_000]
    )
    #expect(change == .refreshCatalog)
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

@Test func hardwareChangeResumesWhenDisconnectedDevicesReturn() {
    let pending = AudioHardwareResumeTarget(
        inputUID: "input-a",
        outputUIDs: ["output-a"],
        inputRate: 48_000,
        outputRates: ["output-a": 48_000]
    )
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: nil,
        runningOutputUID: nil,
        currentInputRate: 48_000,
        currentOutputRates: ["output-a": 48_000],
        pendingResume: pending
    )
    #expect(change == .resumeRoute)
}

@Test func hardwareChangeWaitsWhileDisconnectedDeviceIsStillMissing() {
    let pending = AudioHardwareResumeTarget(
        inputUID: "input-a",
        outputUIDs: ["output-a"],
        inputRate: 48_000,
        outputRates: ["output-a": 48_000]
    )
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["output-a"],
        runningInputUID: nil,
        runningOutputUID: nil,
        currentInputRate: nil,
        currentOutputRates: ["output-a": 48_000],
        pendingResume: pending
    )
    #expect(change == .refreshCatalog)
}

@Test func hardwareChangeWaitsWhenReturnedDeviceRateDiffers() {
    let pending = AudioHardwareResumeTarget(
        inputUID: "input-a",
        outputUIDs: ["output-a"],
        inputRate: 48_000,
        outputRates: ["output-a": 48_000]
    )
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: nil,
        runningOutputUID: nil,
        currentInputRate: 48_000,
        currentOutputRates: ["output-a": 44_100],
        pendingResume: pending
    )
    #expect(change == .refreshCatalog)
}

@Test func hardwareChangeResumesWhenReturnedRateIsWithinJitter() {
    let pending = AudioHardwareResumeTarget(
        inputUID: "input-a",
        outputUIDs: ["output-a"],
        inputRate: 48_000,
        outputRates: ["output-a": 48_000]
    )
    let change = AudioHardwareChangeEvaluator.evaluate(
        currentUIDs: ["input-a", "output-a"],
        runningInputUID: nil,
        runningOutputUID: nil,
        currentInputRate: 48_000.1,
        currentOutputRates: ["output-a": 48_000],
        pendingResume: pending
    )
    #expect(change == .resumeRoute)
}



