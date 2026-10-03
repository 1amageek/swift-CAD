import Foundation
import CADCore
import CADGeometry
import CADIR

/// A path-normal Sweep along a curved path, within a certified positional allowance.
///
/// The section moves rigidly with the path's minimal-rotation frame: at a path point with unit
/// tangent `t` a section point `P` goes to `p + R(t_ref → t)·v`, where `v` is `P`'s offset from
/// the path start carried by the frame so far and `R(a → b)` is the least rotation taking `a` to
/// `b`. The frame restarts its reference wherever the tangent has turned far from it. Each path
/// piece becomes one cubic Hermite row of tensor patches per section span; the Hermite remainder
/// comes from enclosures of the moved control points' fourth derivatives, and the rows' rounding
/// from the enclosures of their values, together within the allowance.
///
/// Admission also proves that the sweep does not overlap itself: the section stays inside the
/// path's bend (its reach times the path curvature below one on every piece), and every two pieces
/// that do not touch are apart, by their distance or by a plane across the path between them.
package struct CertifiedCurvedPathSweepPlan: Sendable {
    package typealias Interval = OutwardScalarInterval

    package let profileSpanLoops: [[ExactBSplineCurveSpan]]
    package let sectionIsClosed: Bool
    package let profilePlane: SketchPlane
    /// Indexed by loop, then path piece, then section span.
    package let surfaces: [[[BSplineSurface3D]]]
    package let pieceCount: Int
    /// The section plane's normal at the start and where the frame carries it at the end.
    package let startNormal: Vector3D
    package let endNormal: Vector3D
    /// The sign of the section normal along the path tangent, the same all along the path.
    package let advanceSign: Double
    package let positionErrorUpperBound: Double
    /// Whether the path closes on itself: the sweep then has no caps, its last row the first.
    package let pathIsClosed: Bool
    /// How far the section comes back turned about the path where a closed path closes, in
    /// radians: zero once the twist law has taken the frame's turn out.
    package let closingTurn: Double
    /// Whether a closed path's last row was made its first.
    package let seamClosed: Bool

    /// Whether a sweep takes this plan: path-normal alignment along a path that is neither
    /// straight nor a circular arc the exact circular sweep already builds as a solid.
    package static func applies(
        _ options: SweepOptions,
        pathSpans: [ExactBSplineCurveSpan],
        exactCircularSolid: Bool,
        tolerance: ModelingTolerance
    ) -> Bool {
        options.alignment == .normal && exactCircularSolid == false && isStraight(pathSpans, tolerance: tolerance) == false
    }

    private static func isStraight(_ spans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance) -> Bool {
        guard let start = spans.first?.startPoint, let end = spans.last?.endPoint else { return true }
        let chord = end - start
        guard chord.length > tolerance.distance else { return false }
        let direction = chord * (1 / chord.length)
        return spans.allSatisfy { span in
            span.curve.controlPoints.allSatisfy { point in
                let offset = point - start
                return (offset - direction * offset.dot(direction)).length <= tolerance.distance
            }
        }
    }

    /// The plan for a resolved section: a profile's loops, or a curve as one open or closed loop.
    package init(
        section: ResolvedModelingSection,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        guide: [BSplineCurve3D]? = nil,
        pathIsClosed: Bool = false,
        closesSeam: Bool = false,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws {
        let spans = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        switch section {
        case .profile(let profile, _):
            try self.init(sectionLoops: try spans.profileLoopSpans(from: profile), sectionIsClosed: true,
                profilePlane: profile.plane, pathSpans: pathSpans, sweep: sweep, values: values, guide: guide,
                pathIsClosed: pathIsClosed, closesSeam: closesSeam, featureID: featureID, tolerance: tolerance)
        case .curve(let curve):
            try self.init(sectionLoops: [try spans.sectionSpans(from: curve)], sectionIsClosed: curve.isClosed,
                profilePlane: try section.plane(), pathSpans: pathSpans, sweep: sweep, values: values, guide: guide,
                pathIsClosed: pathIsClosed, closesSeam: closesSeam, featureID: featureID, tolerance: tolerance)
        }
    }

    package init(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        guide guideSpans: [BSplineCurve3D]? = nil,
        pathIsClosed: Bool = false,
        closesSeam: Bool = false,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard let allowance = values.approximationTolerance, allowance.isFinite, allowance > 0 else {
            throw Self.failure(.sweepPathNormalUnavailable,
                "A path-normal sweep along a curved path needs a positional approximation allowance.", featureID, tolerance)
        }
        // The twist turns the section about the path and the scale grows it, both by laws of the
        // fraction of the path's length run so far.
        let twistPositions = values.twistPositions
        let twistAngles = values.twistAngles.isEmpty ? [0, values.twistAngle] : values.twistAngles
        guard twistPositions.count == twistAngles.count, twistPositions.count >= 2,
              twistAngles.allSatisfy({ $0.isFinite && abs($0) <= 16 }), values.endScale.isFinite, values.endScale > 0 else {
            throw Self.failure(.sweepTwistUnavailable,
                "A curved sweep's twist law is finite within 16 radians and its end scale positive.", featureID, tolerance)
        }
        let guided = sweep.guides.isEmpty == false
        let twists = twistAngles.contains { $0 != 0 } || guided
        let scales = values.endScale != 1 || (guided && sweep.options.guideMethod == .point)
        func twist(at fraction: Double) -> Double {
            guard let upper = twistPositions.firstIndex(where: { $0 >= fraction }), upper > 0 else {
                return fraction <= (twistPositions.first ?? 0) ? twistAngles[0] : twistAngles[twistAngles.count - 1]
            }
            let (f0, f1) = (twistPositions[upper - 1], twistPositions[upper])
            let ratio = f1 > f0 ? (fraction - f0) / (f1 - f0) : 1
            return twistAngles[upper - 1] + (twistAngles[upper] - twistAngles[upper - 1]) * ratio
        }
        func scale(at fraction: Double) -> Double { 1 + (values.endScale - 1) * fraction }
        // One guide steers the section by its method in the moving frame (CurvedSweepGuideLaw).
        guard guided == false || (sweep.guides.count == 1 && guideSpans?.isEmpty == false) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): two or more guides along a curved path would deform
            // the section by more than a turn and a scale, which is not built, so they are
            // refused. Production path: CertifiedCurvedPathSweepPlan for every guided curved
            // Sweep. Complete only when several guides steer a curved sweep, verified by its
            // sections meeting every guide.
            throw Self.failure(.sweepGuideConstraintUnavailable, "A curved path-normal sweep takes one guide.", featureID, tolerance)
        }
        guard guided == false || (values.twistAngle == 0 && sweep.options.twistLaw == nil && values.endScale == 1) else {
            throw Self.failure(.sweepTwistUnavailable, "A guided curved sweep takes no twist or scale of its own.", featureID, tolerance)
        }
        guard sweep.options.resultKind == .sheet || sectionIsClosed else {
            throw Self.failure(.invalidInput, "A solid sweep needs a closed section.", featureID, tolerance)
        }
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let sectionPlane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance).plane
        for loop in sectionLoops {
            try patches.validateSectionContinuity(loop, isClosed: sectionIsClosed)
            try patches.validateProfileSpans(loop, on: sectionPlane)
        }
        guard pathSpans.isEmpty == false,
              pathSpans.allSatisfy({ $0.curve.controlPointCount == $0.curve.degree + 1 && $0.curve.degree >= 1 }) else {
            throw Self.failure(.invalidInput, "A curved sweep's path spans are single rational Bezier pieces.", featureID, tolerance)
        }
        let spanCount = sectionLoops.reduce(0) { $0 + $1.count }
        let controlCount = sectionLoops.flatMap { $0 }.reduce(0) { $0 + $1.curve.controlPointCount }
        // Bounded work before tensor or topology allocation: refusal ceilings, not a sampling
        // density.
        guard spanCount > 0, spanCount <= 4096, controlCount <= 65536 else { throw Self.exhausted(featureID, tolerance) }
        let maximumPieces = min(4096 / spanCount, 262144 / max(4 * controlCount, 1))
        guard maximumPieces > 0 else { throw Self.exhausted(featureID, tolerance) }

        let beziers = try pathSpans.map { try HomogeneousBezier(span: $0) }
        // The arc length run along the path, for the laws: the length of each span by composite
        // Gauss–Legendre quadrature. The laws are met at every piece's ends and run linearly in
        // the piece's parameter between them.
        func arcLength(_ curve: BSplineCurve3D, upTo fraction: Double) throws -> Double {
            guard case let .closed(lower, upper) = curve.domain, fraction > 0 else { return 0 }
            let end = lower + (upper - lower) * fraction
            let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
            let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
            var sum = 0.0
            for index in 0..<32 {
                let left = lower + (end - lower) * Double(index) / 32, half = (end - lower) / 64
                for (node, weight) in zip(nodes, weights) {
                    sum += weight * half * (try curve.differentialGeometry(at: left + half * (1 + node), tolerance: tolerance)).firstDerivative.length
                }
            }
            return sum
        }
        let lawful = (twists || scales) && guided == false
        let spanLengths = lawful ? try pathSpans.map { try arcLength($0.curve, upTo: 1) } : pathSpans.map { _ in 0 }
        let totalLength = spanLengths.reduce(0, +)
        let spanStarts = spanLengths.indices.map { spanLengths.prefix($0).reduce(0, +) }
        func fraction(span: Int, at parameter: Double) throws -> Double {
            guard lawful, totalLength > 0 else { return 0 }
            return min(1, (spanStarts[span] + (try arcLength(pathSpans[span].curve, upTo: parameter))) / totalLength)
        }
        // Tangent continuity along the path: a corner needs a mitre or a round.
        for index in beziers.indices.dropFirst() {
            let before = try beziers[index - 1].pointJet(at: .end, order: 1).tangent()
            let after = try beziers[index].pointJet(at: .start, order: 1).tangent()
            guard let before, let after, before.cross(after).length <= sin(tolerance.angle), before.dot(after) > 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a path with a corner is refused. Production
                // path: CertifiedCurvedPathSweepPlan for every path-normal Sweep. Complete only
                // when Mitre and Round corners join the pieces either side, verified by a sweep
                // along an L-shaped path's volume.
                throw Self.failure(.sweepRoundCornerUnavailable,
                    "A curved path-normal sweep needs a path without corners.", featureID, tolerance)
            }
        }
        if pathIsClosed {
            // A closed path closes smoothly, its end leaving the way its start does.
            let before = try beziers[beziers.count - 1].pointJet(at: .end, order: 1).tangent()
            let after = try beziers[0].pointJet(at: .start, order: 1).tangent()
            guard let before, let after, before.cross(after).length <= sin(tolerance.angle), before.dot(after) > 0 else {
                throw Self.failure(.sweepRoundCornerUnavailable,
                    "A closed curved path sweeps only where it closes smoothly.", featureID, tolerance)
            }
        }
        let startJet = try beziers[0].pointJet(at: .start, order: 1)
        guard let startTangent = try startJet.tangent() else {
            throw Self.failure(.invalidInput, "The sweep path has no tangent at its start.", featureID, tolerance)
        }
        let pathStart = pathSpans[0].startPoint
        let normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        let advance = normal.dot(startTangent)
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw Self.failure(.sweepProfilePlaneDegenerate,
                "The section's plane runs along the path, so sweeping it makes no volume.", featureID, tolerance)
        }

        // The section's control points as offsets from the path start, with the section normal
        // carried alongside; all move with the frame.
        let sectionPoints = sectionLoops.flatMap { $0.flatMap(\.curve.controlPoints) }
        // Across the start tangent the section spans two lateral axes the frame also carries, so
        // the overlap certificate reads the section's extent along each of them.
        let lateral = try Self.lateralAxes(of: startTangent, tolerance: tolerance)
        // The frame carries the section normal and the two lateral axes; each section point is
        // its offsets along the start tangent and those axes.
        var carried: [[Interval]] = [Self.values(normal), Self.values(lateral.0), Self.values(lateral.1)]
        let offsets = sectionPoints.map { $0 - pathStart }
        let coordinates = offsets.map { offset in
            SectionCoordinates(along: .exact(offset.dot(startTangent)), first: .exact(offset.dot(lateral.0)), second: .exact(offset.dot(lateral.1)))
        }
        let normalCoordinates = SectionCoordinates(along: .exact(normal.dot(startTangent)),
            first: .exact(normal.dot(lateral.0)), second: .exact(normal.dot(lateral.1)))
        let guideLaw = try guideSpans.map { spans in
            try CurvedSweepGuideLaw(method: sweep.options.guideMethod, guide: spans,
                                    section: sectionLoops.flatMap { $0.map(\.curve) }, pathStart: pathStart,
                                    startTangent: startTangent, startAxes: (lateral.0, lateral.1), featureID: featureID, tolerance: tolerance)
        }
        // The section's reach about the path start, and the largest scale its sections take: the
        // end scale's, or (guided) the largest a guide's law takes on an accepted piece.
        let baseReach = offsets.map(\.length).max() ?? 0
        var largestScale = max(1, values.endScale)
        var smallestScale = min(1, values.endScale)
        let extent = { (axis: Vector3D) -> Interval in
            let values = offsets.map { $0.dot(axis) }
            return Interval(lower: (values.min() ?? 0).nextDown, upper: (values.max() ?? 0).nextUp)
        }
        // A twist turns the lateral offsets anywhere within their radius; a scale grows them all.
        let lateralRadius = offsets.map { offset -> Double in
            let along = offset.dot(startTangent)
            return max(0, offset.length * offset.length - along * along).squareRoot()
        }.max() ?? 0
        let turned = Interval(lower: -lateralRadius.nextUp, upper: lateralRadius.nextUp)
        /// A section point moved by the frame, turned by the twist and grown by the scale.
        func moved(
            _ point: SectionCoordinates, path: IntervalVectorDerivativeJet, frame: RotationJet,
            cosine: IntervalDerivativeJet, sine: IntervalDerivativeJet, scale: IntervalDerivativeJet
        ) -> IntervalVectorDerivativeJet {
            let order = cosine.order
            let first = frame.rotated(carried[1]), second = frame.rotated(carried[2])
            let a = cosine.scaled(by: point.first) - sine.scaled(by: point.second)
            let b = sine.scaled(by: point.first) + cosine.scaled(by: point.second)
            let offset = frame.tangent.scaled(by: .constant(point.along, order: order))
                + first.scaled(by: a) + second.scaled(by: b)
            return path + offset.scaled(by: scale)
        }
        /// The twist's cosine and sine and the scale over a piece (or at an end), linear in its
        /// parameter from `start` to `end`.
        func laws(_ start: (angle: Double, scale: Double), _ end: (angle: Double, scale: Double), at place: HomogeneousBezier.Place, order: Int)
            throws -> (cosine: IntervalDerivativeJet, sine: IntervalDerivativeJet, scale: IntervalDerivativeJet) {
            let rate = Interval.exact(end.angle) - .exact(start.angle)
            let range: Interval
            switch place {
            case .whole: range = Interval(lower: min(start.angle, end.angle), upper: max(start.angle, end.angle))
            case .start: range = .exact(start.angle)
            case .end: range = .exact(end.angle)
            }
            let trig = try CertifiedRotationTrigonometry.evaluate(range, tolerance: tolerance)
            // The k-th derivative of cos(θ0 + δτ) is δᵏ cos(θ + kπ/2), and likewise for the sine.
            var cosine: [Interval] = [], sine: [Interval] = []
            var power = Interval.exact(1)
            for k in 0...order {
                let (c, s): (Interval, Interval) = [(trig.cosine, trig.sine), (-trig.sine, trig.cosine),
                                                    (-trig.cosine, -trig.sine), (trig.sine, -trig.cosine)][k % 4]
                cosine.append(c * power)
                sine.append(s * power)
                power = power * rate
            }
            let growth = Interval.exact(end.scale) - .exact(start.scale)
            let scaleValue: Interval
            switch place {
            case .whole: scaleValue = Interval(lower: min(start.scale, end.scale), upper: max(start.scale, end.scale))
            case .start: scaleValue = .exact(start.scale)
            case .end: scaleValue = .exact(end.scale)
            }
            let scaleJet = IntervalDerivativeJet(derivatives: [scaleValue, growth] + Array(repeating: .exact(0), count: max(0, order - 1)))
            return (IntervalDerivativeJet(derivatives: cosine), IntervalDerivativeJet(derivatives: sine),
                    IntervalDerivativeJet(derivatives: Array(scaleJet.derivatives.prefix(order + 1))))
        }

        var frameReference = startTangent
        var chunkStarted = true
        // The guide's state and law where the last accepted piece ended.
        var guideState: CurvedSweepGuideLaw.State?
        var guideStart = (angle: 0.0, scale: 1.0)
        var stationValues: [[Interval]]?
        var rows: [[[Point3D]]] = []   // piece, row (4), section control point
        var pieces: [AcceptedPiece] = []
        var maximumError = 0.0
        var endNormalEnclosure: [Interval] = Self.values(normal)
        var endLateral = lateral.0
        let third = Interval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)

        /// Accepts the piece, or says why it must be halved and how deep halving may go.
        func accept(_ bezier: HomogeneousBezier, span: Int, lower: Double, upper: Double) throws -> (reason: String, limit: Int)? {
            guard pieces.count < maximumPieces else { throw Self.exhausted(featureID, tolerance) }
            let whole = try bezier.jet(over: .whole, order: 5)
            guard let tangent = whole.unitTangent(), let path = whole.position else {
                return ("The sweep path's speed is not certified positive.", 20)
            }
            var frame = try RotationJet(reference: frameReference, tangent: tangent)
            if (frame?.clearance.lower ?? 0) <= 0.5 {
                // The tangent has turned far from the reference: restart the frame here.
                guard chunkStarted == false else {
                    return ("The sweep path turns too sharply to follow.", 20)
                }
                let station = try bezier.pointJet(at: .start, order: 1)
                guard let restart = try station.tangent() else {
                    throw Self.failure(.invalidInput, "The sweep path has no tangent where its frame restarts.", featureID, tolerance)
                }
                guard let turn = try RotationJet(reference: frameReference, tangent: .constant(Self.values(restart), order: 0)) else {
                    throw Self.failure(.invalidInput, "The sweep frame cannot restart.", featureID, tolerance)
                }
                carried = carried.map { turn.rotated($0).derivative(0) }
                frameReference = restart
                chunkStarted = true
                frame = try RotationJet(reference: frameReference, tangent: tangent)
                guard let restarted = frame, restarted.clearance.lower > 0.5 else {
                    return ("The sweep path turns too sharply to follow.", 20)
                }
            }
            guard let frame else { return ("The sweep frame is not certified.", 20) }
            // The section stays inside the path's bend.
            let velocity = path.derivative(1)
            let acceleration = path.derivative(2)
            let bend = [
                velocity[1] * acceleration[2] - velocity[2] * acceleration[1],
                velocity[2] * acceleration[0] - velocity[0] * acceleration[2],
                velocity[0] * acceleration[1] - velocity[1] * acceleration[0],
            ]
            let bendUpper = bend.reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) * .exact($1.absoluteUpperBound) }.upper.squareRoot().nextUp
            let speedSquared = velocity.reduce(Interval.exact(0)) { $0 + .exact($1.absoluteLowerBound) * .exact($1.absoluteLowerBound) }.lower
            let speed = max(0, speedSquared).squareRoot().nextDown
            let curvature = speed > 0 ? (bendUpper / (speed * speed * speed).nextDown).nextUp : .infinity
            let startLaw: (angle: Double, scale: Double), endLaw: (angle: Double, scale: Double)
            var middleScale = 0.0
            var guideEndState: CurvedSweepGuideLaw.State?
            if let guideLaw {
                // The guide's law at the piece's ends (its start the last piece's end), and in its
                // middle to bound how far the linear law between them strays from the guide.
                func station(_ jet: PathJet) throws -> (Point3D, Vector3D, (first: Vector3D, second: Vector3D))? {
                    guard let position = jet.position?.derivative(0), let direction = try jet.tangent(),
                          let stationFrame = try RotationJet(reference: frameReference, tangent: .constant(Self.values(direction), order: 0)) else { return nil }
                    let first = stationFrame.rotated(carried[1]).derivative(0), second = stationFrame.rotated(carried[2]).derivative(0)
                    func point(_ v: [Interval]) -> Vector3D { Vector3D(x: v[0].midpoint, y: v[1].midpoint, z: v[2].midpoint) }
                    return (Point3D(x: position[0].midpoint, y: position[1].midpoint, z: position[2].midpoint), direction,
                            (try point(first).normalized(tolerance: tolerance.distance), try point(second).normalized(tolerance: tolerance.distance)))
                }
                let begin = guideState ?? guideLaw.initial
                guard let endStation = try station(try bezier.pointJet(at: .end, order: 1)),
                      let middleStation = try station(try bezier.halves().1.pointJet(at: .start, order: 1)) else {
                    return ("The sweep frame is not certified at a guide station.", 20)
                }
                let middle = try guideLaw.evaluate(at: middleStation.0, tangent: middleStation.1, axes: middleStation.2, from: begin, featureID: featureID)
                let end = try guideLaw.evaluate(at: endStation.0, tangent: endStation.1, axes: endStation.2, from: middle.state, featureID: featureID)
                startLaw = guideStart
                endLaw = (end.angle, end.scale)
                middleScale = middle.scale
                // The linear law between the ends strays from the guide's in the middle by at most
                // this much at the section's reach.
                let stray = baseReach * (abs(middle.angle - 0.5 * (startLaw.angle + endLaw.angle)) * max(middle.scale, 1)
                    + abs(middle.scale - 0.5 * (startLaw.scale + endLaw.scale)))
                guard stray <= allowance * 0.25 else {
                    // A piece no longer than a few modeling distances cannot be halved into
                    // pieces its sewing keeps apart: the guide turns the section faster there
                    // than any allowance follows (a Curve guide starting square to the section's
                    // side turns it as the square root of the run), which is refused.
                    if (endStation.0 - (try bezier.pointJet(at: .start, order: 0).position.map { position in
                        Point3D(x: position.derivative(0)[0].midpoint, y: position.derivative(0)[1].midpoint, z: position.derivative(0)[2].midpoint)
                    } ?? endStation.0)).length <= 16 * tolerance.distance {
                        throw Self.failure(.sweepGuideContactUnavailable,
                            "The guide turns the section faster than the allowance follows; start it off the square of the section's side.",
                            featureID, tolerance)
                    }
                    return ("The guide turns the section faster than the allowance follows.", 40)
                }
                guideEndState = end.state
            } else {
                let startFraction = try fraction(span: span, at: lower), endFraction = try fraction(span: span, at: upper)
                startLaw = (angle: twist(at: startFraction), scale: scale(at: startFraction))
                endLaw = (angle: twist(at: endFraction), scale: scale(at: endFraction))
            }
            let pieceLaws = try laws(startLaw, endLaw, at: .whole, order: 4)
            var remainder = 0.0
            for point in coordinates {
                let swept = moved(point, path: path, frame: frame, cosine: pieceLaws.cosine, sine: pieceLaws.sine, scale: pieceLaws.scale)
                let fourth = swept.derivative(4).reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) }
                remainder = max(remainder, (fourth * .exact(1.0 / 384)).upper)
            }
            let pieceReach = baseReach * max(startLaw.scale, endLaw.scale, middleScale)
            guard remainder.isFinite, remainder <= allowance * 0.5, pieceReach * curvature < 1 else {
                return (pieceReach * curvature < 1
                    ? "The requested positional allowance is below the certified Hermite error."
                    : "The section reaches past the path's bend and would overlap itself.", 20)
            }
            // Hermite rows from the piece's ends, the start shared with the previous piece.
            let startFrame = try RotationJet(reference: frameReference, tangent: try bezier.pointJet(at: .start, order: 2).unitTangentJet())
            let endFrame = try RotationJet(reference: frameReference, tangent: try bezier.pointJet(at: .end, order: 2).unitTangentJet())
            guard let startFrame, let endFrame,
                  let startPath = try bezier.pointJet(at: .start, order: 2).position,
                  let endPath = try bezier.pointJet(at: .end, order: 2).position else {
                throw Self.failure(.invalidInput, "The sweep piece's ends are not certified.", featureID, tolerance)
            }
            var pieceRows: [[Point3D]] = Array(repeating: [], count: 4)
            var numeric = 0.0
            var nextStation: [[Interval]] = []
            let startLaws = try laws(startLaw, endLaw, at: .start, order: 1)
            let endLaws = try laws(startLaw, endLaw, at: .end, order: 1)
            for (index, point) in coordinates.enumerated() {
                let atStart = moved(point, path: startPath, frame: startFrame,
                                    cosine: startLaws.cosine, sine: startLaws.sine, scale: startLaws.scale)
                let atEnd = moved(point, path: endPath, frame: endFrame,
                                  cosine: endLaws.cosine, sine: endLaws.sine, scale: endLaws.scale)
                let s0 = stationValues?[index] ?? atStart.derivative(0)
                let s1 = atEnd.derivative(0)
                let enclosures = [
                    s0,
                    zip(atStart.derivative(0), atStart.derivative(1)).map { $0 + $1 * third },
                    zip(s1, atEnd.derivative(1)).map { $0 - $1 * third },
                    s1,
                ]
                for (row, enclosure) in enclosures.enumerated() {
                    let chosen = enclosure.map(\.midpoint)
                    numeric = max(numeric, zip(enclosure, chosen).reduce(Interval.exact(0)) {
                        $0 + .exact(($1.0 - .exact($1.1)).absoluteUpperBound)
                    }.upper)
                    pieceRows[row].append(Point3D(x: chosen[0], y: chosen[1], z: chosen[2]))
                }
                // The end's enclosure starts the next piece, so its rounding counts there too.
                nextStation.append(s1)
            }
            let error = (Interval.exact(numeric) + .exact(remainder)).upper
            guard error.isFinite, error <= allowance, numeric <= tolerance.distance * 0.125 else {
                throw Self.failure(.sweepPathNormalUnavailable,
                    "The requested positional allowance is below the certified coefficient error.", featureID, tolerance)
            }
            maximumError = max(maximumError, error)
            stationValues = nextStation
            if let guideEndState {
                guideState = guideEndState
                guideStart = endLaw
            }
            largestScale = max(largestScale, startLaw.scale, endLaw.scale, middleScale)
            smallestScale = min(smallestScale, startLaw.scale, endLaw.scale, guideEndState == nil ? 1 : middleScale)
            chunkStarted = false
            rows.append(pieceRows)
            let middle = try bezier.halves().1.pointJet(at: .start, order: 1)
            guard let middlePoint = middle.position?.derivative(0), let middleTangent = try middle.tangent() else {
                throw Self.failure(.invalidInput, "The sweep piece's middle is not certified.", featureID, tolerance)
            }
            // Eighths of the piece bound where its sections can be, finely enough that a nearby
            // piece's distance and tilt are read at the same place.
            var parts = [bezier]
            for _ in 0..<3 { parts = parts.flatMap { part -> [HomogeneousBezier] in let halves = part.halves(); return [halves.0, halves.1] } }
            let bounds = try parts.map { part -> PartBounds in
                let jet = try part.jet(over: .whole, order: 1)
                guard let position = jet.position, let direction = jet.unitTangent(),
                      let partFrame = try RotationJet(reference: frameReference,
                          tangent: .constant(direction.derivative(0), order: 0)) else {
                    throw Self.failure(.sweepPathNormalUnavailable, "The sweep path's frame is not certified along a piece.", featureID, tolerance)
                }
                return PartBounds(
                    box: position.derivative(0), tangent: direction.derivative(0),
                    first: partFrame.rotated(carried[1]).derivative(0),
                    second: partFrame.rotated(carried[2]).derivative(0)
                )
            }
            pieces.append(AcceptedPiece(
                box: path.derivative(0), parts: bounds,
                middle: Point3D(x: middlePoint[0].midpoint, y: middlePoint[1].midpoint, z: middlePoint[2].midpoint),
                middleTangent: middleTangent
            ))
            // The section's normal turns with the twist like a section point without its scale.
            endNormalEnclosure = moved(normalCoordinates, path: .constant([.exact(0), .exact(0), .exact(0)], order: 1),
                frame: endFrame, cosine: endLaws.cosine, sine: endLaws.sine, scale: .constant(.exact(1), order: 1)).derivative(0)
            // Where the section's first lateral axis has come to, turned by the twist.
            let endFirst = endFrame.rotated(carried[1]).derivative(0), endSecond = endFrame.rotated(carried[2]).derivative(0)
            let turn = endLaw.angle
            endLateral = Vector3D(x: endFirst[0].midpoint, y: endFirst[1].midpoint, z: endFirst[2].midpoint) * cos(turn)
                + Vector3D(x: endSecond[0].midpoint, y: endSecond[1].midpoint, z: endSecond[2].midpoint) * sin(turn)
            return nil
        }

        // Pieces halved where refused, worked through in order on a stack rather than by recursion
        // (deep halving would otherwise outgrow a worker's stack).
        for (span, bezier) in beziers.enumerated() {
            var pending: [(piece: HomogeneousBezier, lower: Double, upper: Double, depth: Int)] = [(bezier, 0, 1, 0)]
            while let next = pending.popLast() {
                guard let refusal = try accept(next.piece, span: span, lower: next.lower, upper: next.upper) else { continue }
                guard next.depth < refusal.limit else {
                    throw Self.failure(.sweepPathNormalUnavailable, refusal.reason, featureID, tolerance)
                }
                let (left, right) = next.piece.halves()
                let middle = 0.5 * (next.lower + next.upper)
                pending.append((right, middle, next.upper, next.depth + 1))
                pending.append((left, next.lower, middle, next.depth + 1))
            }
        }
        let scaleRange = Interval(lower: smallestScale.nextDown, upper: largestScale.nextUp)
        let sectionExtent = SectionExtent(
            along: extent(startTangent) * scaleRange,
            first: (twists ? turned : extent(lateral.0)) * scaleRange,
            second: (twists ? turned : extent(lateral.1)) * scaleRange
        )
        try Self.certifyApart(pieces, reach: baseReach * scaleRange.upper, extent: sectionExtent, closed: pathIsClosed,
                              featureID: featureID, tolerance: tolerance)
        // The turn the section comes back with where a closed path closes.
        let turnAxis = startTangent.cross(lateral.0)
        let closingTurn = pathIsClosed ? atan2(endLateral.dot(turnAxis), endLateral.dot(lateral.0)) : 0
        var seamClosed = false
        if pathIsClosed, closesSeam, let last = rows.indices.last {
            // The last row is the first, the gap between them counted in the error — when the
            // section has come back close enough; otherwise the seam stays open for the caller to
            // turn the section by the twist law and plan again.
            let gap = zip(rows[last][3], rows[0][0]).map { ($0.0 - $0.1).length }.max() ?? 0
            if gap + maximumError <= allowance {
                rows[last][3] = rows[0][0]
                maximumError += gap
                seamClosed = true
            }
        }

        // Surfaces: every section span of every loop, row by row.
        var built: [[[BSplineSurface3D]]] = sectionLoops.map { _ in [] }
        for pieceRows in rows {
            var offset = 0
            for (loopIndex, loop) in sectionLoops.enumerated() {
                var row: [BSplineSurface3D] = []
                for span in loop {
                    let count = span.curve.controlPointCount
                    let controls = pieceRows.map { Array($0[offset..<(offset + count)]) }
                    offset += count
                    let surface = BSplineSurface3D(
                        uDegree: span.curve.degree, vDegree: 3,
                        uKnots: span.curve.knots, vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                        controlPoints: controls, weights: Array(repeating: span.curve.weights, count: 4)
                    )
                    try surface.validate(tolerance: tolerance)
                    row.append(surface)
                }
                built[loopIndex].append(row)
            }
        }
        profileSpanLoops = sectionLoops
        self.sectionIsClosed = sectionIsClosed
        self.profilePlane = profilePlane
        surfaces = built
        pieceCount = rows.count
        startNormal = normal
        endNormal = try Vector3D(x: endNormalEnclosure[0].midpoint, y: endNormalEnclosure[1].midpoint, z: endNormalEnclosure[2].midpoint)
            .normalized(tolerance: tolerance.distance)
        advanceSign = advance > 0 ? 1 : -1
        positionErrorUpperBound = maximumError
        self.pathIsClosed = pathIsClosed
        self.closingTurn = closingTurn
        self.seamClosed = seamClosed
    }

    /// The plan for a closed path: measured once, then again with a twist law taking out the turn
    /// the frame comes back with (it depends a little on where the pieces fall, so a few rounds
    /// settle it), its last row then made the first. Twist, scale and guides take no part.
    package static func closed(
        section: ResolvedModelingSection,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws -> Self {
        guard values.twistAngle == 0, values.twistAngles.allSatisfy({ $0 == 0 }), values.endScale == 1, sweep.guides.isEmpty,
              values.approximationTolerance != nil else {
            throw failure(.sweepTwistUnavailable,
                "A sweep along a closed curved path takes no twist, scale or guides, and needs an allowance.", featureID, tolerance)
        }
        var correction = 0.0
        for _ in 0..<6 {
            var corrected = values
            corrected.twistAngles = correction == 0 ? [] : [0, correction]
            corrected.twistPositions = [0, 1]
            let plan = try Self(section: section, pathSpans: pathSpans, sweep: sweep, values: corrected,
                                pathIsClosed: true, closesSeam: true, featureID: featureID, tolerance: tolerance)
            if plan.seamClosed { return plan }
            correction -= plan.closingTurn
        }
        throw failure(.sweepPathNormalUnavailable,
            "A closed sweep's frame does not settle on coming back to its start.", featureID, tolerance)
    }

    /// Proves that no two path pieces that do not touch carry overlapping sections: they are
    /// farther apart than twice the section's reach, or the plane across the path in the middle
    /// of a piece between them has one wholly behind it and the other wholly ahead.
    private static func certifyApart(
        _ pieces: [AcceptedPiece], reach: Double, extent: SectionExtent, closed: Bool,
        featureID: FeatureID?, tolerance: ModelingTolerance
    ) throws {
        guard pieces.count >= 3 else { return }
        /// The signed distances from `plane` of the sections of every part of `piece`.
        func side(_ piece: AcceptedPiece, of plane: (Point3D, Vector3D)) -> (lower: Double, upper: Double) {
            let origin = values(plane.0)
            let normal = values(plane.1)
            var lower = Double.infinity, upper = -Double.infinity
            func along(_ axis: [Interval]) -> Interval { (0..<3).reduce(Interval.exact(0)) { $0 + axis[$1] * normal[$1] } }
            for part in piece.parts {
                // A section point is the path point plus its offsets along the tangent and the
                // two lateral axes, each within the section's extent.
                let distance = (0..<3).reduce(Interval.exact(0)) { $0 + (part.box[$1] - origin[$1]) * normal[$1] }
                let reach = distance + along(part.tangent) * extent.along + along(part.first) * extent.first
                    + along(part.second) * extent.second
                lower = min(lower, reach.lower)
                upper = max(upper, reach.upper)
            }
            return (lower, upper)
        }
        for first in pieces.indices {
            for second in stride(from: first + 2, to: pieces.count, by: 1) {
                // Round a closed path the first and the last touch at its start.
                if closed, first == 0, second == pieces.count - 1 { continue }
                let a = pieces[first], b = pieces[second]
                let gap = (0..<3).map { axis -> Double in
                    max(0, b.box[axis].lower - a.box[axis].upper, a.box[axis].lower - b.box[axis].upper)
                }
                if (gap.reduce(0) { $0 + $1 * $1 }).squareRoot() > 2 * reach + tolerance.distance { continue }
                // Round a closed path the pieces between may lie either way.
                let betweens = closed ? [first + 1, second - 1, (second + 1) % pieces.count, (first + pieces.count - 1) % pieces.count]
                    : [first + 1, second - 1]
                let separated = betweens.contains { between in
                    let plane = (pieces[between].middle, pieces[between].middleTangent)
                    let behind = side(a, of: plane), ahead = side(b, of: plane)
                    return (behind.upper < 0 && ahead.lower > 0) || (ahead.upper < 0 && behind.lower > 0)
                }
                guard separated else {
                    throw failure(.sweepPathNormalUnavailable,
                        "The path returns too close to itself for this section: the sweep may overlap itself.", featureID, tolerance)
                }
            }
        }
    }

    /// A section point's offsets from the path start along the start tangent and the two lateral
    /// axes.
    private struct SectionCoordinates {
        let along: Interval
        let first: Interval
        let second: Interval
    }

    /// The section's offsets from the path start along the start tangent and two lateral axes.
    private struct SectionExtent {
        let along: Interval
        let first: Interval
        let second: Interval
    }

    /// Where a part of a piece and its frame can be.
    private struct PartBounds {
        let box: [Interval]
        let tangent: [Interval]
        let first: [Interval]
        let second: [Interval]
    }

    /// Two unit axes across `tangent`, completing a right-handed frame.
    private static func lateralAxes(of tangent: Vector3D, tolerance: ModelingTolerance) throws -> (Vector3D, Vector3D) {
        let seed: Vector3D = abs(tangent.x) < 0.6 ? .unitX : .unitY
        let first = try tangent.cross(seed).normalized(tolerance: tolerance.distance)
        return (first, tangent.cross(first))
    }

    private struct AcceptedPiece {
        let box: [Interval]
        let parts: [PartBounds]
        let middle: Point3D
        let middleTangent: Vector3D
    }

    fileprivate static func values(_ point: Point3D) -> [Interval] { [.exact(point.x), .exact(point.y), .exact(point.z)] }
    fileprivate static func values(_ vector: Vector3D) -> [Interval] { [.exact(vector.x), .exact(vector.y), .exact(vector.z)] }

    /// A refusal of what the sweep asks for, reported as capability planning reports it.
    package static func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID?, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }

    private static func exhausted(_ featureID: FeatureID?, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, featureID: featureID, tolerance: tolerance,
            message: "A curved sweep exceeds 4096 patches or 262144 tensor controls.")
    }
}

