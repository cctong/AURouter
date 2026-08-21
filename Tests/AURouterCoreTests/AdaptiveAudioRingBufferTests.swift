import Testing
@testable import AURouterCore

@Test func adaptiveRingPrimesBeforePublishingAudio() throws {
    let ring = try AdaptiveAudioRingBuffer(
        capacityFrames: 32,
        targetFrames: 8,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    var leftOutput = Array(repeating: Float.nan, count: 4)
    var rightOutput = Array(repeating: Float.nan, count: 4)

    #expect(ring.write(left: [1, 1, 1, 1], right: [2, 2, 2, 2]) == 4)
    #expect(ring.read(left: &leftOutput, right: &rightOutput) == 0)
    #expect(leftOutput == [0, 0, 0, 0])
    #expect(rightOutput == [0, 0, 0, 0])

    #expect(ring.write(left: [1, 1, 1, 1, 1, 1, 1, 1], right: [2, 2, 2, 2, 2, 2, 2, 2]) == 8)
    #expect(ring.read(left: &leftOutput, right: &rightOutput) == 4)
    #expect(leftOutput.allSatisfy { $0 == 1 })
    #expect(rightOutput.allSatisfy { $0 == 2 })
}

@Test func adaptiveRingResamplesBetweenDeviceRates() throws {
    let ring = try AdaptiveAudioRingBuffer(
        capacityFrames: 128,
        targetFrames: 16,
        inputSampleRate: 44_100,
        outputSampleRate: 48_000
    )
    let ramp = (0..<64).map(Float.init)
    #expect(ring.write(left: ramp, right: ramp) == 64)

    var leftOutput = Array(repeating: Float.zero, count: 16)
    var rightOutput = Array(repeating: Float.zero, count: 16)
    #expect(ring.read(left: &leftOutput, right: &rightOutput) == 16)
    #expect(leftOutput[1] > 0.8 && leftOutput[1] < 1.0)
    #expect(leftOutput == rightOutput)
    #expect(ring.currentRatio > 0.91 && ring.currentRatio < 0.93)
}

@Test func adaptiveRingReportsOverrunWithoutOverwritingUnreadAudio() throws {
    let ring = try AdaptiveAudioRingBuffer(
        capacityFrames: 8,
        targetFrames: 2,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    let samples = Array(repeating: Float(0.5), count: 12)

    #expect(ring.write(left: samples, right: samples) == 8)
    #expect(ring.overrunCount == 1)
    #expect(ring.availableFrames == 8)
}

@Test func crossDeviceInputRatePrefersCapturedHALRate() {
    #expect(CrossDeviceInputRate.resolved(captured: 48_000, catalog: 44_100) == 48_000)
    #expect(CrossDeviceInputRate.resolved(captured: 0, catalog: 44_100) == 44_100)
    #expect(CrossDeviceInputRate.resolved(captured: -1, catalog: 48_000) == 48_000)
}

@Test func crossDeviceBridgeUsesMinimumTargetAndRoundsMilliseconds() {
    #expect(CrossDeviceBridge.targetLatencyFrames(bufferHint: 64) == 2_048)
    #expect(CrossDeviceBridge.targetLatencyFrames(bufferHint: 512) == 4_096)
    #expect(CrossDeviceBridge.latencyMilliseconds(frames: 2_048, sampleRate: 48_000) == 43)
    #expect(CrossDeviceBridge.latencyMilliseconds(frames: 2_048, sampleRate: 0) == 0)
}


@Test func adaptiveRingStaysPrimedAfterUnderrun() throws {
    let ring = try AdaptiveAudioRingBuffer(
        capacityFrames: 32,
        targetFrames: 8,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    let priming = Array(repeating: Float(1), count: 16)
    #expect(ring.write(left: priming, right: priming) == 16)
    var left = Array(repeating: Float.nan, count: 4)
    var right = Array(repeating: Float.nan, count: 4)
    #expect(ring.read(left: &left, right: &right) == 4)

    while ring.read(left: &left, right: &right) > 0 {}
    #expect(ring.underrunCount >= 1)
    #expect(ring.write(left: [3, 3, 3, 3, 3, 3], right: [4, 4, 4, 4, 4, 4]) == 6)
    #expect(ring.read(left: &left, right: &right) == 4)
    #expect(left.allSatisfy { !$0.isNaN && $0 != 0 })
    #expect(right.allSatisfy { !$0.isNaN && $0 != 0 })
}

@Test func adaptiveRingWriteWrapsContiguousSpans() throws {
    let wrapping = try AdaptiveAudioRingBuffer(
        capacityFrames: 16,
        targetFrames: 4,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    let control = try AdaptiveAudioRingBuffer(
        capacityFrames: 64,
        targetFrames: 4,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    let first = (0..<8).map(Float.init)
    let second = (8..<20).map(Float.init)
    #expect(wrapping.write(left: first, right: first) == 8)
    #expect(control.write(left: first, right: first) == 8)

    var wrapLeft = Array(repeating: Float.nan, count: 4)
    var wrapRight = Array(repeating: Float.nan, count: 4)
    var controlLeft = Array(repeating: Float.nan, count: 4)
    var controlRight = Array(repeating: Float.nan, count: 4)
    #expect(wrapping.read(left: &wrapLeft, right: &wrapRight) == 4)
    #expect(control.read(left: &controlLeft, right: &controlRight) == 4)
    #expect(wrapLeft == controlLeft)
    #expect(wrapRight == controlRight)

    #expect(wrapping.write(left: second, right: second) == 12)
    #expect(control.write(left: second, right: second) == 12)
    wrapLeft = Array(repeating: Float.nan, count: 8)
    wrapRight = Array(repeating: Float.nan, count: 8)
    controlLeft = Array(repeating: Float.nan, count: 8)
    controlRight = Array(repeating: Float.nan, count: 8)
    #expect(wrapping.read(left: &wrapLeft, right: &wrapRight) == 8)
    #expect(control.read(left: &controlLeft, right: &controlRight) == 8)
    #expect(wrapLeft == controlLeft)
    #expect(wrapRight == controlRight)
}

@Test func adaptiveRingInterpolatesRampAcrossReads() throws {
    let ring = try AdaptiveAudioRingBuffer(
        capacityFrames: 128,
        targetFrames: 16,
        inputSampleRate: 48_000,
        outputSampleRate: 48_000
    )
    let ramp = (0..<64).map(Float.init)
    #expect(ring.write(left: ramp, right: ramp) == 64)

    var first = Array(repeating: Float.zero, count: 8)
    var firstRight = Array(repeating: Float.zero, count: 8)
    #expect(ring.read(left: &first, right: &firstRight) == 8)
    #expect(first == firstRight)
    #expect(abs(first[0] - 0) < 0.0001)
    #expect(abs(first[1] - 1.003) < 0.0001)

    var second = Array(repeating: Float.zero, count: 8)
    var secondRight = Array(repeating: Float.zero, count: 8)
    #expect(ring.read(left: &second, right: &secondRight) == 8)
    #expect(second == secondRight)
    #expect(abs(second[0] - 8.024) < 0.0001)
    #expect(second[0] > first[7])
}

