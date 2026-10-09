import GraphFixtures
#if hasFeature(Embedded)
import WASILibc
#endif
@main struct GraphProof {
    enum Failure: Error { case invalidGroup }
    static func main() throws {
#if hasFeature(Embedded)
        let group=getenv("CAD_PROOF_GROUP").map { UInt8(bitPattern:$0.pointee) } ?? 48
#else
        let group=CommandLine.arguments.count > 1 ? (CommandLine.arguments[1].utf8.first ?? 48):48
#endif
        guard group >= 48 && group <= 53 else { throw Failure.invalidGroup }
        try GraphFixtures.run(Int(group)-48)
    }
}
