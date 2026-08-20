import Testing
@testable import AURouterCore

@Test func stereoPairsUseAdjacentOneBasedDisplayChannels() {
    let pairs = ChannelPair.available(channelCount: 6)

    #expect(pairs == [
        ChannelPair(left: 0, right: 1),
        ChannelPair(left: 2, right: 3),
        ChannelPair(left: 4, right: 5)
    ])
    #expect(pairs[1].displayName == "Channels 3–4")
}

@Test func stereoPairsIgnoreAnUnpairedFinalChannel() {
    #expect(ChannelPair.available(channelCount: 3) == [ChannelPair(left: 0, right: 1)])
    #expect(ChannelPair.available(channelCount: 1).isEmpty)
}