/// A rational Bezier path piece in homogeneous coordinates `(w·x, w·y, w·z, w)`, each an interval
/// so subdivision stays an enclosure.
private struct HomogeneousBezier {
    typealias Interval = OutwardScalarInterval
    enum Place { case whole, start, end }

    let coefficients: [[Interval]]
    var degree: Int { coefficients.count - 1 }

    init(coefficients: [[Interval]]) {
        self.coefficients = coefficients
    }

    init(span: ExactBSplineCurveSpan) throws {
        let curve = span.curve
        coefficients = zip(curve.controlPoints, curve.weights).map { point, weight in
            [Interval.exact(point.x) * .exact(weight), .exact(point.y) * .exact(weight), .exact(point.z) * .exact(weight), .exact(weight)]
        }
    }

    /// The two halves, by de Casteljau at one half.
    func halves() -> (HomogeneousBezier, HomogeneousBezier) {
        var level = coefficients
        var left = [level[0]]
        var right = [level[level.count - 1]]
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                zip(level[index], level[index + 1]).map { ($0 + $1) * .exact(0.5) }
            }
            left.append(level[0])
            right.append(level[level.count - 1])
        }
        return (HomogeneousBezier(coefficients: left), HomogeneousBezier(coefficients: right.reversed()))
    }

    /// Enclosures of the homogeneous derivatives through `order` over the piece or at an end,
    /// in the piece's own parameter.
    func jet(over place: Place, order: Int) throws -> PathJet {
        var differences = coefficients
        var factor = Interval.exact(1)
        var derivatives: [[Interval]] = []
        for k in 0...order {
            if k > 0 {
                guard differences.count > 1 else {
                    derivatives.append(Array(repeating: .exact(0), count: 4))
                    continue
                }
                factor = factor * .exact(Double(degree - k + 1))
                differences = (0..<(differences.count - 1)).map { index in
                    zip(differences[index + 1], differences[index]).map { $0 - $1 }
                }
            }
            let chosen: [[Interval]]
            switch place {
            case .whole: chosen = differences
            case .start: chosen = [differences[0]]
            case .end: chosen = [differences[differences.count - 1]]
            }
            derivatives.append((0..<4).map { component in
                OutwardScalarInterval.enclosing(chosen.map { $0[component] }) * factor
            })
        }
        return PathJet(homogeneous: derivatives)
    }

    func pointJet(at place: Place, order: Int) throws -> PathJet {
        try jet(over: place, order: order)
    }
}

