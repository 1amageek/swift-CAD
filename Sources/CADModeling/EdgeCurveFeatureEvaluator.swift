import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Publishes the exact curves of chosen edges: each edge's curve trimmed to the edge, running from
/// its start vertex to its end vertex, sampled for display and chaining.
package struct EdgeCurveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    package func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard case let .edgeCurve(edgeCurve) = feature.operation else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "The edge curve evaluator received another feature.")
        }
        try edgeCurve.validate()
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: edgeCurve.source), model: model)
        let curves = try edgeCurve.edges.map { reference -> EvaluatedCurve in
            let resolved = try subshapeResolver.topologyReference(
                for: reference, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
            )
            guard case let .edge(edgeID) = resolved, scope.references.contains(.edge(edgeID)), let edge = model.edges[edgeID],
                  let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw KernelError(phase: .evaluation, code: .missingReference, featureID: feature.id,
                                  subshapeID: reference.subshapeID, tolerance: tolerance,
                                  message: "An edge curve's edge is not an edge of its body.")
            }
            // The curve runs over the edge's trim in its own parameter order.
            let (lower, upper) = (min(trim.startParameter, trim.endParameter), max(trim.startParameter, trim.endParameter))
            let parameters = (0...32).map { lower + (upper - lower) * Double($0) / 32 }
            let kind: EvaluatedCurveKind
            switch curve {
            case .line, .analytic(.line): kind = .line
            case .circle, .analytic(.circle): kind = edge.startVertexID == edge.endVertexID ? .circle : .arc
            default: kind = .spline
            }
            return EvaluatedCurve(
                sourceFeatureID: feature.id, source: .generatedFeature, kind: kind,
                points: try parameters.map { try curve.point(at: $0, tolerance: tolerance) },
                isClosed: edge.startVertexID == edge.endVertexID,
                exactCurve: curve,
                exactParameterDomain: .closed(lower, upper),
                exactPointParameters: parameters
            )
        }
        return EvaluationResult(brep: context.brep, generatedCurves: curves)
    }
}
