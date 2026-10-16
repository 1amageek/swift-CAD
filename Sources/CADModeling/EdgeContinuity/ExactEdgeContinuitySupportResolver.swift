import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Resolves an edge continuity against the body: of the faces beside the edge, the one the surface
/// leaves toward the rest of it.
package struct ExactEdgeContinuitySupportResolver: Sendable {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    /// The support for `continuity` at a side whose curve leaves `point` with derivative
    /// `derivative`, the rest of the surface lying toward `toward`.
    package func support(
        for continuity: SurfaceEdgeContinuity,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> ExactEdgeContinuitySupport {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try support(for: continuity, point: point, derivative: derivative, toward: toward, context: context, featureID: featureID, using: &execution)
    }

    package func support(
        for continuity: SurfaceEdgeContinuity,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    , using execution: inout OriginalQueryExecution) throws -> ExactEdgeContinuitySupport {
        try execution.consumeWork(1)
        let tolerance = context.tolerance
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: continuity.source), model: model, using: &execution)
        let resolved = try subshapeResolver.topologyReference(
            for: continuity.edge, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance,
            maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
            remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
            maximumAlgebraicDepth: 32, using: &execution
        )
        guard case let .edge(edgeID) = resolved, scope.references.contains(.edge(edgeID)) else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: continuity.edge.subshapeID,
                              tolerance: tolerance, message: "A continuity edge did not resolve to an edge of its body.")
        }
        return try support(
            across: edgeID, in: scope, excluding: nil, order: continuity.order, tension: continuity.tension,
            angularAllowance: continuity.angularAllowance, curvatureAllowance: continuity.curvatureAllowance,
            point: point, derivative: derivative, toward: toward, context: context, featureID: featureID, using: &execution
        )
    }

    /// The support across the body edge `edgeID` of `scope`, with a face of the body beside it
    /// other than `excluded` (a Loft's face section, whose own boundary it is).
    package func support(
        across edgeID: EdgeID,
        in scope: BodyTopologyScope,
        excluding excluded: FaceID?,
        order: SurfaceEdgeContinuity.Order,
        tension: Double,
        angularAllowance: Double?,
        curvatureAllowance: Double?,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> ExactEdgeContinuitySupport {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try support(across: edgeID, in: scope, excluding: excluded, order: order, tension: tension, angularAllowance: angularAllowance, curvatureAllowance: curvatureAllowance, point: point, derivative: derivative, toward: toward, context: context, featureID: featureID, using: &execution)
    }

    package func support(
        across edgeID: EdgeID,
        in scope: BodyTopologyScope,
        excluding excluded: FaceID?,
        order: SurfaceEdgeContinuity.Order,
        tension: Double,
        angularAllowance: Double?,
        curvatureAllowance: Double?,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    , using execution: inout OriginalQueryExecution) throws -> ExactEdgeContinuitySupport {
        try execution.consumeWork(1)
        let tolerance = context.tolerance
        let model = context.brep
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID,
                              tolerance: tolerance, message: "A continuity edge has no geometry.")
        }
        let projection = try curve.parameterProjection(of: point, tolerance: tolerance, using: &execution)
        guard (try curve.point(at: projection.parameter, tolerance: tolerance, using: &execution) - point).length <= tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side does not run along its edge.")
        }
        let along = try curve.differentialGeometry(at: projection.parameter, tolerance: tolerance, using: &execution).firstDerivative
            * (trim.endParameter >= trim.startParameter ? 1 : -1)
        var best: (outward: Vector3D, outwardNormal: Vector3D, face: Face,
            coedge: Coedge, score: Double)?
        for reference in scope.references {
            try execution.consumeWork(1)
            guard case let .face(faceID) = reference, faceID != excluded else { continue }
            guard let face = model.faces[faceID] else { continue }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A face's loop is missing.") }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    guard coedge.edgeID == edgeID else { continue }
                    guard let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference("A face's surface is missing.")
                    }
                    let projected = try surface.parameterProjection(of: point, tolerance: tolerance, using: &execution)
                    let outwardNormal = try surface.normal(u: projected.u, v: projected.v, tolerance: tolerance, using: &execution)
                        * (face.orientation == .forward ? 1 : -1)
                    // The face lies to the left of its coedges about its outward normal.
                    let travel = along * (coedge.orientation == .forward ? 1 : -1)
                    let outward = try travel.cross(outwardNormal).normalized(tolerance: tolerance.distance)
                    let score = outward.dot(toward)
                    if best.map({ score > $0.score }) ?? true {
                        best = (outward, outwardNormal, face, coedge, score)
                    }
                }
            }
        }
        guard let best, let surface = model.geometry.surfaces[best.face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuity edge borders no face of its body.")
        }
        let outwardSign: Double = best.face.orientation == .forward ? 1 : -1
        let face: ExactEdgeContinuitySupport.Face
        if let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance, using: &execution) {
            face = .plane(normal: try (plane.normal * outwardSign).normalized(tolerance: tolerance.distance))
        } else {
            guard let allowance = angularAllowance else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "Continuity with a curved face needs an angular allowance.")
            }
            guard order == .tangent || curvatureAllowance != nil else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "Curvature continuity with a curved face needs a curvature allowance.")
            }
            face = .curved(surface: surface, outwardSign: outwardSign, angularAllowance: allowance,
                           curvatureAllowance: order == .curvature ? curvatureAllowance : nil)
        }
        let across = best.outwardNormal.cross(derivative)
        guard across.length > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A continuous side has no direction along its edge.")
        }
        return ExactEdgeContinuitySupport(
            face: face, sign: across.dot(best.outward) >= 0 ? 1 : -1,
            order: order, tension: tension,
            originalBoundary: .init(edgeID: edgeID, faceID: best.face.id,
                surface: surface, curve: curve, startParameter: trim.startParameter,
                endParameter: trim.endParameter, coedgeOrientation: best.coedge.orientation,
                parameterCurve: best.coedge.surfaceParameterCurve,
                faceOrientation: best.face.orientation)
        )
    }
}
