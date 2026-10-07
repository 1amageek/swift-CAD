import NativeExactFixtures
@main struct Proof {
    static func main() throws {
#if hasFeature(Embedded)
        let group = "all"
#else
        let group = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
#endif
        if group == "all" || group == "cs" { try NativeExactFixtures.verifyCS() }
        if group == "all" || group == "ssi" { try NativeExactFixtures.verifySSI() }
        if group == "all" || group == "failures" { try NativeExactFixtures.verifyFailures() }
        if group == "all" || group == "provenance" { try NativeProvenanceFixtures.verify() }
        print("PASS Native exact integration \(group)")
    }
}
