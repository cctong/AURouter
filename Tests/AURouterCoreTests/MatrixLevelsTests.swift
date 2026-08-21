import Testing
@testable import AURouterCore

@Test func matrixLevelsSelectAnInputPair() throws {
    let levels = try MatrixLevels.make(
        inputChannels: 4,
        outputChannels: 2,
        routes: [(input: 2, output: 0, gain: 1), (input: 3, output: 1, gain: 1)]
    )

    #expect(levels.count == 15)
    #expect(levels[2 * 3 + 0] == 1)
    #expect(levels[3 * 3 + 1] == 1)
    #expect(levels[0 * 3 + 0] == 0)
    #expect(levels[4 * 3 + 2] == 1)
}

@Test func matrixLevelsRouteStereoToHardwareChannelsSevenAndEight() throws {
    let levels = try MatrixLevels.make(
        inputChannels: 2,
        outputChannels: 8,
        routes: [(input: 0, output: 6, gain: 1), (input: 1, output: 7, gain: 1)]
    )
    let columns = 9
    #expect(levels[0 * columns + 6] == 1)
    #expect(levels[1 * columns + 7] == 1)
    #expect(levels[0 * columns + 0] == 0)
}


@Test func matrixLevelsRejectOutOfRangeRoutes() {
    #expect(throws: AURouterError.self) {
        try MatrixLevels.make(
            inputChannels: 2,
            outputChannels: 2,
            routes: [(input: 2, output: 0, gain: 1)]
        )
    }
}
