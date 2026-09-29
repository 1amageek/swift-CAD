import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A point's place relative to a face: `s` and `t` are the support surface's parameters
/// normalized over the face's parameter box (0 and 1 at its edges), `n` the signed distance along
/// the face's outward normal.
public struct UVNCoordinate: Equatable, Sendable {
    public var s: Double
    public var t: Double
    public var n: Double

    public init(s: Double, t: Double, n: Double) {
        self.s = s
        self.t = t
        self.n = n
    }
}

/// A face's UVN coordinates, the frame Deform carries curves and Wrap carries bodies between
/// faces in. A point takes the parameters of its nearest point on the face's support surface (not
/// clamped to the trim) and its height along the outward normal there; a coordinate is placed
/// back at those normalized parameters, that height along the outward normal. The parameters are
/// normalized over the face's own extent (`FaceParameterExtentResolver`), so its trim spans 0…1.
public struct FaceUVNChart: Sendable {
    public let reference: SurfaceReference
    /// The face's parameter box, over which `s` and `t` run from 0 to 1.
    public let box: SurfaceParameterBox
    private let surface: Surface3D
    private let document: any SurfaceQueryModel
    private let evaluator: SurfaceQueryEvaluator
    private let tolerance: ModelingTolerance

    public init(face reference: SurfaceReference, in document: some SurfaceQueryModel, tolerance: ModelingTolerance) throws {
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let resolved = try evaluator.resolve(reference, in: document)
        let box = try FaceParameterExtentResolver().bounds(for: resolved.faceID, in: document.brep, tolerance: tolerance)
        guard box.u.width > tolerance.distance, box.v.width > tolerance.distance else {
            throw KernelError(
                phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "A face with no parameter extent has no UVN coordinates."
            )
        }
        self.reference = reference
        self.box = box
        self.surface = resolved.surface
        self.document = document
        self.evaluator = evaluator
        self.tolerance = tolerance
    }

    public func coordinate(of point: Point3D) throws -> UVNCoordinate {
        let frame = try evaluator.outwardFrame(
            nearestTo: point, on: reference, in: document,
            options: SurfaceProjectionOptions(respectsTrimBounds: false)
        )
        let u = Self.unwrapped(frame.parameter.u, domain: surface.uDomain, interval: box.u)
        let v = Self.unwrapped(frame.parameter.v, domain: surface.vDomain, interval: box.v)
        let height = (point - frame.point).dot(try frame.outwardNormal.normalized(tolerance: 1.0e-15))
        return UVNCoordinate(
            s: (u - box.u.lower) / box.u.width,
            t: (v - box.v.lower) / box.v.width,
            n: height
        )
    }

    /// Fails when the parameters fall outside a bounded support surface.
    public func point(at coordinate: UVNCoordinate) throws -> Point3D {
        guard coordinate.s.isFinite, coordinate.t.isFinite, coordinate.n.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil, message: "A UVN coordinate must be finite.")
        }
        let u = box.u.lower + coordinate.s * box.u.width
        let v = box.v.lower + coordinate.t * box.v.width
        guard try surface.uDomain.contains(u, tolerance: tolerance), try surface.vDomain.contains(v, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A UVN coordinate at s \(coordinate.s), t \(coordinate.t) falls beyond the face's bounded support surface."
            )
        }
        let frame = try evaluator.outwardFrame(
            at: SurfaceParameterReference(surface: reference, u: u, v: v),
            in: document
        )
        return frame.point + (try frame.outwardNormal.normalized(tolerance: 1.0e-15)) * coordinate.n
    }

    /// A periodic parameter moved by whole periods to the turn that starts at the box's lower
    /// end, so a face across the seam reads one continuous range.
    static func unwrapped(_ value: Double, domain: ParameterDomain, interval: ScalarInterval) -> Double {
        guard case .periodic(let period) = domain, period > 0 else { return value }
        let turns = ((value - interval.lower) / period).rounded(.down)
        let shifted = value - turns * period
        // A value just below the lower end by rounding belongs to the box, not a period later.
        return shifted - interval.lower > interval.width + (period - interval.width) * 0.5 ? shifted - period : shifted
    }
}
