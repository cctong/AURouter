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

@Test func matrixLevelsRejectOutOfRangeRoutes() {
    #expect(throws: AURouterError.self) {
        try MatrixLevels.make(
            inputChannels: 2,
            outputChannels: 2,
            routes: [(input: 2, output: 0, gain: 1)]
        )
    }
}
