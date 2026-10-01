import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Revolve's Normal, Binormal and Tangent axes, taken from the section: through the start of its
/// boundary (a profile's outer loop, a curve's start, a face's outer loop), Tangent along the boundary
/// there, Normal along the section's plane normal, Binormal along Normal × Tangent.
public struct RevolveSectionAxis {
    public enum Direction: String, Sendable, CaseIterable {
        case normal
        case binormal
        case tangent
    }

    public init() {}

    public func axis(_ direction: Direction, section: SectionReference, in document: EvaluatedDocument) throws -> RevolveAxis {
        let tolerance = document.configuration.tolerance
        let frame = try self.frame(section, in: document, tolerance: tolerance)
        let axis: Vector3D
        switch direction {
        case .normal: axis = frame.normal
        case .tangent: axis = frame.tangent
        case .binormal: axis = try frame.normal.cross(frame.tangent).normalized(tolerance: tolerance.distance)
        }
        return RevolveAxis(origin: frame.origin, direction: axis)
    }

    /// The section's boundary start, its unit tangent there and the section plane's unit normal.
    private func frame(_ section: SectionReference, in document: EvaluatedDocument,
                       tolerance: ModelingTolerance) throws -> (origin: Point3D, tangent: Vector3D, normal: Vector3D) {
        func refuse(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
        }
        switch section {
        case let .profile(reference):
            guard let node = document.document.designGraph.nodes[reference.featureID], case let .sketch(sketch) = node.operation else {
                throw refuse("A revolve's profile section comes from a sketch.")
            }
            let profiles = try SketchProfileExtractor(tolerance: tolerance).extractProfiles(from: sketch, sourceFeatureID: reference.featureID,
                                                                         parameters: document.parameters)
            guard profiles.indices.contains(reference.profileIndex),
                  let segment = profiles[reference.profileIndex].outerLoop.boundarySegments.first else {
                throw refuse("A revolve's profile section has no boundary.")
            }
            let normal = try planeNormal(profiles[reference.profileIndex].plane, tolerance: tolerance)
            let (origin, tangent) = try start(of: segment, tolerance: tolerance)
            return (origin, tangent, normal)
        case let .curve(reference):
            guard let curve = document.curves[reference.featureID]?.first, let exact = curve.exactCurve,
                  case let .closed(lower, upper) = curve.parameterDomain else {
                throw refuse("A revolve's curve section has an exact bounded curve.")
            }
            let at = reference.isReversed ? upper : lower
            let geometry = try exact.differentialGeometry(at: at, tolerance: tolerance)
            let tangent = try (geometry.firstDerivative * (reference.isReversed ? -1 : 1)).normalized(tolerance: tolerance.distance)
            // The curve's plane: its sketch's, or the one through its points.
            let normal: Vector3D
            if let plane = curve.plane {
                normal = try planeNormal(plane, tolerance: tolerance)
            } else {
                normal = try fittedNormal(curve.points, tolerance: tolerance)
            }
            return (geometry.position, tangent, normal)
        case let .face(reference):
            let resolved = try StableSubshapeResolver().topologyReference(for: reference.face, model: document.brep,
                                                                         subshapes: document.subshapes, lineage: document.lineage,
                                                                         tolerance: tolerance)
            guard case let .face(faceID) = resolved, let face = document.brep.faces[faceID],
                  case let .plane(plane)? = document.brep.geometry.surfaces[face.surfaceID],
                  let loop = face.loops.first.flatMap({ document.brep.loops[$0] }), let use = loop.edges.first,
                  let edge = document.brep.edges[use.edgeID], let curve = document.brep.geometry.curves[edge.curveID] else {
                throw refuse("A revolve's face section is a planar face.")
            }
            let forward = use.orientation == .forward
            let trim = edge.trim
            let parameter = forward ? (trim?.startParameter ?? 0) : (trim?.endParameter ?? 1)
            let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
            let tangent = try (geometry.firstDerivative * (forward ? 1 : -1)).normalized(tolerance: tolerance.distance)
            let normal = try (face.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
            return (geometry.position, tangent, normal)
        }
    }

    private func start(of segment: ProfileBoundarySegment, tolerance: ModelingTolerance) throws -> (Point3D, Vector3D) {
        switch segment {
        case let .line(line):
            return (line.start, try (line.end - line.start).normalized(tolerance: tolerance.distance))
        case let .circularArc(arc):
            let radial = arc.start - arc.center
            let turn = try arc.normal.cross(radial).normalized(tolerance: tolerance.distance)
            return (arc.start, arc.sweepAngle >= 0 ? turn : turn * -1)
        case let .spline(spline):
            guard case let .closed(lower, _) = spline.curve.domain else {
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A profile spline is bounded.")
            }
            let geometry = try Curve3D.bSpline(spline.curve).differentialGeometry(at: lower, tolerance: tolerance)
            return (geometry.position, try geometry.firstDerivative.normalized(tolerance: tolerance.distance))
        }
    }

    private func planeNormal(_ plane: SketchPlane, tolerance: ModelingTolerance) throws -> Vector3D {
        switch plane {
        case .xy: return .unitZ
        case .yz: return Vector3D(x: 1, y: 0, z: 0)
        case .zx: return Vector3D(x: 0, y: 1, z: 0)
        case let .plane(plane): return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }

    /// The normal of the plane holding `points`, from the widest triangle among them.
    private func fittedNormal(_ points: [Point3D], tolerance: ModelingTolerance) throws -> Vector3D {
        guard let first = points.first else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A curve section has no points.")
        }
        var best = Vector3D.zero
        for i in points.indices {
            for j in points.indices where j > i {
                let candidate = (points[i] - first).cross(points[j] - first)
                if candidate.length > best.length { best = candidate }
            }
        }
        let normal = try best.normalized(tolerance: tolerance.distance * tolerance.distance)
        guard points.allSatisfy({ abs(($0 - first).dot(normal)) <= tolerance.distance }) else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                              message: "A revolve's Normal and Binormal need a curve section in one plane.")
        }
        return normal
    }
}
