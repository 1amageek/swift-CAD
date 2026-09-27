import CADCore
import CADGeometry
import Foundation

/// Measures a face on a sphere bounded by great-circle arcs, meridians and circles of latitude.
///
/// The area follows from Gauss–Bonnet: a region of a sphere of radius R with h holes, bounded by
/// loops that keep it on their left about the outward normal, has area
/// R² (2π (1 − h) − Σ θ − Σ ∫ k_g ds), with θ the turning angle at each vertex and k_g the
/// geodesic curvature, zero on a great circle and tan v / R on the circle of latitude v. The first
/// moment follows from the vector area: ∫∫ (x − C) dA = (R / 2) ∮ (x − C) × dx, whose integrand is
/// constant along a great circle and trigonometric along a circle of latitude. Both are closed
/// forms in the arcs' end parameters.
///
/// Which side of its boundary the face covers is read from the parameter domain, where the face
/// is the region its pcurves enclose: the sign of that region's area says whether the loops run
/// counterclockwise about the outward normal. A loop that winds around the sphere's axis encloses
/// no region of the parameter domain on its own, so such a face is refused.
struct SphericalFaceAreaIntegrator {
    /// One boundary arc's exact contributions and its end tangents.
    private struct Arc {
        var startTangent: Vector3D
        var endTangent: Vector3D
        var endRadial: Vector3D
        /// ∮ (x − C) × dx along the arc, over R².
        var vectorArea: Vector3D
        /// ∫ k_g ds along the arc, with the region on the left.
        var geodesicTurning: Double
    }

    private static let orientationSamplesPerArc = 32

    func measurement(
        of face: Face,
        center: Point3D,
        radius: Double,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceAreaMeasurement {
        let support = Surface3D.analytic(.sphere(center: center, radius: radius))
        let frame = try Frame(support: support, center: center, radius: radius, tolerance: tolerance)
        var totalTurning = 0.0
        var vectorArea = Vector3D.zero
        var parameterArea = 0.0
        for loopID in face.loops {
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference("Face area references a missing or empty loop.")
            }
            let curves = try loop.coedges.map { coedge -> SurfaceParameterCurve in
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                return curve
            }
            let arcs = try curves.map { try arc(for: $0, frame: frame, tolerance: tolerance) }
            for (index, arc) in arcs.enumerated() {
                let next = arcs[(index + 1) % arcs.count]
                let normal = arc.endRadial
                totalTurning += atan2(normal.dot(arc.endTangent.cross(next.startTangent)),
                                      arc.endTangent.dot(next.startTangent))
                totalTurning += arc.geodesicTurning
                vectorArea = vectorArea + arc.vectorArea
            }
            parameterArea += try signedParameterArea(of: curves, tolerance: tolerance)
        }
        guard abs(parameterArea) > tolerance.angle else {
            throw KernelError(
                phase: .topology, code: .topologyFailure, residual: parameterArea, tolerance: tolerance,
                message: "Face area found a spherical face bounding no area."
            )
        }
        let counterclockwise: Double = parameterArea > 0 ? 1 : -1
        let holes = Double(face.loops.count - 1)
        let area = radius * radius * (2 * .pi * (1 - holes) - counterclockwise * totalTurning)
        guard area.isFinite, area > tolerance.distance * tolerance.distance,
              area <= 4 * .pi * radius * radius * (1 + tolerance.relative) else {
            throw KernelError(
                phase: .topology, code: .topologyFailure, residual: area, tolerance: tolerance,
                message: "Face area found a spherical face whose boundary does not enclose a region."
            )
        }
        let moment = vectorArea * (counterclockwise * radius * radius * radius / 2)
        return FaceAreaMeasurement(area: area, centroid: center + moment * (1 / area))
    }

    /// The sphere's frame: e(u) = e₀ cos u + e₁ sin u is the horizontal radial direction at
    /// longitude u and z the polar axis, all read from the support's own parameterization.
    private struct Frame {
        var e0: Vector3D
        var e1: Vector3D
        var z: Vector3D
        var center: Point3D
        var radius: Double

        init(support: Surface3D, center: Point3D, radius: Double, tolerance: ModelingTolerance) throws {
            e0 = (try support.point(u: 0, v: 0, tolerance: tolerance) - center) * (1 / radius)
            e1 = (try support.point(u: .pi / 2, v: 0, tolerance: tolerance) - center) * (1 / radius)
            z = (try support.point(u: 0, v: .pi / 2, tolerance: tolerance) - center) * (1 / radius)
            self.center = center
            self.radius = radius
        }

