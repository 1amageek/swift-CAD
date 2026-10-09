import L5Fixtures
import L4ProjectionFixtures
#if hasFeature(Embedded)
import WASILibc
#endif

@main struct L5Proof {
    enum Failure: Error { case unknownGroup }
    static func main() throws {
        // ASCII group dispatch avoids requiring Unicode normalization tables in
        // this verification-only Embedded driver. The mathematical inputs agree.
        let group = selectedGroup()
        switch group {
        case 112: try ProjectionFixtures.geometryIndependentProjection(); try ProjectionFixtures.failures()
        case 103: try GraphRelationFixtures.graphRelations()
        case 102: try GraphRelationFixtures.failuresAndLifetime(); try GraphDepthFixtures.inheritedDepth()
        case 108: try legacy()
        case 48...56:
            let mode = Int(group)-48
            try GraphRelationFixtures.graphRelations(modes:mode..<(mode+1))
        case 97:
            try ProjectionFixtures.geometryIndependentProjection(); try ProjectionFixtures.failures()
            try GraphRelationFixtures.graphRelations(); try GraphRelationFixtures.failuresAndLifetime(); try GraphDepthFixtures.inheritedDepth()
            try legacy()
        default: throw Failure.unknownGroup
        }
        print("PASS: independent original parameter relation composition group=\(group)")
    }
    static func legacy() throws {
        try RelationFixtures.csRelations(); try RelationFixtures.foldedSSI()
        try RelationFixtures.domainsAndLifetime(); try FailureFixtures.verify()
    }
    static func selectedGroup() -> UInt8 {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return UInt8(bitPattern:value.pointee) }
        return 97
#else
        return CommandLine.arguments.count > 1 ? (CommandLine.arguments[1].utf8.first ?? 97) : 97
#endif
    }
}
