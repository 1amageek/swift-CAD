import Testing
import CADCore

@Suite("Topology lineage validation")
struct TopologyLineageValidationTests {
    @Test
    func acceptsRelationCardinalityContract() {
        let firstParent = subshape(role: "parent", ordinal: 0)
        let secondParent = subshape(role: "parent", ordinal: 1)

        #expect(TopologyLineage(
            output: subshape(role: "generated"),
            relation: .generated
        ).isStructurallyValid)
        #expect(TopologyLineage(
            output: subshape(role: "preserved"),
            parents: [firstParent],
            relation: .preserved
        ).isStructurallyValid)
        #expect(TopologyLineage(
            output: subshape(role: "split"),
            parents: [firstParent],
            relation: .split
        ).isStructurallyValid)
        #expect(TopologyLineage(
            output: subshape(role: "merged"),
            parents: [firstParent, secondParent].sorted(),
            relation: .merged
        ).isStructurallyValid)
    }

    @Test
    func rejectsRelationCardinalityMismatch() {
        let firstParent = subshape(role: "parent", ordinal: 0)
        let secondParent = subshape(role: "parent", ordinal: 1)

        #expect(TopologyLineage(
            output: subshape(role: "generated"),
            parents: [firstParent],
            relation: .generated
        ).isStructurallyValid == false)
        #expect(TopologyLineage(
            output: subshape(role: "preserved"),
            relation: .preserved
        ).isStructurallyValid == false)
        #expect(TopologyLineage(
            output: subshape(role: "split"),
            parents: [firstParent, secondParent].sorted(),
            relation: .split
        ).isStructurallyValid == false)
        #expect(TopologyLineage(
            output: subshape(role: "merged"),
            parents: [firstParent],
            relation: .merged
        ).isStructurallyValid == false)
    }

    private func subshape(
        role: String,
        ordinal: Int = 0
    ) -> SubshapeID {
        SubshapeID(featureID: FeatureID(), role: role, ordinal: ordinal)
    }
}
