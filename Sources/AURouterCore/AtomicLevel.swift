import AURouterRealtime
import Foundation

final class AtomicLevel: @unchecked Sendable {
    private let storage: OpaquePointer

    init(initialValue: Float = 0) {
        guard let storage = ARAtomicFloatCreate(initialValue) else {
            fatalError("Unable to allocate an atomic level meter")
        }
        self.storage = storage
    }

    deinit {
        ARAtomicFloatDestroy(storage)
    }

    func store(_ value: Float) {
        ARAtomicFloatStore(storage, value)
    }

    func load() -> Float {
        ARAtomicFloatLoad(storage)
    }
}
