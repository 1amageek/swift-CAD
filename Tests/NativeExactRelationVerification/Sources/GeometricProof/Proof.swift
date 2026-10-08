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
        let group = selectedGroup()
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
        case "public-cs": try L6PublicCurveSurfaceFixtures.verify()
        case "public-cs-weighted": try L6PublicCurveSurfaceFixtures.verifyWeightedContact()
        case "public-ssi-endpoints": try L6PublicSurfaceSurfaceFixtures.verifyClosedEndpoints()
        case "public-ssi-routes": try L6PublicSurfaceSurfaceFixtures.verifyRoutes()
        case "public-ssi-cover-ordinary": try L6PublicSurfaceSurfaceFixtures.verifyCoverageRoutes(only: "ordinary")
        case "public-ssi-cover-admitted": try L6PublicSurfaceSurfaceFixtures.verifyCoverageRoutes(only: "admitted")
        case "public-ssi-cover-domains": try L6PublicSurfaceSurfaceFixtures.verifyCoverageRoutes(only: "domains")
        case "public-ssi-cover-prepared": try L6PublicSurfaceSurfaceFixtures.verifyCoverageRoutes(only: "prepared")
        case "public-ssi-cover-routes": try L6PublicSurfaceSurfaceFixtures.verifyCoverageRoutes()
        case "public-ssi-fiber-domains": try L6PublicSurfaceSurfaceFixtures.verifyCoverageFibers(only: "domains")
        case "public-ssi-fiber-prepared": try L6PublicSurfaceSurfaceFixtures.verifyCoverageFibers(only: "prepared")
        case "public-ssi-cover-fibers": try L6PublicSurfaceSurfaceFixtures.verifyCoverageFibers()
        case "public-ssi-coverage": try L6PublicSurfaceSurfaceFixtures.verifyCoverage()
        case "public-ssi-failures": try L6PublicSurfaceSurfaceFixtures.verifyFailures()
        case "public-ssi-applicability": try L6PublicSurfaceSurfaceFixtures.verifyApplicability()
        case "cs-mixed-relation": try L6CurveSurfaceFixtures.verifyMixedRelation()
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
    nonisolated private static func selectedGroup() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString: value) }
        return "all"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
#endif
    }

}

private enum ProofFailure: Error { case invalidGroup }
