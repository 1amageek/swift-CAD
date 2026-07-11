import CADCore
import CADIR

struct GeneratedNameValidator {
    static func validate<Names: Sequence>(
        _ generatedNames: Names,
        in brep: BRepModel
    ) throws where Names.Element == (key: PersistentName, value: TopologyReference) {
        var namedBodyIDs = Set<BodyID>()
        var namedFaceIDs = Set<FaceID>()
        var namedEdgeIDs = Set<EdgeID>()
        var namedVertexIDs = Set<VertexID>()
        for (name, reference) in generatedNames {
            try name.validate()
            switch reference {
            case let .body(bodyID):
                guard brep.bodies[bodyID] != nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Generated name references a missing body."
                    )
                }
                namedBodyIDs.insert(bodyID)
            case let .face(faceID):
                guard brep.faces[faceID] != nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Generated name references a missing face."
                    )
                }
                namedFaceIDs.insert(faceID)
            case let .edge(edgeID):
                guard brep.edges[edgeID] != nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Generated name references a missing edge."
                    )
                }
                namedEdgeIDs.insert(edgeID)
            case let .vertex(vertexID):
                guard brep.vertices[vertexID] != nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Generated name references a missing vertex."
                    )
                }
                namedVertexIDs.insert(vertexID)
            }
        }
        try validateCoverage(
            actual: namedBodyIDs,
            expected: Set(brep.bodies.keys),
            label: "body"
        )
        try validateCoverage(
            actual: namedFaceIDs,
            expected: Set(brep.faces.keys),
            label: "face"
        )
        try validateCoverage(
            actual: namedEdgeIDs,
            expected: Set(brep.edges.keys),
            label: "edge"
        )
        try validateCoverage(
            actual: namedVertexIDs,
            expected: Set(brep.vertices.keys),
            label: "vertex"
        )
    }

    private static func validateCoverage<ID: Hashable & CustomStringConvertible>(
        actual: Set<ID>,
        expected: Set<ID>,
        label: String
    ) throws {
        if let missingID = expected.subtracting(actual)
            .sorted(by: { $0.description < $1.description })
            .first {
            throw FeatureEvaluationError.invalidGraph(
                "Generated names do not cover \(label) \(missingID)."
            )
        }
        if let extraID = actual.subtracting(expected)
            .sorted(by: { $0.description < $1.description })
            .first {
            throw FeatureEvaluationError.invalidGraph(
                "Generated names contain extra \(label) \(extraID)."
            )
        }
    }
}