/// The path's position (and so its tangent) from homogeneous derivative enclosures.
private struct PathJet {
    let homogeneous: [[OutwardScalarInterval]]

    var position: IntervalVectorDerivativeJet? {
        let weight = IntervalDerivativeJet(derivatives: homogeneous.map { $0[3] })
        guard let inverse = weight.reciprocal() else { return nil }
        let components = (0..<3).map { component in
            IntervalDerivativeJet(derivatives: homogeneous.map { $0[component] }) * inverse
        }
        return IntervalVectorDerivativeJet(x: components[0], y: components[1], z: components[2])
    }

    /// The unit tangent's jet, one order below the position's.
    func unitTangent() -> IntervalVectorDerivativeJet? {
        guard let velocity = position?.differentiated(), let speed = velocity.dot(velocity).squareRoot(),
              let inverse = speed.reciprocal() else { return nil }
        return velocity.scaled(by: inverse)
    }

    func unitTangentJet() throws -> IntervalVectorDerivativeJet {
        guard let tangent = unitTangent() else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: .standard,
                message: "The sweep path's speed vanishes at a piece end.")
        }
        return tangent
    }

    /// The unit tangent's midpoint, for a frame reference.
    func tangent() throws -> Vector3D? {
        guard let tangent = unitTangent() else { return nil }
        let value = tangent.derivative(0)
        let vector = Vector3D(x: value[0].midpoint, y: value[1].midpoint, z: value[2].midpoint)
        guard vector.length > 0.5 else { return nil }
        return vector * (1 / vector.length)
    }
}

