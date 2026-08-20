import Testing
@testable import AURouterCore

@Test func effectChainAllowsEightUnits() throws {
    let effect = AudioEffectCatalog.builtInEffects[0]
    let effects = Array(repeating: RoutedEffect(descriptor: effect), count: EffectChain.maximumLength)
    try EffectChain.validate(effects)
}

@Test func effectChainRejectsNineUnits() {
    let effect = AudioEffectCatalog.builtInEffects[0]
    let effects = Array(repeating: RoutedEffect(descriptor: effect), count: EffectChain.maximumLength + 1)
    #expect(throws: AURouterError.self) {
        try EffectChain.validate(effects)
    }
}
