import NativeExactSelfFixtures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

@main
struct NativeExactSelfProof {
    static func main() {
        do { try execute(selectedGroup()) }
        catch {
#if hasFeature(Embedded)
            print("FAIL M6 self")
#else
            print("FAIL M6 self " + String(describing:error))
#endif
            fflush(nil)
            exit(1)
        }
    }
    nonisolated private static func execute(_ group: String) throws {
        try M6ExactSelfFixtures.verify(group:group == "all" ? nil:group)
    }
    nonisolated private static func selectedGroup() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString:value) }
        return "all"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1]:"all"
#endif
    }
}
