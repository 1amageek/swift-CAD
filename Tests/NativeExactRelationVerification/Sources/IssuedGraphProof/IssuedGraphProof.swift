import IssuedGraphFixtures
#if hasFeature(Embedded)
import WASILibc
#endif
@main struct GraphProof {
    enum Failure:Error {case invalidGroup}
    static func main() throws { try run() }
    nonisolated static func run() throws {
#if hasFeature(Embedded)
        let input=getenv("CAD_PROOF_GROUP").map {String(cString:$0)} ?? "6"
#else
        let input=CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"6"
#endif
        guard let group=Int(input),group >= 6,group <= 14 else {throw Failure.invalidGroup}
        try GraphFixtures.run(group)
    }
}
