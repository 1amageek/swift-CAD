import Foundation
import CADCore
import CADGeometry
import CADIR

/// A drafted or thin extrusion's section at one height: every wall of the profile moved toward the
/// material by `height · tangent`, so the section narrows along the extrusion axis for a positive
/// draft and one taper runs straight through the sketch plane.
///
/// Each line moves parallel to itself and each circular arc keeps its centre, its radius growing
/// or shrinking by the offset (a hole's wall moves away from the hole's centre as the outline's
/// moves toward it). Where two elements meet tangentially the joint moves along their common
/// normal; where two lines meet at a corner it moves to their offset lines' crossing (the miter).
/// Arcs come out as circular arcs of at most a quarter turn about the same axis at every height,
/// so the wall between two heights is the analytic cone through them (a cylinder without a draft);
/// an open curve's sheet takes them as rational quadratic spans parameterised by angle, which rule
/// point for point into the same cone. A spline's offset is `PlanarCurveOffsetApproximator`'s, on one basis for every
/// shift up to `splineReach`, so its walls between heights rule point for point too; a spline
/// meets its neighbours tangentially.
package struct ExactDraftedProfileBoundaryBuilder: Sendable {
    private let tolerance: ModelingTolerance
    /// The largest shift any height asks of a spline, which its offsets' shared basis serves.
    private let splineReach: Double

    package init(tolerance: ModelingTolerance, splineReach: Double = 0) {
        self.tolerance = tolerance
        self.splineReach = abs(splineReach)
    }

    private enum Element {
        case line(start: Point3D, end: Point3D)
        case arc(ProfileCircularArcSegment)
        case spline(BSplineCurve3D)
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
        return try profile.boundaryLoops.map { loop in
            try segments(try offset(try elements(of: loop), normal: normal, shift: -height * tangent, crossings: tangent == 0), lift: lift)
        }
    }

    /// An open curve's section drafted to `height` along `axis` as B-spline curves (lines of
    /// degree 1, arcs as rational quadratic spans, splines within the offset deviation), moved
    /// toward the curve's left about `planeNormal` by `height · tangent`: its ends move along their
    /// own normals, so a drafted curve sheet ruled between two heights leans by the draft.
    package func openCurve(
        _ curve: EvaluatedCurve,
        planeNormal: Vector3D,
        axis: Vector3D,
        height: Double,
        tangent: Double
    ) throws -> [BSplineCurve3D] {
        try tolerance.validate()
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let lift = try axis.normalized(tolerance: tolerance.distance) * height
        guard case let .closed(lower, upper)? = curve.exactParameterDomain, let exact = curve.exactCurve else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A drafted curve is unbounded.")
        }
        let element: Element
        switch exact {
        case let .line(line):
            element = .line(start: try Curve3D.line(line).point(at: lower, tolerance: tolerance),
                            end: try Curve3D.line(line).point(at: upper, tolerance: tolerance))
        case .circle, .analytic(.circle):
            let start = try exact.point(at: lower, tolerance: tolerance), end = try exact.point(at: upper, tolerance: tolerance)
            let (center, axisNormal, radius): (Point3D, Vector3D, Double)
            switch exact {
            case let .circle(circle): (center, axisNormal, radius) = (circle.center, circle.normal, circle.radius)
            case let .analytic(.circle(c, n, r)): (center, axisNormal, radius) = (c, n, r)
            default: throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A drafted arc lost its circle.")
            }
            element = .arc(ProfileCircularArcSegment(center: center, normal: axisNormal, radius: radius, start: start, end: end,
                                                     sweepAngle: upper - lower))
        default:
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: curve).map(\.curve)
            element = .spline(spans.count == 1 ? spans[0] : try ExactCompositeBSplineCurveBuilder().build(spans: spans, tolerance: tolerance))
        }
        // Toward the curve's left: the shift along the outward (right-hand) normal is negative.
        let shift = -height * tangent
        let first = try startPoint(of: element), last = endPoint(of: element)
        let start = try first + travel(of: element, at: first).cross(normal) * shift
        let end = try last + travel(of: element, at: last).cross(normal) * shift
        let moved = try place(element, from: start, to: end, normal: normal, shift: shift)
        return try segments([moved], lift: lift, arcsAsSpans: true).map { segment in
            switch segment.geometry {
            case .bSpline(let curve): return curve
            case .line:
                return BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [segment.startPoint, segment.endPoint], weights: [1, 1])
            case .circularArc:
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A drafted arc came out unconverted.")
            }
        }
    }

    private func startPoint(of element: Element) throws -> Point3D {
        switch element {
        case let .line(start, _): return start
        case let .arc(arc): return arc.start
        case let .spline(curve): return curve.controlPoints[0]
        }
    }

    /// The walls of a thin extrusion at `height`: for every loop a ring `thickness` wide on the
    /// material's side of its drafted boundary, each as its outer boundary and its one hole. The
    /// outline's ring runs inside it; a hole's ring runs around the hole.
    package func wallRegions(
        from profile: Profile,
        planeNormal: Vector3D,
        axis: Vector3D,
        height: Double,
        tangent: Double,
        thickness: Double
    ) throws -> [[[ExactPrismaticBoundarySegment]]] {
        try tolerance.validate()
        guard thickness.isFinite, thickness > tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A thin extrusion's wall thickness must be a positive length.")
        }
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let lift = try axis.normalized(tolerance: tolerance.distance) * height
        let shift = -height * tangent
        return try profile.boundaryLoops.enumerated().map { index, loop in
            let source = try elements(of: loop)
            // Without a draft every height takes the same section, so a sharp arc corner may join
            // at its offset curves' crossing.
            let face = try offset(source, normal: normal, shift: shift, crossings: tangent == 0)
            let back = try offset(source, normal: normal, shift: shift - thickness, crossings: tangent == 0)
            // The outline's ring is bounded by the outline and, as its hole, the wall's inner
            // face turned around; a hole's ring by the grown hole turned around and the hole.
            if index == 0 {
                return [try segments(face, lift: lift), try segments(reversed(back), lift: lift)]
            }
            return [try segments(reversed(back), lift: lift), try segments(face, lift: lift)]
        }
    }

    /// The rings of a thin section in its own plane, one profile per loop: the outline's ring
    /// runs inside it, a hole's around the hole, each `thickness` wide with exact lines and arcs.
    package func wallProfiles(from profile: Profile, planeNormal: Vector3D, thickness: Double, outward: Bool = false) throws -> [Profile] {
        try tolerance.validate()
        guard thickness.isFinite, thickness > tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A thin section's wall thickness must be a positive length.")
        }
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        return try profile.boundaryLoops.enumerated().map { index, loop in
            let source = try elements(of: loop)
            // Inward the wall runs into the region from each loop (the outline in, each hole out);
            // outward it runs away from the region (the outline out, each hole in).
            let shifted = try offset(source, normal: normal, shift: outward ? thickness : -thickness, crossings: true)
            let (outer, inner): ([Element], [Element])
            switch (index == 0, outward) {
            case (true, false): (outer, inner) = (source, reversed(shifted))
            case (true, true): (outer, inner) = (shifted, reversed(source))
            case (false, false): (outer, inner) = (reversed(shifted), source)
            case (false, true): (outer, inner) = (reversed(source), shifted)
            }
            return Profile(
                sourceFeatureID: profile.sourceFeatureID,
                plane: profile.plane,
                outerLoop: try profileLoop(outer),
                innerLoops: [try profileLoop(inner)]
            )
        }
    }

    /// `elements` as a profile loop, sampled at every line's start and eight points along each arc.
    private func profileLoop(_ elements: [Element]) throws -> ProfileLoop {
        var vertices: [Point3D] = []
        let segments = try elements.map { element -> ProfileBoundarySegment in
            switch element {
            case let .line(start, end):
                vertices.append(start)
                return .line(ProfileLineSegment(start: start, end: end))
            case let .arc(arc):
                let radial = arc.start - arc.center
                let axis = try arc.normal.normalized(tolerance: tolerance.distance).cross(radial)
                for index in 0..<8 {
                    let angle = arc.sweepAngle * Double(index) / 8
                    vertices.append(arc.center + radial * cos(angle) + axis * sin(angle))
                }
                return .circularArc(arc)
            case let .spline(curve):
                guard case let .closed(lower, upper) = curve.domain else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A wall's spline is unbounded.")
                }
                for index in 0..<8 {
                    vertices.append(try Curve3D.bSpline(curve).point(at: lower + (upper - lower) * Double(index) / 8, tolerance: tolerance))
                }
                return .spline(ProfileSplineSegment(curve: curve))
            }
        }
        return ProfileLoop(vertices: vertices, boundarySegments: segments)
    }

    private func elements(of loop: ProfileLoop) throws -> [Element] {
        let elements = try loop.boundarySegments.map { segment -> Element in
            switch segment {
            case let .line(line): return .line(start: line.start, end: line.end)
            case let .circularArc(arc): return .arc(arc)
            case let .spline(spline): return .spline(spline.curve)
            }
        }
        guard elements.isEmpty == false else { throw SketchError.openProfile }
        return elements
    }

    /// `elements` with every wall moved by `shift` along its outward side (negative: toward the
    /// material), joints moved with them. With `crossings`, a sharp corner at an arc joins where the
    /// two moved walls cross; without, such a corner is refused, as a drafted section's would sweep
    /// a conic between heights.
    private func offset(_ elements: [Element], normal: Vector3D, shift: Double, crossings: Bool) throws -> [Element] {
        var joints: [Point3D] = []
        for index in elements.indices {
            let this = elements[index]
            let next = elements[(index + 1) % elements.count]
            let corner = endPoint(of: this)
            let before = try travel(of: this, at: corner)
            let after = try travel(of: next, at: corner)
            let outBefore = before.cross(normal)
            let outAfter = after.cross(normal)
            if before.cross(after).length <= tolerance.angle, before.dot(after) > 0 {
                joints.append(corner + outBefore * shift)
            } else if case .line = this, case .line = next {
                let denominator = 1 + outBefore.dot(outAfter)
                guard denominator > 1e-9 else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                      message: "An offset section turns back on itself at a corner.")
                }
                joints.append(corner + (outBefore + outAfter) * (shift / denominator))
            } else if crossings, isSpline(this) == false, isSpline(next) == false {
                joints.append(try crossing(this, next, at: corner, normal: normal, shift: shift))
            } else if isSpline(this) || isSpline(next) {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a spline meeting its neighbour at a sharp
                // corner needs the offsets' crossing on the approximated spline, which is not built,
                // so it is refused. Production path: ExactDraftedProfileBoundaryBuilder for every
                // drafted or thin section with a spline. Complete only when such a corner joins at
                // the offsets' crossing, verified by a thin section of a spline and a line at an angle.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "An offset section's splines must meet their neighbours tangentially.")
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a drafted section's corner where a circular arc
                // meets another element at an angle moves along a conic between heights, not a
                // ruling, so it is refused. Production path: ExactProfileExtrudeBodyBuilder for every
                // extrude with a draft angle. Complete only when such a corner's drafted edge is the
                // surfaces' intersection, verified by a drafted slot with sharp arc corners.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "A drafted section's arcs must meet their neighbours tangentially.")
            }
        }
        return try elements.indices.map { index in
            try place(elements[index], from: joints[(index + elements.count - 1) % elements.count], to: joints[index],
                      normal: normal, shift: shift)
        }
    }

    /// `element` moved by `shift` along its outward side to run from `start` to `end`.
    private func place(_ element: Element, from start: Point3D, to end: Point3D, normal: Vector3D, shift: Double) throws -> Element {
        switch element {
        case let .line(originalStart, originalEnd):
            guard (end - start).dot(originalEnd - originalStart) > 0, (end - start).length > tolerance.distance else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "An offset section's wall vanishes or turns over.")
            }
            return .line(start: start, end: end)
        case let .spline(curve):
            let approximator = PlanarCurveOffsetApproximator(tolerance: tolerance)
            let knots = try approximator.basis(for: curve, normal: normal, reach: max(splineReach, abs(shift)))
            let moved = try approximator.offset(curve, normal: normal, shift: shift, knots: knots)
            guard let first = moved.controlPoints.first, let last = moved.controlPoints.last,
                  (first - start).length <= tolerance.distance, (last - end).length <= tolerance.distance else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "An offset spline does not meet its neighbours' joints.")
            }
            var points = moved.controlPoints
            points[0] = start
            points[points.count - 1] = end
            return .spline(BSplineCurve3D(degree: moved.degree, knots: moved.knots, controlPoints: points, weights: moved.weights))
        case let .arc(arc):
            let radial = try (arc.start - arc.center).normalized(tolerance: tolerance.distance)
            let outward = try travel(of: element, at: arc.start).cross(normal)
            let radius = arc.radius + shift * outward.dot(radial)
            guard radius > tolerance.distance,
                  abs((start - arc.center).length - radius) <= tolerance.distance,
                  abs((end - arc.center).length - radius) <= tolerance.distance else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "An offset section's arc shrinks to nothing.")
            }
            // The turn from the moved start to the moved end, the way the arc runs.
            let arcNormal = try arc.normal.normalized(tolerance: tolerance.distance)
            let (a, b) = (start - arc.center, end - arc.center)
            var sweep = atan2(arcNormal.dot(a.cross(b)), a.dot(b))
            if arc.sweepAngle > 0, sweep <= tolerance.angle { sweep += 2 * Double.pi }
            if arc.sweepAngle < 0, sweep >= -tolerance.angle { sweep -= 2 * Double.pi }
            return .arc(ProfileCircularArcSegment(
                center: arc.center, normal: arc.normal, radius: radius, start: start, end: end, sweepAngle: sweep
            ))
        }
    }

    /// Where `before` and `after`, both moved by `shift`, cross nearest their corner: a line's
    /// parallel and an arc's concentric circle meeting in the section's plane.
    private func crossing(_ before: Element, _ after: Element, at corner: Point3D, normal: Vector3D, shift: Double) throws -> Point3D {
        enum Moved {
            case line(point: Point3D, direction: Vector3D)
            case circle(center: Point3D, radius: Double)
        }
        func moved(_ element: Element) throws -> Moved {
            let out = try travel(of: element, at: corner).cross(normal)
            switch element {
            case let .line(start, end):
                return .line(point: corner + out * shift, direction: try (end - start).normalized(tolerance: tolerance.distance))
            case let .arc(arc):
                let radial = try (corner - arc.center).normalized(tolerance: tolerance.distance)
                return .circle(center: arc.center, radius: arc.radius + shift * out.dot(radial))
            case .spline:
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "An offset spline's crossing with its neighbour is not solved.")
            }
        }
        // Coordinates in the section's plane about the corner.
        let seed: Vector3D = abs(normal.x) < 0.6 ? .unitX : .unitY
        let u = try normal.cross(seed).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        func flat(_ point: Point3D) -> (Double, Double) { ((point - corner).dot(u), (point - corner).dot(v)) }
        func flat(_ vector: Vector3D) -> (Double, Double) { (vector.dot(u), vector.dot(v)) }
        func back(_ x: Double, _ y: Double) -> Point3D { corner + u * x + v * y }
        var candidates: [(Double, Double)] = []
        switch (try moved(before), try moved(after)) {
        case let (.line(p, d), .circle(c, r)), let (.circle(c, r), .line(p, d)):
            let (px, py) = flat(p), (dx, dy) = flat(d), (cx, cy) = flat(c)
            let (fx, fy) = (px - cx, py - cy)
            let b = fx * dx + fy * dy
            let discriminant = b * b - (fx * fx + fy * fy - r * r)
            if discriminant >= 0 {
                for t in [-b - discriminant.squareRoot(), -b + discriminant.squareRoot()] { candidates.append((px + dx * t, py + dy * t)) }
            }
        case let (.circle(c1, r1), .circle(c2, r2)):
            let (x1, y1) = flat(c1), (x2, y2) = flat(c2)
            let (ex, ey) = (x2 - x1, y2 - y1)
            let distance = (ex * ex + ey * ey).squareRoot()
            if distance > tolerance.distance {
                let along = (r1 * r1 - r2 * r2 + distance * distance) / (2 * distance)
                let height = r1 * r1 - along * along
                if height >= 0 {
                    let (mx, my) = (x1 + ex * along / distance, y1 + ey * along / distance)
                    let h = height.squareRoot()
                    candidates.append((mx - ey * h / distance, my + ex * h / distance))
                    candidates.append((mx + ey * h / distance, my - ex * h / distance))
                }
            }
        case (.line, .line):
            break
        }
        guard let nearest = candidates.min(by: { ($0.0 * $0.0 + $0.1 * $0.1) < ($1.0 * $1.0 + $1.1 * $1.1) }),
              (nearest.0 * nearest.0 + nearest.1 * nearest.1).squareRoot() <= 10 * abs(shift) + tolerance.distance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "An offset section's walls no longer meet at a corner.")
        }
        return back(nearest.0, nearest.1)
    }

    /// `elements` run the other way.
    private func reversed(_ elements: [Element]) -> [Element] {
        elements.reversed().map { element in
            switch element {
            case let .line(start, end): .line(start: end, end: start)
            case let .spline(curve): .spline(reversedSpline(curve))
            case let .arc(arc):
                .arc(ProfileCircularArcSegment(
                    center: arc.center, normal: arc.normal, radius: arc.radius, start: arc.end, end: arc.start, sweepAngle: -arc.sweepAngle
                ))
            }
        }
    }

    /// `elements` lifted by `lift`, lines as lines and arcs as circular arcs of at most a quarter
    /// turn (rational quadratic spans when `arcsAsSpans`, for a curve's B-spline sheet).
    private func segments(_ elements: [Element], lift: Vector3D, arcsAsSpans: Bool = false) throws -> [ExactPrismaticBoundarySegment] {
        var result: [ExactPrismaticBoundarySegment] = []
        for element in elements {
            switch element {
            case let .line(start, end):
                result.append(try .line(from: start + lift, to: end + lift, tolerance: tolerance))
            case let .arc(arc):
                result.append(contentsOf: try spans(
                    center: arc.center + lift, normal: arc.normal, radius: arc.radius,
                    start: arc.start + lift, sweep: arc.sweepAngle, asSpans: arcsAsSpans
                ))
            case let .spline(curve):
                result.append(try .bSpline(BSplineCurve3D(degree: curve.degree, knots: curve.knots,
                                                          controlPoints: curve.controlPoints.map { $0 + lift }, weights: curve.weights),
                                           tolerance: tolerance))
            }
        }
        return result
    }

    private func endPoint(of element: Element) -> Point3D {
        switch element {
        case let .line(_, end): end
        case let .arc(arc): arc.end
        case let .spline(curve): curve.controlPoints[curve.controlPoints.count - 1]
        }
    }

    private func isSpline(_ element: Element) -> Bool {
        if case .spline = element { return true }
        return false
    }

    /// `curve` run the other way on the same parameter range.
    private func reversedSpline(_ curve: BSplineCurve3D) -> BSplineCurve3D {
        let (lower, upper) = (curve.knots[0], curve.knots[curve.knots.count - 1])
        return BSplineCurve3D(degree: curve.degree, knots: curve.knots.reversed().map { lower + upper - $0 },
                              controlPoints: curve.controlPoints.reversed(), weights: curve.weights.reversed())
    }

    /// The unit direction an element runs in at `point`, one of its ends.
    private func travel(of element: Element, at point: Point3D) throws -> Vector3D {
        switch element {
        case let .line(start, end):
            return try (end - start).normalized(tolerance: tolerance.distance)
        case let .arc(arc):
            let normal = try arc.normal.normalized(tolerance: tolerance.distance)
            let direction = normal.cross(point - arc.center) * (arc.sweepAngle >= 0 ? 1 : -1)
            return try direction.normalized(tolerance: tolerance.distance)
        case let .spline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A wall's spline is unbounded.")
            }
            let atStart = (try Curve3D.bSpline(curve).point(at: lower, tolerance: tolerance) - point).length
                <= (try Curve3D.bSpline(curve).point(at: upper, tolerance: tolerance) - point).length
            return try Curve3D.bSpline(curve).differentialGeometry(at: atStart ? lower : upper, tolerance: tolerance)
                .firstDerivative.normalized(tolerance: tolerance.distance)
        }
    }

    /// An arc from `start` sweeping `sweep` about `normal`, in pieces of at most a quarter turn:
    /// circular arcs, or rational quadratic spans `asSpans`.
    private func spans(center: Point3D, normal: Vector3D, radius: Double, start: Point3D, sweep: Double,
                       asSpans: Bool) throws -> [ExactPrismaticBoundarySegment] {
        let circle = Circle3D(center: center, normal: try normal.normalized(tolerance: tolerance.distance), radius: radius)
        try circle.validate(tolerance: tolerance)
        let curve = Curve3D.circle(circle)
        let first = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
        let count = max(1, Int(ceil(abs(sweep) / (0.5 * Double.pi))))
        return try (0..<count).map { index in
            let lower = first + sweep * Double(index) / Double(count)
            let upper = first + sweep * Double(index + 1) / Double(count)
            guard asSpans else {
                return try .circularArc(circle: circle, startParameter: lower, endParameter: upper, tolerance: tolerance)
            }
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
