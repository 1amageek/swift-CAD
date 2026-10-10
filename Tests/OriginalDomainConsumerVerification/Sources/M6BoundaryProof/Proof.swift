import NativeExactBoundaryFixtures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

@main
enum BoundaryProof {
    static func main() async { await execute() }
    nonisolated static func execute() async {
        do {
            let group = try selectedGroup()
            try M6ExactBoundaryFixtures.verify(group:group)
            if group == "failures" {
                try M6TopologyPortableFixtures.verifyCanonicalAudit()
                try M6TopologyPortableFixtures.verifyDiagnosticAuthority()
                try M6TopologyPortableFixtures.verifyDefaultArcLengthOptions()
                try await M6TopologyPortableFixtures.verifyCurrentTaskCancellation()
            }
        } catch {
#if hasFeature(Embedded)
            print("FAIL M6 boundary")
#else
            print("FAIL M6 boundary " + String(describing:error))
#endif
            fflush(nil);exit(1)
        }
    }
    nonisolated private static func selectedGroup() throws -> String {
#if hasFeature(Embedded)
        guard let value = getenv("CAD_PROOF_GROUP") else { throw SelectionFailure.missingGroup }
        return String(cString:value)
#else
        guard CommandLine.arguments.count == 2 else { throw SelectionFailure.missingGroup }
        return CommandLine.arguments[1]
#endif
    }
}

private enum SelectionFailure: Error { case missingGroup }
