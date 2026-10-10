import GraphFixtures
#if GRAPH_REFINEMENT_ONLY_VERIFICATION
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
#elseif hasFeature(Embedded)
import WASILibc
#endif
@main struct GraphProof {
    enum Failure:Error {case invalidGroup}
#if GRAPH_REFINEMENT_ONLY_VERIFICATION
    static func main() {
        do { try run() }
        catch { print("FAIL graph refinement"); fflush(nil); exit(1) }
    }
#else
    static func main() throws { try run() }
#endif
    nonisolated static func run() throws {
#if GRAPH_REFINEMENT_ONLY_VERIFICATION
        try GraphFixtures.parameterRefinement()
#else
#if hasFeature(Embedded)
        let input=getenv("CAD_PROOF_GROUP").map {String(cString:$0)} ?? "0"
#else
        let input=CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"0"
#endif
        guard let group=Int(input),group >= 0,group <= 15 else {throw Failure.invalidGroup}
        try GraphFixtures.run(group)
#endif
    }
}
