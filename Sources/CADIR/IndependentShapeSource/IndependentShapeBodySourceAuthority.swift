import HashTreeCollections
import CADTopology
import CADCore

/// Original imported feature/output authority, shared by full and graph-edit validation.
enum IndependentShapeBodySourceAuthority {
    static func validate(_ selector: SubshapeID, in graph: DesignGraph?,
                         charge: (Int, Int) throws -> Void) throws {
        try charge(1, 4)
        guard let graph, let feature = graph.nodes[selector.featureID],
              !feature.isSuppressed, case .importedBRep(let original) = feature.operation,
              original.model.bodies.count == 1, let body = original.model.bodies.values.first,
              selector.role == GeneratedSubshapeRole.body.rawValue, selector.ordinal == 0 else {
            throw IndependentShapeSourceError.missingReference("Actual imported Body source selector or context.")
        }
        try charge(0, feature.outputs.count)
        let expectedPort: FeaturePort = body.kind == .solid ? .body : .sheet
        guard feature.outputs.count == 1, feature.outputs[0].role == expectedPort else {
            throw IndependentShapeSourceError.invalidSource("Imported Body source selector disagrees with its declared solid/sheet output.")
        }
    }
}
