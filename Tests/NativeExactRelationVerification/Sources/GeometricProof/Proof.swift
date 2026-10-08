import NativeExactFixtures
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

@main struct GeometricProof {
    static func main() throws {
#if hasFeature(Embedded)
        let group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "all"
#else
        let group = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
#endif
        do { try execute(group) }
        catch {
            // Flush completed proof markers before propagating the actual failure.
            fflush(nil)
            throw error
        }
    }

    nonisolated static func execute(_ group: String) throws {
        try L5SquareReductionFixtures.verify()
        switch group {
        case "all": try L6CurveSurfaceFixtures.verify(); try L6SurfaceSurfaceFixtures.verify()
        case "cs": try L6CurveSurfaceFixtures.verify()
        case "ssi": try L6SurfaceSurfaceFixtures.verify()
        case "ssi-points": try L6SurfaceSurfaceFixtures.verifyPoints()
        case "ssi-images": try L6SurfaceSurfaceFixtures.verifyImagesAndFibers()
        case "ssi-domain": try L6SurfaceSurfaceFixtures.verifySelectedDomains()
        case "ssi-failures": try L6SurfaceSurfaceFixtures.verifyFailures()
        default: throw ProofFailure.invalidGroup
        }
        print("PASS full production Native L6 geometric publication \(group)")
    }
}

private enum ProofFailure: Error { case invalidGroup }
