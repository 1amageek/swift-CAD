import GraphFixtures
#if hasFeature(Embedded)
import WASILibc
#endif
@main struct GraphProof {
    enum Failure:Error {case invalidGroup}
    static func main() throws {
#if hasFeature(Embedded)
        let input=getenv("CAD_PROOF_GROUP").map {String(cString:$0)} ?? "0"
#else
        let input=CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"0"
#endif
        guard let group=Int(input),group >= 0,group <= 13 else {throw Failure.invalidGroup}
        try GraphFixtures.run(group)
    }
}