/// The least rotation taking a fixed unit `reference` to the moving unit `tangent`:
/// `R v = (r·t) v + (r×t)×v + (r×t) ((r×t)·v) / (1 + r·t)`.
private struct RotationJet {
    let tangent: IntervalVectorDerivativeJet
    let cross: IntervalVectorDerivativeJet
    let cosine: IntervalDerivativeJet
    let inverse: IntervalDerivativeJet
    /// `1 + r·t`, how far the tangent is from turning back on the reference.
    let clearance: OutwardScalarInterval

    init?(reference: Vector3D, tangent: IntervalVectorDerivativeJet) throws {
        let order = tangent.x.order
        let fixed = IntervalVectorDerivativeJet.constant(
            [.exact(reference.x), .exact(reference.y), .exact(reference.z)], order: order
        )
        cross = fixed.cross(tangent)
        cosine = fixed.dot(tangent)
        let one = IntervalDerivativeJet.constant(.exact(1), order: order)
        let sum = one + cosine
        guard sum.value.lower > 0, let inverse = sum.reciprocal() else { return nil }
        self.tangent = tangent
        self.inverse = inverse
        clearance = sum.value
    }

    func rotated(_ vector: [OutwardScalarInterval]) -> IntervalVectorDerivativeJet {
        let order = cosine.order
        let fixed = IntervalVectorDerivativeJet.constant(vector, order: order)
        return fixed.scaled(by: cosine) + cross.cross(fixed) + cross.scaled(by: cross.dot(fixed) * inverse)
    }
}
