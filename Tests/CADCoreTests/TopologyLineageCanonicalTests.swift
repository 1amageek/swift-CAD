import CADCore
import Testing

struct TopologyLineageCanonicalTests {
    private let feature = FeatureID(highBits: 1, lowBits: 2)

    private func id(_ ordinal: Int, role: String = "face") -> SubshapeID {
        SubshapeID(featureID: feature, role: role, ordinal: ordinal)
    }

    @Test func canonicalConstructionRetainsOriginalIdentityAndCardinality() throws {
        let output = id(4)
        for (parents, relation) in [
            ([], TopologyLineageRelation.generated),
            ([id(1)], .preserved),
            ([id(1)], .split),
            ([id(1), id(2), id(3)], .merged),
        ] {
            let retained = try #require(TopologyLineage(output: output,
                canonicalParents: parents, relation: relation))
            #expect(retained.isStructurallyValid)
            #expect(retained == TopologyLineage(output: output, parents: parents, relation: relation))
        }
    }

    @Test func invalidCanonicalInputIsRefusedWithoutRepair() {
        let output = id(4)
        #expect(TopologyLineage(output: output, canonicalParents: [id(2), id(1)], relation: .merged) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(1), id(1)], relation: .merged) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(1), output], relation: .merged) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(-1)], relation: .preserved) == nil)
        #expect(TopologyLineage(output: id(4, role: ""), canonicalParents: [], relation: .generated) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(1)], relation: .generated) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [], relation: .preserved) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(1), id(2)], relation: .split) == nil)
        #expect(TopologyLineage(output: output, canonicalParents: [id(1)], relation: .merged) == nil)
    }

    @Test func callerMutationPreservesRetainedParents() throws {
        let original = id(1)
        var parents = [original]
        let retained = try #require(TopologyLineage(output: id(4),
            canonicalParents: parents, relation: .preserved))
        parents[0] = id(2)
        #expect(retained.parents == [original])
        #expect(retained.isStructurallyValid)
    }
}
