import AudioToolbox
import Testing
@testable import AURouterCore

@Test func parsesEffectRowsFromAUValAndIgnoresOtherComponentTypes() {
    let output = """
        AU Validation Tool
        aufx dcmp appl  -  Apple: AUDynamicsProcessor
        aufx MXVS ksWV  -  Waves: RVox (s)WaveShell-AU Compiled for 64 bits
        aumu samp appl  -  Apple: AUSampler
        """

    let effects = AudioEffectCatalog.parseAUValList(output)

    #expect(effects.count == 2)
    #expect(effects.contains { $0.name == "AUDynamicsProcessor" })
    #expect(effects.contains { $0.manufacturerName == "Waves" })
    #expect(effects.allSatisfy { $0.componentType == kAudioUnitType_Effect })
}

@Test func builtInFallbackDoesNotNeedComponentDiscovery() {
    #expect(!AudioEffectCatalog.builtInEffects.isEmpty)
    #expect(AudioEffectCatalog.builtInEffects.allSatisfy { $0.manufacturerName == "Apple" })
}
