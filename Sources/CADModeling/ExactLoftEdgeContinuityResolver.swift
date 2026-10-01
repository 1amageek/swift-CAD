import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The planar face a Loft is tangent or curvature continuous with at an end section along a body
/// edge, and the directions leaving it across the section.
package struct ExactLoftEdgeContinuityPlane: Sendable {
    /// The face's unit outward normal.
    package let normal: Vector3D
    /// The sign that turns `normal × C′` away from the face for the section's curve `C`.
    package let sign: Double
    package let order: LoftEdgeContinuity.Order
    package let tension: Double

    /// The unit directions leaving the face across `span` at its control points' Greville
    /// abscissae: in the face's plane and across the span, so every combination of them keeps the
    /// Loft's cross-boundary derivative in the plane.
    package func leavingDirections(along span: BSplineCurve3D, tolerance: ModelingTolerance) throws -> [Vector3D] {
        let degree = span.degree
        return try span.controlPoints.indices.map { index in
            let greville = span.knots[(index + 1)...(index + degree)].reduce(0, +) / Double(degree)
            let derivative = try span.differentialGeometry(at: greville, tolerance: tolerance).firstDerivative
            return try (normal.cross(derivative) * sign).normalized(tolerance: tolerance.distance)
        }
    }
}

/// Resolves a Loft section's edge continuity against the body: of the faces beside the edge, the
/// one the Loft leaves toward its other sections, which must be planar.
package struct ExactLoftEdgeContinuityResolver: Sendable {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    /// The plane for `continuity` at a section whose curve leaves `point` with derivative
    /// `derivative`, the other sections lying toward `toward`.
    package func plane(
        for continuity: LoftEdgeContinuity,
        point: Point3D,
        derivative: Vector3D,
        toward: Vector3D,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> ExactLoftEdgeContinuityPlane {
        let tolerance = context.tolerance
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: continuity.source), model: model)
        let resolved = try subshapeResolver.topologyReference(
            for: continuity.edge, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        )
        guard case let .edge(edgeID) = resolved, scope.references.contains(.edge(edgeID)), let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: continuity.edge.subshapeID,
                              tolerance: tolerance, message: "A Loft continuity edge did not resolve to an edge of its body.")
        }
        let projection = try curve.parameterProjection(of: point, tolerance: tolerance)
        guard (try curve.point(at: projection.parameter, tolerance: tolerance) - point).length <= tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A Loft continuity section does not run along its edge.")
        }
        let along = try curve.differentialGeometry(at: projection.parameter, tolerance: tolerance).firstDerivative
            * (trim.endParameter >= trim.startParameter ? 1 : -1)
        var best: (outward: Vector3D, normal: Vector3D?, score: Double)?
        for case let .face(faceID) in scope.references {
            guard let face = model.faces[faceID] else { continue }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A face's loop is missing.") }
                for coedge in loop.coedges where coedge.edgeID == edgeID {
                    guard let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference("A face's surface is missing.")
                    }
                    let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance)
                    // A non-planar face's normal turns along the edge, so it has no plane here.
                    let surfaceNormal: Vector3D
                    if let plane {
                        surfaceNormal = plane.normal
                    } else {
                        let projected = try surface.parameterProjection(of: point, tolerance: tolerance)
                        surfaceNormal = try surface.normal(u: projected.u, v: projected.v, tolerance: tolerance)
                    }
                    let outwardNormal = surfaceNormal * (face.orientation == .forward ? 1 : -1)
                    // The face lies to the left of its coedges about its outward normal.
                    let travel = along * (coedge.orientation == .forward ? 1 : -1)
                    let outward = try travel.cross(outwardNormal).normalized(tolerance: tolerance.distance)
                    let score = outward.dot(toward)
                    if best.map({ score > $0.score }) ?? true {
                        best = (outward, plane.map { $0.normal * (face.orientation == .forward ? 1 : -1) }, score)
                    }
                }
            }
        }
        guard let best else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A Loft continuity edge borders no face of its body.")
        }
        guard let normal = best.normal else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): beside a curved face the cross-boundary rows that
            // keep the Loft in the face's tangent planes are not a B-spline, so continuity with a
            // non-planar face is refused. Production path: ExactLoftBodyBuilder for every Loft
            // section with continuity. Complete only when the rows are fitted within a stated
            // deviation, verified by a G1 loft from a cylinder's rim.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "Loft continuity is with a planar face.")
        }
        let unitNormal = try normal.normalized(tolerance: tolerance.distance)
        let across = unitNormal.cross(derivative)
        guard across.length > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A Loft continuity section has no direction along its edge.")
        }
        return ExactLoftEdgeContinuityPlane(
            normal: unitNormal, sign: across.dot(best.outward) >= 0 ? 1 : -1,
            order: continuity.order, tension: continuity.tension
        )
    }
}
