import Foundation
import CADCore
import CADGeometry

/// A planar curve for `PlanarCurveExtrusionIntersector`: its plane frame and its points and
/// first derivatives in the plane's (u, v) coordinates over `lower...upper`.
public struct PlanarFrameCurve: Sendable {
    public var origin: Point3D
    public var u: Vector3D
    public var v: Vector3D
    public var normal: Vector3D
    public var lower: Double
    public var upper: Double
    public var point: @Sendable (Double) throws -> Point2D
    public var derivative: @Sendable (Double) throws -> Point2D

    public init(
        origin: Point3D, u: Vector3D, v: Vector3D, normal: Vector3D, lower: Double, upper: Double,
        point: @escaping @Sendable (Double) throws -> Point2D,
        derivative: @escaping @Sendable (Double) throws -> Point2D
    ) {
        self.origin = origin
        self.u = u
        self.v = v
        self.normal = normal
        self.lower = lower
        self.upper = upper
        self.point = point
        self.derivative = derivative
    }

    func spatial(_ w: Double) throws -> Point3D {
        let p = try point(w)
        return origin + u * p.x + v * p.y
    }
}

/// Where two planar curves' extrusions meet, each extruded along its plane's normal: the 3D
/// curve whose projection onto each plane along that plane's normal is that plane's curve
/// (Project Curve Curve). Over the first curve's parameter w it is P₁(w) + s(w)·n₁ with
/// (P₁(w) + s·n₁ − O₂)·(u₂, v₂) = C₂(t(w)).
///
/// The trace starts at the first curve's lower end on the second curve's first crossing (in
/// its own parameter) and follows that branch by continuation over `traceSampleCount` steps;
/// a point between them is solved by Newton from the nearest traced step. Planes whose
/// normals are parallel have no such curve, and a first curve whose extrusion leaves the
/// second's partway fails.
public struct PlanarCurveExtrusionIntersector: Sendable {
    public static let traceSampleCount = 256
    static let scanSampleCount = 512
    static let maximumNewtonIterations = 32

    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public struct Trace: Sendable {
        let first: PlanarFrameCurve
        let second: PlanarFrameCurve
        let steps: [(w: Double, s: Double, t: Double)]
        let tolerance: ModelingTolerance

        /// The meeting point over the first curve's parameter `w`.
        public func point(at w: Double) throws -> Point3D {
            let nearest = steps.min { abs($0.w - w) < abs($1.w - w) }!
            let solved = try PlanarCurveExtrusionIntersector.solve(
                w: w, s: nearest.s, t: nearest.t, first: first, second: second, tolerance: tolerance
            )
            return try first.spatial(w) + first.normal * solved.s
        }
    }

    public func trace(first: PlanarFrameCurve, second: PlanarFrameCurve) throws -> Trace {
        let across = Point2D(x: first.normal.dot(second.u), y: first.normal.dot(second.v))
        guard hypot(across.x, across.y) > tolerance.angle else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                              message: "Curves on parallel planes extrude alongside each other and never meet in a curve.")
        }
        // The first crossing of the second curve by the first curve's extrusion line at its start.
        let start = try first.spatial(first.lower)
        let base = Point2D(x: (start - second.origin).dot(second.u), y: (start - second.origin).dot(second.v))
        func side(_ t: Double) throws -> Double {
            let p = try second.point(t)
            return across.x * (p.y - base.y) - across.y * (p.x - base.x)
        }
        var guess: (s: Double, t: Double)?
        var previousT = second.lower
        var previousSide = try side(previousT)
        for index in 1...Self.scanSampleCount {
            let t = second.lower + (second.upper - second.lower) * Double(index) / Double(Self.scanSampleCount)
            let current = try side(t)
            if previousSide == 0 || (previousSide < 0) != (current < 0) {
                let crossingT = previousSide == 0 ? previousT : previousT + (t - previousT) * previousSide / (previousSide - current)
                let p = try second.point(crossingT)
                let delta = Point2D(x: p.x - base.x, y: p.y - base.y)
                guess = ((delta.x * across.x + delta.y * across.y) / (across.x * across.x + across.y * across.y), crossingT)
                break
            }
            previousT = t
            previousSide = current
        }
        guard var current = guess else {
            throw KernelError(phase: .geometry, code: .emptyResult, tolerance: tolerance,
                              message: "The first curve's extrusion does not meet the second curve's.")
        }
        var steps: [(w: Double, s: Double, t: Double)] = []
        for index in 0...Self.traceSampleCount {
            let w = first.lower + (first.upper - first.lower) * Double(index) / Double(Self.traceSampleCount)
            current = try Self.solve(w: w, s: current.s, t: current.t, first: first, second: second, tolerance: tolerance)
            steps.append((w, current.s, current.t))
        }
        return Trace(first: first, second: second, steps: steps, tolerance: tolerance)
    }

    /// Newton on (s, t) for the first curve's parameter `w`; t must stay on the second curve.
    static func solve(
        w: Double, s: Double, t: Double,
        first: PlanarFrameCurve, second: PlanarFrameCurve, tolerance: ModelingTolerance
    ) throws -> (s: Double, t: Double) {
        let p = try first.spatial(w)
        let a = first.normal.dot(second.u), b = first.normal.dot(second.v)
        var s = s, t = t
        for _ in 0..<maximumNewtonIterations {
            let q = p + first.normal * s - second.origin
            let c = try second.point(t), d = try second.derivative(t)
            let fx = q.dot(second.u) - c.x, fy = q.dot(second.v) - c.y
            if hypot(fx, fy) <= tolerance.distance * 1.0e-3 {
                guard t >= second.lower - 1.0e-9, t <= second.upper + 1.0e-9 else { break }
                return (s, t)
            }
            // J = [[a, −dx], [b, −dy]].
            let determinant = a * -d.y - (-d.x) * b
            guard abs(determinant) > 1.0e-15 else { break }
            s -= (fx * -d.y - (-d.x) * fy) / determinant
            t -= (a * fy - b * fx) / determinant
        }
        throw KernelError(phase: .geometry, code: .emptyResult, tolerance: tolerance,
                          message: "The first curve's extrusion leaves the second curve's partway.")
    }
}
