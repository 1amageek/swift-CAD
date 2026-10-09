import GuideIssuerFixtures

@main
struct GuideIssuerProof {
    static func main() throws {
        try SourceFixtures.guideLaws()
        print("ORIGINAL_GUIDE_ISSUANCE_PROOF_OK")
    }
}
