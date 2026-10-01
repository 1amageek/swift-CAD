import CADCore
import CADIR
import CADModeling
import CADTopology

/// The radius of Fillet Shell's Full round across the face between two edges of a body, which the
/// faces fix (`FullRoundLayout`, or `FullRimRoundBuilder` across a tube's end) and a full
/// `FilletFeature` states.
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
        let (first, second) = (try edgeID(edges.0), try edgeID(edges.1))
        // Across a tube's end, the half torus's tube radius.
        if let tube = try FullRimRoundBuilder(tolerance: tolerance).radius(first, second, model: document.brep) {
            return tube
        }
        return try FullRoundLayout(model: document.brep, bodyID: bodyID, firstEdgeID: first,
                                   secondEdgeID: second, featureID: nil, tolerance: tolerance).radius
    }
}
