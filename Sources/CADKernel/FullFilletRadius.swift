import CADCore
import CADIR
import CADModeling
import CADTopology

/// The radius of Fillet Shell's Full round across the face between two edges of a body, which the
/// faces fix (`FullRoundLayout`) and a full `FilletFeature` states.
public struct FullFilletRadius {
    public init() {}

    /// Throws where the full fillet itself would refuse the edges.
    public func radius(target: FeatureID, edges: (StableSubshapeReference, StableSubshapeReference),
                       in document: EvaluatedDocument) throws -> Double {
        let tolerance = document.configuration.tolerance
        let context = EvaluationContext(parameters: document.parameters, brep: document.brep, profiles: [:],
                                        curves: document.curves, subshapes: document.subshapes,
                                        lineage: document.lineage, tolerance: tolerance)
        let bodyID = try context.bodyID(generatedBy: target)
        func edgeID(_ reference: StableSubshapeReference) throws -> EdgeID {
            guard case let .edge(edgeID) = try StableSubshapeResolver().topologyReference(
                for: reference, model: document.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance) else {
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A full fillet takes edges.")
            }
            return edgeID
        }
        return try FullRoundLayout(model: document.brep, bodyID: bodyID, firstEdgeID: try edgeID(edges.0),
                                   secondEdgeID: try edgeID(edges.1), featureID: nil, tolerance: tolerance).radius
    }
}
