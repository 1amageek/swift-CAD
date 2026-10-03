import CADCore
import CADIR
import CADModeling
import CADTopology

/// The faces Remove Fillets From Shell would take off a body — the fillets within a radius and
/// of a convexity, as its evaluator plans them — named by their subshapes in an evaluated
/// document, for a dialog to show before it runs.
public struct RemovableFillets {
    public init() {}

    /// The fillet faces of the body `target` generates; `maximumRadius` nil takes any radius.
    public func faces(target: FeatureID, maximumRadius: Double?, convexity: FilletConvexity,
                      in document: EvaluatedDocument) throws -> [SubshapeID] {
        let tolerance = document.configuration.tolerance
        let context = EvaluationContext(parameters: document.parameters, brep: document.brep, profiles: [:],
                                        curves: document.curves, subshapes: document.subshapes,
                                        lineage: document.lineage, tolerance: tolerance)
        let bodyID = try context.bodyID(generatedBy: target)
        let planned: FaceRemovalPlanner.Convexity = switch convexity {
        case .any: .any
        case .convex: .convex
        case .concave: .concave
        }
        let plan = try FaceRemovalPlanner().fillets(of: bodyID, maximumRadius: maximumRadius, convexity: planned,
                                                     model: document.brep, tolerance: tolerance)
        return document.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard case let .face(faceID) = value, plan[faceID] != nil else { return nil }
            return key
        }.sorted()
    }
}