        func horizontal(_ u: Double) -> Vector3D { e0 * cos(u) + e1 * sin(u) }
        func east(_ u: Double) -> Vector3D { e0 * -sin(u) + e1 * cos(u) }
    }

    private func arc(for curve: SurfaceParameterCurve, frame: Frame, tolerance: ModelingTolerance) throws -> Arc {
        switch curve {
        case let .sphericalGreatCircle(cosine, sine, start, end):
            let direction: Double = end >= start ? 1 : -1
            return Arc(
                startTangent: (cosine * -sin(start) + sine * cos(start)) * direction,
                endTangent: (cosine * -sin(end) + sine * cos(end)) * direction,
                endRadial: cosine * cos(end) + sine * sin(end),
                vectorArea: cosine.cross(sine) * (end - start),
                geodesicTurning: 0
            )
        case let .constantU(u, vStart, vEnd):
            // A meridian: a great circle through both poles.
            let e = frame.horizontal(u)
            let direction: Double = vEnd >= vStart ? 1 : -1
            return Arc(
                startTangent: (e * -sin(vStart) + frame.z * cos(vStart)) * direction,
                endTangent: (e * -sin(vEnd) + frame.z * cos(vEnd)) * direction,
                endRadial: e * cos(vEnd) + frame.z * sin(vEnd),
                vectorArea: e.cross(frame.z) * (vEnd - vStart),
                geodesicTurning: 0
            )
        case let .constantV(v, uStart, uEnd):
            // A circle of latitude, curving toward the pole on its northern side.
            guard cos(v) > tolerance.angle else {
                throw unsupported("Face area found a circle of latitude collapsed to a pole.", tolerance)
            }
            let direction: Double = uEnd >= uStart ? 1 : -1
            let swept = frame.e0 * (sin(uEnd) - sin(uStart)) - frame.e1 * (cos(uEnd) - cos(uStart))
            return Arc(
                startTangent: frame.east(uStart) * direction,
                endTangent: frame.east(uEnd) * direction,
                endRadial: frame.horizontal(uEnd) * cos(v) + frame.z * sin(v),
                vectorArea: (frame.e0.cross(frame.e1) * (cos(v) * (uEnd - uStart)) - swept * sin(v)) * cos(v),
                geodesicTurning: sin(v) * (uEnd - uStart)
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard vShift == 0 else {
                throw unsupported("Face area found a spherical pcurve shifted in latitude.", tolerance)
            }
            switch base {
            case let .constantU(u, vStart, vEnd):
                return try arc(for: .constantU(u: u + uShift, vStart: vStart, vEnd: vEnd), frame: frame, tolerance: tolerance)
            case let .constantV(v, uStart, uEnd):
                return try arc(for: .constantV(v: v, uStart: uStart + uShift, uEnd: uEnd + uShift), frame: frame, tolerance: tolerance)
            case .sphericalGreatCircle where remainder(uShift, 2 * .pi) == 0:
                return try arc(for: base, frame: frame, tolerance: tolerance)
            default:
                throw unsupported("Face area found a shifted spherical pcurve it cannot measure.", tolerance)
            }
        default:
            throw unsupported(
                "Face area on a sphere is measured for great-circle arcs, meridians and circles of latitude only.",
                tolerance
            )
        }
    }

    /// The area the loop encloses in the parameter domain, −∮ v du over sampled pcurves, with
    /// longitudes unwrapped along the loop and a collapsed pole side closed straight. Only its sign
    /// is used. A loop whose longitude does not return is refused: it encloses no region there.
    private func signedParameterArea(of curves: [SurfaceParameterCurve], tolerance: ModelingTolerance) throws -> Double {
        var points: [SurfaceParameter] = []
        for curve in curves {
            for index in 0...Self.orientationSamplesPerArc {
                let fraction = Double(index) / Double(Self.orientationSamplesPerArc)
                var point = try curve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                if let previous = points.last {
                    point.u += 2 * .pi * ((previous.u - point.u) / (2 * .pi)).rounded()
                }
                points.append(point)
            }
        }
        guard let first = points.first, let last = points.last,
              abs(last.u - first.u) < .pi else {
            throw unsupported("Face area found a spherical loop that winds around the polar axis.", tolerance)
        }
        var area = 0.0
        for (start, end) in zip(points, points.dropFirst() + [first]) {
            area -= (end.u - start.u) * (start.v + end.v) / 2
        }
        return area
    }

    private func unsupported(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}
