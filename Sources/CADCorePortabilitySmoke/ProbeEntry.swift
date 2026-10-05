import CADCore

@main
enum ProbeEntry {
    static func main() async throws {
        try CorePortabilityProof.run()
        try await CorePortabilityProof.checkCancellationWitness()
        #if !hasFeature(Embedded)
        try CoreNativeCodecProof.run()
        print("CORE_NATIVE_CODEC_OK")
        #else
        print("CORE_NATIVE_CODEC_UNAVAILABLE")
        #endif
        print("CORE_PORTABILITY_OK")
    }
}
