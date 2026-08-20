import Testing
@testable import AURouterCore

@Test func inputSelectionsContainEveryMonoChannelAndAvailableStereoPairs() {
    let selections = InputChannelSelection.available(channelCount: 4)

    #expect(selections.count == 6)
    #expect(selections[0] == .mono(channel: 0))
    #expect(selections[3] == .mono(channel: 3))
    #expect(selections[4] == .stereo(pair: ChannelPair(left: 0, right: 1)))
    #expect(selections[5] == .stereo(pair: ChannelPair(left: 2, right: 3)))
}

@Test func monoIsDuplicatedToBothStereoChannels() throws {
    let routes = try ChannelAdapter.routes(from: 1, to: 2)

    #expect(routes.count == 2)
    #expect(routes.contains { $0 == (0, 0, 1) })
    #expect(routes.contains { $0 == (0, 1, 1) })
}

@Test func stereoIsDownmixedWithoutSummingGain() throws {
    let routes = try ChannelAdapter.routes(from: 2, to: 1)

    #expect(routes.count == 2)
    #expect(routes.contains { $0 == (0, 0, 0.5) })
    #expect(routes.contains { $0 == (1, 0, 0.5) })
}

@Test func monoCaptureMapsOneHardwareChannelToBothRingChannels() {
    let map = ChannelAdapter.captureChannelMap(.mono(channel: 2))

    #expect(map.left == 2)
    #expect(map.right == 2)
}
