import RetainedCurveIssuerFixtures

@main
struct RetainedCurveIssuerProof {
    static func main() throws {
        try SourceFixtures.retainedCurveLaws()
        print("ORIGINAL_RETAINED_CURVE_PROOF_OK")
    }
}
