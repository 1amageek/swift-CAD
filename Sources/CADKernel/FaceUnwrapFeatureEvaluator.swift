import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Unwrap Face: one face laid flat as a sheet of its own in the world's XY plane, centred on the
/// origin, its front facing +Z, the body left as it is. The flat sheet keeps the face's parameters
/// and trimming curves: its surface is a planar B-spline fitted to the face's development
/// (`FaceDevelopment`) over the face's parameter extent, and each edge a B-spline fitted to that
/// surface along the edge's trimming curve, both within a quarter of the distance tolerance.
/// A seam the face closes around is cut open; a face closed around its surface's period with no
/// seam to cut along is refused.
struct FaceUnwrapFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try unwrap(feature: feature, context: context)
        }
    }

    private func unwrap(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceUnwrap(unwrap) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Unwrap Face evaluator requires a faceUnwrap feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try unwrap.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let model = context.brep
        let bodyID = try context.bodyID(generatedBy: unwrap.target.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let resolved = try subshapeResolver.topologyReference(
            for: unwrap.face, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        )
        guard case let .face(faceID) = resolved, scope.references.contains(.face(faceID)), let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: feature.id, subshapeID: unwrap.face.subshapeID,
                              tolerance: tolerance, message: "The face to unwrap did not resolve to a face of its body.")
        }
        let source = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "unwrap:face", from: model, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
        ).patch
        let box = try FaceParameterExtentResolver().bounds(for: faceID, in: model, tolerance: tolerance)
        let development = try FaceDevelopment(surface: surface, box: box, tolerance: tolerance)
        // The front faces +Z: a face facing against its surface's normal is laid out mirrored.
        let mirror = face.orientation == .reversed ? -1.0 : 1.0
        func flat(_ parameter: SurfaceParameter) throws -> (x: Double, y: Double) {
            let point = try development.point(u: parameter.u, v: parameter.v)
            return (point.x * mirror, point.y)
        }
        // Centred on the origin: the middle of the box around the face's boundary laid flat.
        var lower = (x: Double.infinity, y: Double.infinity)
        var upper = (x: -Double.infinity, y: -Double.infinity)
        for loop in source.loops {
            for edge in loop.edges {
                let pcurve = edge.surfaceParameterCurve
                for index in 0...32 {
                    let point = try flat(try pcurve.parameter(atNormalizedFraction: Double(index) / 32, tolerance: tolerance))
                    lower = (min(lower.x, point.x), min(lower.y, point.y))
                    upper = (max(upper.x, point.x), max(upper.y, point.y))
                }
            }
        }
        let center = (x: (lower.x + upper.x) / 2, y: (lower.y + upper.y) / 2)
        let deviation = tolerance.distance / 4
        let fitted = try MappedBSplineSurfaceFitter(deviation: deviation).fit(u: box.u, v: box.v, tolerance: tolerance) { u, v in
            let point = try flat(SurfaceParameter(u: u, v: v))
            return Point3D(x: point.x - center.x, y: point.y - center.y, z: 0)
        }.surface
        let flatSurface = Surface3D.bSpline(fitted)
        let curveFitter = try SpatialCurveFitter(deviation: deviation)
        var loops: [BRepSewingLoop] = []
        for (loopIndex, loop) in source.loops.enumerated() {
            var edges: [BRepSewingEdge] = []
            for (edgeIndex, edge) in loop.edges.enumerated() {
                let pcurve = edge.surfaceParameterCurve
                let onFlat = { (fraction: Double) throws -> Point3D in
                    let parameter = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                    return try flatSurface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                }
                let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance, point: onFlat).curve
                edges.append(BRepSewingEdge(
                    stableID: "unwrap:loop:\(loopIndex):edge:\(edgeIndex)",
                    curve: .bSpline(curve), startParameter: 0, endParameter: 1,
                    startPoint: try onFlat(0), endPoint: try onFlat(1),
                    surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                    startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                    endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
                ))
            }
            guard let first = edges.first, let last = edges.last, (first.startPoint - last.endPoint).length <= tolerance.distance else {
                throw failure(.unsupportedCapability, feature.id, tolerance,
                              "The face closes around its surface's period with no seam to cut it open along.")
            }
            loops.append(BRepSewingLoop(stableID: "unwrap:loop:\(loopIndex)", role: loop.role, edges: edges))
        }
        let patch = BRepSewingFacePatch(
            stableID: "unwrap:face", surface: flatSurface, orientation: face.orientation, loops: loops,
            parentSubshapeIDs: source.parentSubshapeIDs
        )
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: [BRepSewingShell(stableID: "unwrap:shell", patches: [patch])]),
            tolerance: tolerance
        )
        var result = model
        try BRepModelCombiner().merge(sewn.brep, into: &result)
        return EvaluationResult(brep: result, subshapes: sewn.subshapes, lineage: sewn.lineage)
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
