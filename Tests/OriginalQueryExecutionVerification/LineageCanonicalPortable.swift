import CADCore

/// Exercises the real Core implementation with the same three native-test oracles.
@main
struct LineageCanonicalPortable {
    private static let feature = FeatureID(highBits: 1, lowBits: 2)

    private static func id(_ ordinal: Int, role: String = "face") -> SubshapeID {
        SubshapeID(featureID: feature, role: role, ordinal: ordinal)
    }

    private static func require(_ condition: Bool) {
        if !condition { fatalError("Canonical lineage behavior violated its oracle.") }
    }

    private static func canonicalConstruction() {
        let output = id(4)
        let cases: [([SubshapeID], TopologyLineageRelation)] = [
            ([], .generated), ([id(1)], .preserved), ([id(1)], .split),
            ([id(1), id(2), id(3)], .merged),
        ]
        for (parents, relation) in cases {
            guard let retained = TopologyLineage(output: output,
                canonicalParents: parents, relation: relation) else {
                fatalError("Canonical lineage construction rejected valid original parents.")
            }
            require(retained.isStructurallyValid)
            require(retained.output == output && retained.parents == parents && retained.relation == relation)
            require(retained == TopologyLineage(output: output, parents: parents, relation: relation))
        }
        print("PASS canonical construction: four relations retain original identity and cardinality")
    }

    private static func invalidInput() {
        let output = id(4)
        require(TopologyLineage(output: output, canonicalParents: [id(2), id(1)], relation: .merged) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(1), id(1)], relation: .merged) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(1), output], relation: .merged) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(-1)], relation: .preserved) == nil)
        require(TopologyLineage(output: id(4, role: ""), canonicalParents: [], relation: .generated) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(1)], relation: .generated) == nil)
        require(TopologyLineage(output: output, canonicalParents: [], relation: .preserved) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(1), id(2)], relation: .split) == nil)
        require(TopologyLineage(output: output, canonicalParents: [id(1)], relation: .merged) == nil)
        print("PASS invalid canonical input: nine malformed inputs refused without repair")
    }

    private static func retainedAfterCallerRelease() -> TopologyLineage {
        var parents = [id(1)]
        guard let retained = TopologyLineage(output: id(4), canonicalParents: parents, relation: .preserved) else {
            fatalError("Canonical COW fixture could not retain its original parent.")
        }
        parents[0] = id(2)
        require(retained.parents == [id(1)])
        require(parents == [id(2)])
        require(retained.isStructurallyValid)
        return retained
    }

    private static func cowLifetime() {
        let retained = retainedAfterCallerRelease()
        require(retained.parents == [id(1)])
        require(retained.output == id(4) && retained.relation == .preserved)
        require(retained.isStructurallyValid)
        print("PASS COW lifetime: caller mutation and caller release preserve retained original parents")
    }

    static func main() {
        canonicalConstruction()
        invalidInput()
        cowLifetime()
        print("PASS lineage canonical portable: 3 oracle groups")
    }
}
