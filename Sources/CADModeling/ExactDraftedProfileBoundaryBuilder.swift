import Foundation
import CADCore
import CADGeometry
import CADIR

/// A drafted extrusion's section at one height: every wall of the profile moved toward the
/// material by `height · tangent`, so the section narrows along the extrusion axis for a positive
/// draft and one taper runs straight through the sketch plane.
///
/// Each line moves parallel to itself and each circular arc keeps its centre, its radius growing
/// or shrinking by the offset (a hole's wall moves away from the hole's centre as the outline's
/// moves toward it). Where two elements meet tangentially the joint moves along their common
/// normal; where two lines meet at a corner it moves to their offset lines' crossing (the miter).
/// Arcs come out as rational quadratic spans of at most a quarter turn, parameterised by angle,
/// so the spans at two heights correspond point for point and the surface ruled between them is
/// the exact cone.
package struct ExactDraftedProfileBoundaryBuilder: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    private enum Element {
        case line(start: Point3D, end: Point3D)
        case arc(ProfileCircularArcSegment)
    }

    /// The profile's loops, outer first, drafted to `height` along `axis` (the sketch plane's
    /// normal, either way), with `planeNormal` the normal the loops run counterclockwise about.
    package func boundaries(
        from profile: Profile,
        planeNormal: Vector3D,
        axis: Vector3D,
        height: Double,
        tangent: Double
    ) throws -> [[ExactPrismaticBoundarySegment]] {
        try tolerance.validate()
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let lift = try axis.normalized(tolerance: tolerance.distance) * height
        // Toward the material is inward: a positive draft narrows the section along the axis.
        let shift = -height * tangent
        return try profile.boundaryLoops.map { loop in
            let elements = try loop.boundarySegments.map { segment -> Element in
                switch segment {
                case let .line(line): return .line(start: line.start, end: line.end)
                case let .circularArc(arc): return .arc(arc)
                case .spline:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a spline's offset is not a spline, so a
                    // drafted extrusion of a spline section is refused. Production path:
                    // ExactProfileExtrudeBodyBuilder for every extrude with a draft angle. Complete
                    // only when a spline wall is drafted within a stated deviation, verified by a
                    // drafted spline section's volume and wall angle.
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                      message: "A drafted extrusion drafts line and circular-arc sections.")
                }
            }
            guard elements.isEmpty == false else { throw SketchError.openProfile }
            // The joint after each element, moved.
            var joints: [Point3D] = []
            for index in elements.indices {
                let this = elements[index]
                let next = elements[(index + 1) % elements.count]
                let corner = endPoint(of: this)
                let before = try travel(of: this, at: corner, atEnd: true)
                let after = try travel(of: next, at: corner, atEnd: false)
                let outBefore = before.cross(normal)
                let outAfter = after.cross(normal)
                if before.cross(after).length <= tolerance.angle, before.dot(after) > 0 {
                    joints.append(corner + outBefore * shift)
                } else if case .line = this, case .line = next {
                    let denominator = 1 + outBefore.dot(outAfter)
                    guard denominator > 1e-9 else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                          message: "A drafted extrusion's section turns back on itself at a corner.")
                    }
                    joints.append(corner + (outBefore + outAfter) * (shift / denominator))
                } else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): a corner where a circular arc meets another
                    // element at an angle drafts along a conic, not a ruling, so it is refused.
                    // Production path: ExactProfileExtrudeBodyBuilder for every extrude with a draft
                    // angle. Complete only when such a corner's edge is the plane-cone or cone-cone
                    // intersection, verified by a drafted slot with sharp arc corners.
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                      message: "A drafted extrusion drafts arcs that meet their neighbours tangentially.")
                }
            }
            var result: [ExactPrismaticBoundarySegment] = []
            for index in elements.indices {
                let start = joints[(index + elements.count - 1) % elements.count]
                let end = joints[index]
                switch elements[index] {
                case let .line(originalStart, originalEnd):
                    guard (end - start).dot(originalEnd - originalStart) > 0, (end - start).length > tolerance.distance else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                          message: "A drafted extrusion's wall vanishes or turns over at this height.")
                    }
                    result.append(try .line(from: start + lift, to: end + lift, tolerance: tolerance))
                case let .arc(arc):
                    let radial = try (arc.start - arc.center).normalized(tolerance: tolerance.distance)
                    let outward = try travel(of: elements[index], at: arc.start, atEnd: false).cross(normal)
                    let radius = arc.radius + shift * outward.dot(radial)
                    guard radius > tolerance.distance,
                          abs((start - arc.center).length - radius) <= tolerance.distance,
                          abs((end - arc.center).length - radius) <= tolerance.distance else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                          message: "A drafted extrusion's arc shrinks to nothing at this height.")
                    }
                    result.append(contentsOf: try spans(
                        center: arc.center + lift, normal: arc.normal, radius: radius,
                        start: start + lift, sweep: arc.sweepAngle
                    ))
                }
            }
            return result
        }
    }

    private func endPoint(of element: Element) -> Point3D {
        switch element {
        case let .line(_, end): end
        case let .arc(arc): arc.end
        }
    }

    /// The unit direction an element runs in at `point`, one of its ends.
    private func travel(of element: Element, at point: Point3D, atEnd: Bool) throws -> Vector3D {
        switch element {
        case let .line(start, end):
            return try (end - start).normalized(tolerance: tolerance.distance)
        case let .arc(arc):
            let normal = try arc.normal.normalized(tolerance: tolerance.distance)
            let direction = normal.cross(point - arc.center) * (arc.sweepAngle >= 0 ? 1 : -1)
            return try direction.normalized(tolerance: tolerance.distance)
        }
    }

    /// An arc from `start` sweeping `sweep` about `normal`, as rational quadratic spans of at most
    /// a quarter turn.
    private func spans(center: Point3D, normal: Vector3D, radius: Double, start: Point3D, sweep: Double) throws -> [ExactPrismaticBoundarySegment] {
        let circle = Circle3D(center: center, normal: try normal.normalized(tolerance: tolerance.distance), radius: radius)
        try circle.validate(tolerance: tolerance)
        let curve = Curve3D.circle(circle)
        let first = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        let count = max(1, Int(ceil(abs(sweep) / (0.5 * Double.pi))))
        return try (0..<count).map { index in
            let lower = first + sweep * Double(index) / Double(count)
            let upper = first + sweep * Double(index + 1) / Double(count)
            let weight = cos(0.5 * (upper - lower))
            let middle = try curve.point(at: 0.5 * (lower + upper), tolerance: tolerance)
            let span = BSplineCurve3D(
                degree: 2,
                knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [
                    try curve.point(at: lower, tolerance: tolerance),
                    center + (middle - center) / weight,
                    try curve.point(at: upper, tolerance: tolerance),
                ],
                weights: [1, weight, 1]
            )
            return try .bSpline(span, tolerance: tolerance)
        }
    }
}
