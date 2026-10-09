import RetainedSurfaceIssuerFixtures

@main
struct RetainedSurfaceIssuerProof {
    static func main() throws {
        try SourceFixtures.retainedSurfaceLaws()
        print("ORIGINAL_RETAINED_SURFACE_PROOF_OK")
    }
}
