import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A planar face read as a profile: its plane with the face's outward normal, and its loops, the
/// outer one counterclockwise about that normal and the holes clockwise, each edge as the exact
/// segment it is (a line, a circular arc, or a B-spline trimmed to the edge).
package struct FaceSectionProfileResolver: Sendable {
    private let subshapeResolver: any StableSubshapeResolving

    package init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    package func profile(for reference: FaceSectionReference, context: EvaluationContext, featureID: FeatureID) throws -> Profile {
        let tolerance = context.tolerance
        let model = context.brep
        let bodyID = try context.bodyID(generatedBy: reference.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let resolved = try subshapeResolver.topologyReference(
            for: reference.face, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        )
        guard case let .face(faceID) = resolved, scope.references.contains(.face(faceID)), let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: reference.face.subshapeID,
                              tolerance: tolerance, message: "A face section did not resolve to a face of its body.")
        }
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "A face section is a planar face.")
        }
        let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
        let normal = face.orientation == .forward ? planeNormal : planeNormal * -1
        var outer: ProfileLoop?
        var inner: [ProfileLoop] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A face section's loop is missing.") }
            var segments = try loop.coedges.map { try segment(of: $0, model: model, featureID: featureID, tolerance: tolerance) }
            // The outline runs counterclockwise about the outward normal, a hole clockwise.
            let counterclockwise = signedArea(of: try samples(of: segments), about: normal) > 0
            if counterclockwise != (loop.role == .outer) { segments = try reversed(segments, tolerance: tolerance) }
            let profileLoop = ProfileLoop(vertices: try samples(of: segments), boundarySegments: segments)
            if loop.role == .outer {
                guard outer == nil else {
                    throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                      message: "A face section has more than one outer loop.")
                }
                outer = profileLoop
            } else {
                inner.append(profileLoop)
            }
        }
        guard let outer else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A face section needs an outer loop.")
        }
        return Profile(
            sourceFeatureID: reference.featureID,
            plane: .plane(Plane3D(origin: plane.origin, normal: normal)),
            outerLoop: outer,
            innerLoops: inner
        )
    }

    /// The segment a coedge runs along, in the coedge's direction.
    private func segment(of coedge: Coedge, model: BRepModel, featureID: FeatureID, tolerance: ModelingTolerance) throws -> ProfileBoundarySegment {
        guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
              let first = model.vertices[edge.startVertexID]?.point, let last = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("A face section's edge is missing.")
        }
        let forward = coedge.orientation == .forward
        let (start, end) = forward ? (first, last) : (last, first)
        switch curve {
        case .line, .analytic(.line):
            return .line(ProfileLineSegment(start: start, end: end))
        case let .circle(circle):
            let sweep = (trim.endParameter - trim.startParameter) * (forward ? 1 : -1)
            return .circularArc(ProfileCircularArcSegment(
                center: circle.center, normal: circle.normal, radius: circle.radius, start: start, end: end, sweepAngle: sweep
            ))
        case let .analytic(.circle(center, circleNormal, radius)):
            let sweep = (trim.endParameter - trim.startParameter) * (forward ? 1 : -1)
            return .circularArc(ProfileCircularArcSegment(
                center: center, normal: circleNormal, radius: radius, start: start, end: end, sweepAngle: sweep
            ))
        case let .bSpline(spline):
            var trimmed = try spline.trimmed(
                from: min(trim.startParameter, trim.endParameter), to: max(trim.startParameter, trim.endParameter), tolerance: tolerance
            )
            if (trim.endParameter < trim.startParameter) == forward { trimmed = try trimmed.reversed(tolerance: tolerance) }
            return .spline(ProfileSplineSegment(curve: trimmed))
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): an edge that is not a line, a circle or a B-spline
            // (an ellipse, an intersection or a lifted curve) is refused. Production path:
            // FaceSectionProfileResolver for every face section. Complete only when such edges are
            // carried exactly or within a stated deviation, verified by extruding a face bounded by
            // an elliptical edge.
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              message: "A face section's edges are lines, circular arcs or B-splines.")
        }
    }

    /// Points along the segments, their ends and midpoints, for the loop's samples and its sense.
    private func samples(of segments: [ProfileBoundarySegment]) throws -> [Point3D] {
        try segments.flatMap { segment -> [Point3D] in
            switch segment {
            case let .line(line):
                return [line.start]
            case let .circularArc(arc):
                let radial = arc.start - arc.center
                let normal = arc.normal * (1 / max(arc.normal.length, 1e-300))
                let axis = normal.cross(radial)
                return (0..<8).map { index in
                    let angle = arc.sweepAngle * Double(index) / 8
                    return arc.center + radial * cos(angle) + axis * sin(angle)
                }
            case let .spline(spline):
                guard case let .closed(lower, upper) = spline.curve.domain else {
                    throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: .standard,
                                      message: "A face section's spline edge has no bounded domain.")
                }
                return try (0..<8).map { index in
                    try spline.curve.point(at: lower + (upper - lower) * Double(index) / 8, tolerance: .standard)
                }
            }
        }
    }

    private func signedArea(of points: [Point3D], about normal: Vector3D) -> Double {
        guard let origin = points.first else { return 0 }
        var twice = Vector3D.zero
        for index in points.indices {
            let a = points[index] - origin
            let b = points[(index + 1) % points.count] - origin
            twice = twice + a.cross(b)
        }
        return twice.dot(normal)
    }

    private func reversed(_ segments: [ProfileBoundarySegment], tolerance: ModelingTolerance) throws -> [ProfileBoundarySegment] {
        try segments.reversed().map { segment in
            switch segment {
            case let .line(line):
                return .line(ProfileLineSegment(start: line.end, end: line.start))
            case let .circularArc(arc):
                return .circularArc(ProfileCircularArcSegment(
                    center: arc.center, normal: arc.normal, radius: arc.radius, start: arc.end, end: arc.start, sweepAngle: -arc.sweepAngle
                ))
            case let .spline(spline):
                return .spline(ProfileSplineSegment(curve: try spline.curve.reversed(tolerance: tolerance)))
            }
        }
    }
}
