import Testing
@testable import AURouterCore

@Test func systemDeviceCatalogReturnsUniqueDeviceUIDs() throws {
    let devices = try AudioDeviceCatalog.devices()
    let uniqueUIDs = Set(devices.map(\.uid))

    #expect(uniqueUIDs.count == devices.count)
}
