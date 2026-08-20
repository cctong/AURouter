import Foundation
import Testing
@testable import AURouterCore

private let testDevice = AudioDevice(
    id: 42,
    uid: "test-device",
    name: "Test Interface",
    manufacturer: "Tests",
    inputChannelCount: 4,
    outputChannelCount: 6,
    nominalSampleRate: 48_000,
    bufferFrameSize: 128,
    isDefaultInput: true,
    isDefaultOutput: true
)

private let testOutputDevice = AudioDevice(
    id: 43,
    uid: "test-output-device",
    name: "Test Virtual Output",
    manufacturer: "Tests",
    inputChannelCount: 0,
    outputChannelCount: 8,
    nominalSampleRate: 44_100,
    bufferFrameSize: 256,
    isDefaultInput: false,
    isDefaultOutput: true
)

@Test func validRouteMatchesDeviceChannels() throws {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testDevice.uid,
        inputPair: ChannelPair(left: 2, right: 3),
        outputPair: ChannelPair(left: 4, right: 5)
    )

    try route.validate(inputDevice: testDevice, outputDevice: testDevice)
}

@Test func validMonoRouteSelectsOneHardwareChannel() throws {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 3),
        outputPair: ChannelPair(left: 0, right: 1)
    )

    try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    #expect(route.inputSelection.channelCount == 1)
}

@Test func monoRouteRejectsUnavailableHardwareChannel() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 4),
        outputPair: ChannelPair(left: 0, right: 1)
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func validRouteCanUseIndependentInputAndOutputDevices() throws {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputPair: ChannelPair(left: 0, right: 1),
        outputPair: ChannelPair(left: 6, right: 7)
    )

    try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
}

@Test func routeRejectsUnavailableOutputChannels() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputPair: ChannelPair(left: 0, right: 1),
        outputPair: ChannelPair(left: 7, right: 8)
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func stereoRouteRejectsLeftChannelOutsideDevice() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .stereo(pair: ChannelPair(left: 99, right: 1)),
        outputPair: ChannelPair(left: 0, right: 1)
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func outputRouteRejectsLeftChannelOutsideDevice() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 0),
        outputPair: ChannelPair(left: 99, right: 1)
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func validRouteCanUseMultipleOutputPairs() throws {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 0),
        outputPairs: [
            ChannelPair(left: 0, right: 1),
            ChannelPair(left: 6, right: 7)
        ]
    )

    try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    #expect(route.outputMatrixRoutes().count == 4)
}

@Test func routeRejectsAnEmptyOutputPairList() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 0),
        outputPairs: []
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func routeRejectsMoreThanFourOutputPairs() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        outputDeviceUID: testOutputDevice.uid,
        inputSelection: .mono(channel: 0),
        outputPairs: [
            ChannelPair(left: 0, right: 1),
            ChannelPair(left: 2, right: 3),
            ChannelPair(left: 4, right: 5),
            ChannelPair(left: 6, right: 7),
            ChannelPair(left: 0, right: 1)
        ]
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevice: testOutputDevice)
    }
}

@Test func routeDecodesLegacySingleOutputPair() throws {
    let modern = RouteConfiguration(
        inputDeviceUID: "a",
        outputDeviceUID: "b",
        inputSelection: .mono(channel: 0),
        outputPair: ChannelPair(left: 0, right: 1)
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(modern)) as? [String: Any]
    )
    let pairs = try #require(object["outputPairs"] as? [[String: Any]])
    object["outputPair"] = try #require(pairs.first)
    object.removeValue(forKey: "outputPairs")
    let decoded = try JSONDecoder().decode(
        RouteConfiguration.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(decoded.outputPairs == [ChannelPair(left: 0, right: 1)])
}

@Test func validRouteCanUseTwoOutputDevices() throws {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        inputSelection: .mono(channel: 0),
        outputs: [
            OutputDeviceRoute(
                deviceUID: testDevice.uid,
                pairs: [ChannelPair(left: 0, right: 1)]
            ),
            OutputDeviceRoute(
                deviceUID: testOutputDevice.uid,
                pairs: [ChannelPair(left: 0, right: 1), ChannelPair(left: 6, right: 7)]
            )
        ]
    )

    try route.validate(inputDevice: testDevice, outputDevices: [testDevice, testOutputDevice])
    #expect(route.outputs.count == 2)
}

@Test func routeRejectsDuplicateOutputDevices() {
    let route = RouteConfiguration(
        inputDeviceUID: testDevice.uid,
        inputSelection: .mono(channel: 0),
        outputs: [
            OutputDeviceRoute(deviceUID: testOutputDevice.uid, pairs: [ChannelPair(left: 0, right: 1)]),
            OutputDeviceRoute(deviceUID: testOutputDevice.uid, pairs: [ChannelPair(left: 2, right: 3)])
        ]
    )

    #expect(throws: AURouterError.self) {
        try route.validate(inputDevice: testDevice, outputDevices: [testOutputDevice, testOutputDevice])
    }
}


