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
    package let terminalSectionCollapsed: Bool
    private let originalSeam: ClosedSweepSectionCorrespondence?
    private let seamTransport: ClosedSweepSectionCorrespondence.RowTransport?

    /// Whether a sweep takes this plan: path-normal alignment along a path that is neither
    /// straight nor a circular arc the exact circular sweep already builds as a solid.
    package static func applies(
        _ options: SweepOptions,
        pathSpans: [ExactBSplineCurveSpan],
        exactCircularSolid: Bool,
        tolerance: ModelingTolerance,
        sourceBudget: CurvedSweepSourceBudget? = nil
    ) throws -> Bool {
        guard options.alignment == .normal, exactCircularSolid == false else { return false }
        let admission = try sourceBudget?.conversionAdmission()
        return try !OriginalSweepPathLinearity(tolerance: tolerance, admission: admission).isStraight(pathSpans)
    }

    /// The plan for a resolved section: a profile's loops, or a curve as one open or closed loop.
    package init(
        section: ResolvedModelingSection,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        guide: [BSplineCurve3D]? = nil,
        secondGuide: [BSplineCurve3D]? = nil,
        pathIsClosed: Bool = false,
        closesSeam: Bool = false,
        authoredSeam: ClosedSweepSectionCorrespondence? = nil,
        sourceBudget: CurvedSweepSourceBudget? = nil,
        originalLengthLaw: OriginalCurvedSweepArcLengthLaw? = nil,
        originalPathPieces: [OriginalSweepPathPiece]? = nil,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws {
        let invocation = try sourceBudget ?? CurvedSweepSourceBudget(tolerance: tolerance)
        let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: invocation.conversionAdmission())
        switch section {
        case .profile, .face, .constructedRegion:
            try self.init(sectionLoops: try spans.loopSpans(from: section), sectionIsClosed: true,
                profilePlane: try section.plane(), pathSpans: pathSpans, sweep: sweep, values: values, guide: guide, secondGuide: secondGuide,
                pathIsClosed: pathIsClosed, closesSeam: closesSeam, authoredSeam: authoredSeam, sourceBudget: invocation,
                originalLengthLaw: originalLengthLaw,
                originalPathPieces: originalPathPieces,
                featureID: featureID, tolerance: tolerance)
        case .curve(let curve):
            try self.init(sectionLoops: [try spans.sectionSpans(from: curve)], sectionIsClosed: curve.isClosed,
                profilePlane: try section.plane(), pathSpans: pathSpans, sweep: sweep, values: values, guide: guide, secondGuide: secondGuide,
                pathIsClosed: pathIsClosed, closesSeam: closesSeam, authoredSeam: authoredSeam, sourceBudget: invocation,
                originalLengthLaw: originalLengthLaw,
                originalPathPieces: originalPathPieces,
                featureID: featureID, tolerance: tolerance)
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
        secondGuide secondGuideSpans: [BSplineCurve3D]? = nil,
        pathIsClosed: Bool = false,
        closesSeam: Bool = false,
        authoredSeam: ClosedSweepSectionCorrespondence? = nil,
        sourceBudget: CurvedSweepSourceBudget? = nil,
        originalLengthLaw: OriginalCurvedSweepArcLengthLaw? = nil,
        originalPathPieces: [OriginalSweepPathPiece]? = nil,
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
              twistPositions.first == 0, twistPositions.last == 1,
              twistPositions.allSatisfy({ $0.isFinite }),
              zip(twistPositions, twistPositions.dropFirst()).allSatisfy({ $0 < $1 }),
              twistAngles.allSatisfy({ $0.isFinite && abs($0) <= 16 }), values.endScale.isFinite, values.endScale >= 0 else {
            throw Self.failure(.sweepTwistUnavailable,
                "A curved sweep's twist law is finite within 16 radians and its end scale nonnegative with an explicit terminal collapse.", featureID, tolerance)
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
        // One guide steers the section by its method in the moving frame (CurvedSweepGuideLaw); two
        // Point guides deform it, at every station, by the linear map of the plane across the path
        // taking its two contacts to where the guides cross that plane (Sweep2's rule).
        let twoGuides = sweep.guides.count == 2 && guideSpans?.isEmpty == false && secondGuideSpans?.isEmpty == false
        guard guided == false || (sweep.guides.count == 1 && guideSpans?.isEmpty == false)
                || (twoGuides && sweep.options.guideMethod == .point) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): two Chord or Curve guides, or three or more guides,
            // along a curved path have no single rule for the section between them, so they are
            // refused. Production path: CertifiedCurvedPathSweepPlan for every guided curved
            // Sweep. Complete only when such guides steer a curved sweep, verified by its sections
            // meeting every guide.
            throw Self.failure(.sweepGuideConstraintUnavailable,
                "A curved path-normal sweep takes one guide, or two Point guides.", featureID, tolerance)
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

        let lawful = (twists || scales) && guided == false
        let invocation = try sourceBudget ?? CurvedSweepSourceBudget(tolerance: tolerance)
        let beziers = try originalPathPieces ?? OriginalSweepPathPiece.prepare(pathSpans,
            tolerance: tolerance, budget: invocation)
        guard beziers.count == pathSpans.count else {
            throw Self.failure(.invalidInput, "Retained original path pieces must cover every source span.", featureID, tolerance)
        }
        for index in pathSpans.indices {
            guard try beziers[index].belongs(to: pathSpans[index], tolerance: tolerance, budget: invocation) else {
                throw Self.failure(.invalidInput, "A retained original path piece belongs to another source or invocation.", featureID, tolerance)
            }
        }
        let lengthLaw = lawful ? try originalLengthLaw ?? OriginalCurvedSweepArcLengthLaw(
            spans: pathSpans, tolerance: tolerance, budget: invocation) : nil
        var stationFractions: [Int: [Double: Interval]] = [:]
        func fractionEnclosure(span: Int, at parameter: Double) throws -> Interval {
            guard let lengthLaw else { return .exact(0) }
            if let retained = stationFractions[span]?[parameter] { return retained }
            let enclosed = try lengthLaw.fraction(span: span, at: parameter)
            try invocation.retainScalars(3)
            stationFractions[span, default: [:]][parameter] = enclosed
            return enclosed
        }
        func fraction(span: Int, at parameter: Double) throws -> Double {
            try fractionEnclosure(span: span, at: parameter).midpoint
        }
        func originalTwist(at fraction: Double) throws -> Interval {
            try invocation.consume(depth: 0)
            if fraction <= 0 { return .exact(twistAngles[0]) }
            if fraction >= 1 { return .exact(twistAngles[twistAngles.count - 1]) }
            guard let upper = twistPositions.firstIndex(where: { $0 >= fraction }), upper > 0,
                  let ratio = (Interval.exact(fraction) - .exact(twistPositions[upper - 1]))
                    .divided(by: .exact(twistPositions[upper]) - .exact(twistPositions[upper - 1])) else {
                throw Self.failure(.sweepTwistUnavailable, "The original twist knot interval has no finite ratio.", featureID, tolerance)
            }
            return .exact(twistAngles[upper - 1])
                + (.exact(twistAngles[upper]) - .exact(twistAngles[upper - 1])) * ratio
        }
        var maximumTwistSlope = 0.0
        if lawful {
            for index in 1..<twistPositions.count {
                try invocation.consume(depth: 0)
                guard let slope = (Interval.exact(twistAngles[index]) - .exact(twistAngles[index - 1]))
                    .divided(by: .exact(twistPositions[index]) - .exact(twistPositions[index - 1])),
                      slope.absoluteUpperBound.isFinite else {
                    throw Self.exhausted(featureID, tolerance)
                }
                maximumTwistSlope = max(maximumTwistSlope, slope.absoluteUpperBound)
            }
        }
        let joinSine = try CertifiedRotationTrigonometry.evaluate(.exact(tolerance.angle),
            tolerance: tolerance, consumeWork: { try invocation.consume(depth: 0) }).sine
        func requireSmoothJoin(_ before: PathJet, _ after: PathJet, message: String) throws {
            try invocation.consume(depth: 0)
            guard let a = before.unitTangent()?.derivative(0),
                  let b = after.unitTangent()?.derivative(0) else {
                throw Self.failure(.singularGeometry, "An original path join has no certified nonzero tangent.", featureID, tolerance)
            }
            let cross = IntervalVector3DBounds(x: a[1] * b[2] - a[2] * b[1],
                y: a[2] * b[0] - a[0] * b[2], z: a[0] * b[1] - a[1] * b[0])
            let dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
            if cross.lengthUpperBound <= joinSine.lower, dot.lower > 0 { return }
            if cross.lengthLowerBound > joinSine.upper || dot.upper <= 0 {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public curved Sweep/Pipe
                // need original Mitre and Round corner construction before this
                // proven one-sided tangent discontinuity can be published.
                throw Self.failure(.sweepRoundCornerUnavailable, message, featureID, tolerance)
            }
            throw Self.failure(.resourceLimitExceeded,
                "Original one-sided tangent bounds cannot certify this path join at the requested angle tolerance.", featureID, tolerance)
        }
        // Tangent continuity along the path: a corner needs a mitre or a round.
        for index in beziers.indices.dropFirst() {
            try requireSmoothJoin(beziers[index - 1].pointJet(at: .end, order: 1),
                beziers[index].pointJet(at: .start, order: 1),
                message: "A curved path-normal sweep needs a path without corners.")
        }
        if pathIsClosed {
            // A closed path closes smoothly, its end leaving the way its start does.
            try requireSmoothJoin(beziers[beziers.count - 1].pointJet(at: .end, order: 1),
                beziers[0].pointJet(at: .start, order: 1),
                message: "A closed curved path sweeps only where it closes smoothly.")
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
        // Two guides deform the section within its own plane, which must lie across the path.
        guard twoGuides == false || abs(advance) >= cos(tolerance.angle) else {
            throw Self.failure(.sweepGuideConstraintUnavailable,
                "Two guides sweep a section lying square to the path at its start.", featureID, tolerance)
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
        let certifiedReach = coordinates.map { point in
            (Interval.exact(point.along.absoluteUpperBound)
                + .exact(point.first.absoluteUpperBound)
                + .exact(point.second.absoluteUpperBound)).upper
        }.max() ?? 0
        let normalCoordinates = SectionCoordinates(along: .exact(normal.dot(startTangent)),
            first: .exact(normal.dot(lateral.0)), second: .exact(normal.dot(lateral.1)))
        let guideLaw = try guideSpans.map { spans in
            try CurvedSweepGuideLaw(method: sweep.options.guideMethod, guide: spans,
                                    section: sectionLoops.flatMap { $0.map(\.curve) }, pathStart: pathStart,
                                    startTangent: startTangent, startAxes: (lateral.0, lateral.1), featureID: featureID, tolerance: tolerance)
        }
        let secondLaw = try secondGuideSpans.map { spans in
            try CurvedSweepGuideLaw(method: .point, guide: spans,
                                    section: sectionLoops.flatMap { $0.map(\.curve) }, pathStart: pathStart,
                                    startTangent: startTangent, startAxes: (lateral.0, lateral.1), featureID: featureID, tolerance: tolerance)
        }
        // The two contacts' lateral offsets at the start, whose inverse the linear maps share.
        let contacts = guideLaw.flatMap { first in secondLaw.map { (first.start, $0.start) } }
        let contactDeterminant = contacts.map { $0.0.first * $0.1.second - $0.1.first * $0.0.second } ?? 0
        if let contacts {
            let reach = max(hypot(contacts.0.first, contacts.0.second), hypot(contacts.1.first, contacts.1.second))
            guard abs(contactDeterminant) > tolerance.distance * reach else {
                throw Self.failure(.sweepGuideConstraintUnavailable,
                    "Two guides meet the section on one line through the path, which leaves its turn open.", featureID, tolerance)
            }
        }
        /// The linear map of the plane across the path taking the contacts to the guides' crossings.
        func linearMap(_ g1: (first: Double, second: Double), _ g2: (first: Double, second: Double)) -> LinearMap {
            guard let contacts else { return .identity }
            let (s1, s2) = contacts
            let inverse = 1 / contactDeterminant
            return LinearMap(a: (g1.first * s2.second - g2.first * s1.second) * inverse,
                             b: (g2.first * s1.first - g1.first * s2.first) * inverse,
                             c: (g1.second * s2.second - g2.second * s1.second) * inverse,
                             d: (g2.second * s1.first - g1.second * s2.first) * inverse)
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
        func laws(_ start: (angle: Double, scale: Double), _ end: (angle: Double, scale: Double), at place: OriginalSweepPathPiece.Place, order: Int)
            throws -> (cosine: IntervalDerivativeJet, sine: IntervalDerivativeJet, scale: IntervalDerivativeJet) {
            let rate = Interval.exact(end.angle) - .exact(start.angle)
            let range: Interval
            switch place {
            case .whole: range = Interval(lower: min(start.angle, end.angle), upper: max(start.angle, end.angle))
            case .start: range = .exact(start.angle)
            case .end: range = .exact(end.angle)
            }
            let trig = try CertifiedRotationTrigonometry.evaluate(range, tolerance: tolerance,
                consumeWork: { try invocation.consume(depth: 0) })
            let count = order.addingReportingOverflow(1)
            let bytes = count.partialValue.multipliedReportingOverflow(by: 3 * MemoryLayout<Interval>.stride)
            guard order >= 0, !count.overflow, !bytes.overflow else {
                throw Self.exhausted(featureID, tolerance)
            }
            try invocation.retainBytes(bytes.partialValue)
            // The k-th derivative of cos(θ0 + δτ) is δᵏ cos(θ + kπ/2), and likewise for the sine.
            var cosine: [Interval] = [], sine: [Interval] = []
            cosine.reserveCapacity(count.partialValue); sine.reserveCapacity(count.partialValue)
            var power = Interval.exact(1)
            for k in 0...order {
                try invocation.consume(depth: 0)
                let c: Interval, s: Interval
                switch k % 4 {
                case 0: c = trig.cosine; s = trig.sine
                case 1: c = -trig.sine; s = trig.cosine
                case 2: c = -trig.cosine; s = -trig.sine
                default: c = trig.sine; s = -trig.cosine
                }
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
            var scaleFields: [Interval] = []; scaleFields.reserveCapacity(count.partialValue)
            for k in 0...order {
                try invocation.consume(depth: 0)
                scaleFields.append(k == 0 ? scaleValue : k == 1 ? growth : .exact(0))
            }
            return (IntervalDerivativeJet(derivatives: cosine), IntervalDerivativeJet(derivatives: sine),
                    IntervalDerivativeJet(derivatives: scaleFields))
        }

        /// A section point moved by the frame and deformed by the linear map's entries.
        func movedLinear(_ point: SectionCoordinates, path: IntervalVectorDerivativeJet, frame: RotationJet,
                         map: (a: IntervalDerivativeJet, b: IntervalDerivativeJet, c: IntervalDerivativeJet, d: IntervalDerivativeJet))
            -> IntervalVectorDerivativeJet {
            let order = map.a.order
            let first = frame.rotated(carried[1]), second = frame.rotated(carried[2])
            let x = map.a.scaled(by: point.first) + map.b.scaled(by: point.second)
            let y = map.c.scaled(by: point.first) + map.d.scaled(by: point.second)
            return path + frame.tangent.scaled(by: .constant(point.along, order: order)) + first.scaled(by: x) + second.scaled(by: y)
        }
        /// The linear map's entries over a piece (or at an end), linear in its parameter.
        func mapJets(_ start: LinearMap, _ end: LinearMap, at place: HomogeneousBezier.Place, order: Int)
            -> (a: IntervalDerivativeJet, b: IntervalDerivativeJet, c: IntervalDerivativeJet, d: IntervalDerivativeJet) {
            func jet(_ s: Double, _ e: Double) -> IntervalDerivativeJet {
                let value: Interval
                switch place {
                case .whole: value = Interval(lower: min(s, e).nextDown, upper: max(s, e).nextUp)
                case .start: value = .exact(s)
                case .end: value = .exact(e)
                }
                return IntervalDerivativeJet(derivatives: Array(([value, .exact(e) - .exact(s)]
                    + Array(repeating: .exact(0), count: max(0, order - 1))).prefix(order + 1)))
            }
            return (jet(start.a, end.a), jet(start.b, end.b), jet(start.c, end.c), jet(start.d, end.d))
        }

        var frameReference = startTangent
        var chunkStarted = true
        // The second guide's state and the linear map where the last accepted piece ended.
        var secondState: CurvedSweepGuideLaw.State?
        var mapStart = LinearMap.identity
        // The guide's state and law where the last accepted piece ended.
        var guideState: CurvedSweepGuideLaw.State?
        var guideStart = (angle: 0.0, scale: 1.0)
        var stationValues: [[Interval]]?
        var rows: [[[Point3D]]] = []   // piece, row (4), section control point
        var pieces: [AcceptedPiece] = []
        var maximumError = 0.0
        var endNormalEnclosure: [Interval] = Self.values(normal)
        var endLateral = lateral.0
        var startSectionAction: ClosedSweepIntervalFrameAction?
        var endSectionAction: ClosedSweepIntervalFrameAction?
        let sectionAdmission = try invocation.conversionAdmission()
        let third = Interval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)

        /// Accepts the piece, or says why it must be halved and how deep halving may go.
        func accept(_ bezier: OriginalSweepPathPiece, span: Int, lower: Double, upper: Double,
            depth: Int) throws -> (reason: String, limit: Int)? {
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
            var secondEndState: CurvedSweepGuideLaw.State?
            var mapEnd: LinearMap?
            // FIXME(INCOMPLETE_IMPLEMENTATION): this public curved-guide path constructs
            // an interpolated station law. Midpoint deviation is a candidate refinement
            // signal, not a whole original-guide contact certificate. Full S4 requires
            // retained implicit guide/normal-plane enclosures and multiple-guide deformation
            // before this domain may be reported as complete.
            if let guideLaw, let secondLaw {
                func station(_ jet: PathJet) throws -> (Point3D, Vector3D, (first: Vector3D, second: Vector3D))? {
                    guard let position = jet.position?.derivative(0), let direction = try jet.tangent(),
                          let stationFrame = try RotationJet(reference: frameReference, tangent: .constant(Self.values(direction), order: 0)) else { return nil }
                    let first = stationFrame.rotated(carried[1]).derivative(0), second = stationFrame.rotated(carried[2]).derivative(0)
                    func point(_ v: [Interval]) -> Vector3D { Vector3D(x: v[0].midpoint, y: v[1].midpoint, z: v[2].midpoint) }
                    return (Point3D(x: position[0].midpoint, y: position[1].midpoint, z: position[2].midpoint), direction,
                            (try point(first).normalized(tolerance: tolerance.distance), try point(second).normalized(tolerance: tolerance.distance)))
                }
                guard let endStation = try station(try bezier.pointJet(at: .end, order: 1)),
                      let middleStation = try station(try bezier.halves().1.pointJet(at: .start, order: 1)) else {
                    return ("The sweep frame is not certified at a guide station.", 20)
                }
                func onward(_ state: CurvedSweepGuideLaw.State, _ at: (span: Int, parameter: Double)) -> CurvedSweepGuideLaw.State {
                    CurvedSweepGuideLaw.State(span: at.span, parameter: at.parameter, contact: state.contact, angle: state.angle)
                }
                let (begin1, begin2) = (guideState ?? guideLaw.initial, secondState ?? secondLaw.initial)
                let middle1 = try guideLaw.crossing(at: middleStation.0, tangent: middleStation.1, axes: middleStation.2, from: begin1, featureID: featureID)
                let middle2 = try secondLaw.crossing(at: middleStation.0, tangent: middleStation.1, axes: middleStation.2, from: begin2, featureID: featureID)
                let end1 = try guideLaw.crossing(at: endStation.0, tangent: endStation.1, axes: endStation.2,
                                                 from: onward(begin1, middle1.at), featureID: featureID)
                let end2 = try secondLaw.crossing(at: endStation.0, tangent: endStation.1, axes: endStation.2,
                                                  from: onward(begin2, middle2.at), featureID: featureID)
                let (middleMap, endMap) = (linearMap(middle1.offset, middle2.offset), linearMap(end1.offset, end2.offset))
                // The section must not fold: the map's determinant, quadratic along the piece, stays positive.
                let change = LinearMap(a: endMap.a - mapStart.a, b: endMap.b - mapStart.b, c: endMap.c - mapStart.c, d: endMap.d - mapStart.d)
                let linear = mapStart.a * change.d + change.a * mapStart.d - mapStart.b * change.c - change.b * mapStart.c
                var candidates = [0.0, 1.0]
                if change.determinant != 0 { candidates.append(min(1, max(0, -linear / (2 * change.determinant)))) }
                guard middleMap.determinant > 0, candidates.allSatisfy({ mapStart.determinant + linear * $0 + change.determinant * $0 * $0 > tolerance.relative }) else {
                    throw Self.failure(.sweepGuideTransformCollapse, "Two guides fold the section on its way along the path.", featureID, tolerance)
                }
                let stray = baseReach * middleMap.distance(to: mapStart.midway(to: endMap))
                guard stray <= allowance * 0.25 else {
                    if (endStation.0 - (try bezier.pointJet(at: .start, order: 0).position.map { position in
                        Point3D(x: position.derivative(0)[0].midpoint, y: position.derivative(0)[1].midpoint, z: position.derivative(0)[2].midpoint)
                    } ?? endStation.0)).length <= 16 * tolerance.distance {
                        throw Self.failure(.sweepGuideContactUnavailable,
                            "The guides deform the section faster than the allowance follows.", featureID, tolerance)
                    }
                    return ("The guides deform the section faster than the allowance follows.", 40)
                }
                startLaw = (0, 1)
                endLaw = (0, 1)
                middleScale = max(mapStart.norm, middleMap.norm, endMap.norm)
                guideEndState = onward(begin1, end1.at)
                secondEndState = onward(begin2, end2.at)
                mapEnd = endMap
            } else if let guideLaw {
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
            var originalLawError = 0.0
            if let lengthLaw {
                let first = try fractionEnclosure(span: span, at: lower)
                let last = try fractionEnclosure(span: span, at: upper)
                let f0 = first.midpoint, f1 = last.midpoint
                let endpointError = max((first - .exact(f0)).absoluteUpperBound,
                    (last - .exact(f1)).absoluteUpperBound)
                // In this piece's normalized parameter F'' = speed'/L and
                // |speed'| <= |C''|. The linear interpolation remainder is M/8.
                let interpolation = try lengthLaw.fractionInterpolationError(span: span,
                    from: lower, to: upper, depth: depth)
                let fractionError = Interval.exact(endpointError) + interpolation
                var knotError = 0.0
                let stations = [f0, f1] + twistPositions.filter { $0 > min(f0, f1) && $0 < max(f0, f1) }
                for station in stations {
                    let ratio: Interval
                    if f1 != f0 {
                        guard let value = (Interval.exact(station) - .exact(f0))
                            .divided(by: .exact(f1) - .exact(f0)) else {
                            throw Self.exhausted(featureID, tolerance)
                        }
                        ratio = value
                    } else { ratio = .exact(0) }
                    let candidate = Interval.exact(startLaw.angle)
                        + (.exact(endLaw.angle) - .exact(startLaw.angle)) * ratio
                    knotError = max(knotError,
                        (try originalTwist(at: station) - candidate).absoluteUpperBound)
                }
                let angleError = Interval.exact(knotError) + .exact(maximumTwistSlope) * fractionError
                let scaleSlope = Interval.exact(values.endScale) - .exact(1)
                let firstScale = Interval.exact(1) + scaleSlope * .exact(f0)
                let lastScale = Interval.exact(1) + scaleSlope * .exact(f1)
                let scaleError = Interval.exact(max(
                    (firstScale - .exact(startLaw.scale)).absoluteUpperBound,
                    (lastScale - .exact(endLaw.scale)).absoluteUpperBound))
                    + .exact(scaleSlope.absoluteUpperBound) * fractionError
                let maximumScale = max(1, values.endScale, startLaw.scale, endLaw.scale).nextUp
                originalLawError = (Interval.exact(certifiedReach)
                    * (.exact(maximumScale) * angleError + scaleError)).upper
                guard originalLawError.isFinite, originalLawError <= allowance * 0.5 else {
                    return ("The original arc-length twist or scale law exceeds its complete interpolation allowance.", 20)
                }
            }
            let pieceLaws = try laws(startLaw, endLaw, at: .whole, order: 4)
            /// A section point placed over the piece or at one of its ends.
            func placed(_ point: SectionCoordinates, path: IntervalVectorDerivativeJet, frame: RotationJet,
                        at place: HomogeneousBezier.Place, order: Int) throws -> IntervalVectorDerivativeJet {
                if let mapEnd { return movedLinear(point, path: path, frame: frame, map: mapJets(mapStart, mapEnd, at: place, order: order)) }
                let placeLaws = place == .whole && order == 4 ? pieceLaws : try laws(startLaw, endLaw, at: place, order: order)
                return moved(point, path: path, frame: frame, cosine: placeLaws.cosine, sine: placeLaws.sine, scale: placeLaws.scale)
            }
            var remainder = 0.0
            for point in coordinates {
                let swept = try placed(point, path: path, frame: frame, at: .whole, order: 4)
                let fourth = swept.derivative(4).reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) }
                remainder = max(remainder, (fourth * .exact(1.0 / 384)).upper)
            }
            let pieceReach = baseReach * max(startLaw.scale, endLaw.scale, middleScale)
            guard remainder.isFinite,
                  (Interval.exact(remainder) + .exact(originalLawError)).upper <= allowance * 0.5,
                  pieceReach * curvature < 1 else {
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
            let endLaws = try laws(startLaw, endLaw, at: .end, order: 1)
            if pathIsClosed, closesSeam {
                func sectionAction(path: IntervalVectorDerivativeJet, frame: RotationJet,
                    cosine: IntervalDerivativeJet, sine: IntervalDerivativeJet,
                    scale: IntervalDerivativeJet) throws -> ClosedSweepIntervalFrameAction {
                    try ClosedSweepIntervalFrameAction(origin: pathStart, position: path.derivative(0),
                        tangent: frame.tangent.derivative(0), first: frame.rotated(carried[1]).derivative(0),
                        second: frame.rotated(carried[2]).derivative(0), originalTangent: startTangent,
                        originalFirst: lateral.0, originalSecond: lateral.1,
                        cosine: cosine.derivatives[0], sine: sine.derivatives[0], scale: scale.derivatives[0],
                        admission: sectionAdmission)
                }
                if startSectionAction == nil {
                    startSectionAction = try sectionAction(path: startPath, frame: startFrame,
                        cosine: startLaws.cosine, sine: startLaws.sine, scale: startLaws.scale)
                }
                endSectionAction = try sectionAction(path: endPath, frame: endFrame,
                    cosine: endLaws.cosine, sine: endLaws.sine, scale: endLaws.scale)
            }
            for (index, point) in coordinates.enumerated() {
                let atStart = try placed(point, path: startPath, frame: startFrame, at: .start, order: 1)
                let atEnd = try placed(point, path: endPath, frame: endFrame, at: .end, order: 1)
                let s0 = stationValues?[index] ?? atStart.derivative(0)
                let s1 = atEnd.derivative(0)
                let enclosures = [
                    s0,
                    zip(atStart.derivative(0), atStart.derivative(1)).map { $0 + $1 * third },
                    zip(s1, atEnd.derivative(1)).map { $0 - $1 * third },
                    s1,
                ]
                for (row, enclosure) in enclosures.enumerated() {
                    let chosen = row == 3 && values.endScale == 0 && endLaw.scale == 0
                        ? endPath.derivative(0).map(\.midpoint) : enclosure.map(\.midpoint)
                    numeric = max(numeric, zip(enclosure, chosen).reduce(Interval.exact(0)) {
                        $0 + .exact(($1.0 - .exact($1.1)).absoluteUpperBound)
                    }.upper)
                    pieceRows[row].append(Point3D(x: chosen[0], y: chosen[1], z: chosen[2]))
                }
                // The end's enclosure starts the next piece, so its rounding counts there too.
                nextStation.append(s1)
            }
            let error = (Interval.exact(numeric) + .exact(remainder) + .exact(originalLawError)).upper
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
            if let secondEndState, let mapEnd {
                secondState = secondEndState
                mapStart = mapEnd
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
            for _ in 0..<3 { parts = parts.flatMap { part -> [OriginalSweepPathPiece] in let halves = part.halves(); return [halves.0, halves.1] } }
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
            // Holonomy belongs to the bare transported frame. Including the
            // authored twist here would silently cancel the user's end angle.
            let endFirst = endFrame.rotated(carried[1]).derivative(0)
            endLateral = Vector3D(x: endFirst[0].midpoint,
                y: endFirst[1].midpoint, z: endFirst[2].midpoint)
            return nil
        }

        // Pieces halved where refused, worked through in order on a stack rather than by recursion
        // (deep halving would otherwise outgrow a worker's stack).
        for (span, bezier) in beziers.enumerated() {
            var pending: [(piece: OriginalSweepPathPiece, lower: Double, upper: Double, depth: Int)] = [(bezier, 0, 1, 0)]
            while let next = pending.popLast() {
                guard let refusal = try accept(next.piece, span: span, lower: next.lower,
                    upper: next.upper, depth: next.depth) else { continue }
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
        // The bare frame turn; authored twist remains in the seam's rows.
        let turnAxis = startTangent.cross(lateral.0)
        let closingTurn = pathIsClosed ? atan2(endLateral.dot(turnAxis), endLateral.dot(lateral.0)) : 0
        var seamClosed = false
        var retainedSeamTransport: ClosedSweepSectionCorrespondence.RowTransport?
        if pathIsClosed, closesSeam, let last = rows.indices.last {
            guard let authoredSeam, let startSectionAction, let endSectionAction else {
                throw Self.failure(.invalidInput,
                    "Closing a sweep requires the retained original authored seam and endpoint frame actions.", featureID, tolerance)
            }
            if let transport = try authoredSeam.transport(loops: sectionLoops,
                firstRow: rows[0][0], lastRow: rows[last][3],
                startAction: startSectionAction, endAction: endSectionAction,
                tolerance: tolerance, admission: sectionAdmission) {
                let completeError = (Interval.exact(transport.maximumControlDisplacement)
                    + .exact(maximumError)).upper
                if completeError <= allowance {
                    rows[last][3] = transport.row
                    maximumError = completeError
                    seamClosed = true
                    retainedSeamTransport = transport
                }
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
        terminalSectionCollapsed = values.endScale == 0
        self.pathIsClosed = pathIsClosed
        self.closingTurn = closingTurn
        self.seamClosed = seamClosed
        originalSeam = authoredSeam
        seamTransport = retainedSeamTransport
    }

    /// The plan for a closed path: measured once, then again with a twist law taking out the turn
    /// the frame comes back with (it depends a little on where the pieces fall, so a few rounds
    /// settle it), its last row then made the first. The retained twist law is composed with
    /// that correction; a nonperiodic scale or unresolved guide cannot close a section.
    package static func closed(
        section: ResolvedModelingSection,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID?,
        tolerance: ModelingTolerance,
        sourceBudget suppliedBudget: CurvedSweepSourceBudget? = nil
    ) throws -> Self {
        guard values.endScale == 1, sweep.guides.isEmpty,
              values.approximationTolerance != nil else {
            throw failure(.sweepTwistUnavailable,
                "A closed sweep requires a periodic scale, resolved guide closure and a positional allowance.", featureID, tolerance)
        }
        let authoredPositions = values.twistPositions
        let authoredAngles = values.twistAngles.isEmpty ? [0, values.twistAngle] : values.twistAngles
        guard authoredPositions.count == authoredAngles.count, authoredPositions.count >= 2 else {
            throw failure(.sweepTwistUnavailable, "A closed sweep twist requires matching retained knots.", featureID, tolerance)
        }
        var correction = 0.0
        let sourceBudget = try suppliedBudget ?? CurvedSweepSourceBudget(tolerance: tolerance)
        let admission = try sourceBudget.conversionAdmission()
        let builder = ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission)
        let sectionLoops: [[ExactBSplineCurveSpan]]
        let sectionIsClosed: Bool
        switch section {
        case .profile, .face, .constructedRegion:
            sectionLoops = try builder.loopSpans(from: section); sectionIsClosed = true
        case .curve(let curve):
            sectionLoops = [try builder.sectionSpans(from: curve)]; sectionIsClosed = curve.isClosed
        }
        let originalPathPieces = try OriginalSweepPathPiece.prepare(pathSpans,
            tolerance: tolerance, budget: sourceBudget)
        guard let firstPiece = originalPathPieces.first,
              let tangent = try firstPiece.pointJet(at: .start, order: 1).tangent(),
              let pathStart = pathSpans.first?.startPoint else {
            throw failure(.invalidInput, "The closed sweep has no original initial frame.", featureID, tolerance)
        }
        let axes = try lateralAxes(of: tangent, tolerance: tolerance)
        let turn = Interval.exact(authoredAngles[authoredAngles.count - 1]) - .exact(authoredAngles[0])
        let harmonic = try CertifiedRotationTrigonometry.evaluate(turn, tolerance: tolerance,
            consumeWork: { try sourceBudget.consume(depth: 0) })
        let authoredAction = try ClosedSweepIntervalFrameAction(origin: pathStart,
            position: Self.values(pathStart), tangent: Self.values(tangent), first: Self.values(axes.0), second: Self.values(axes.1),
            originalTangent: tangent, originalFirst: axes.0, originalSecond: axes.1,
            cosine: harmonic.cosine, sine: harmonic.sine, scale: .exact(1), admission: admission)
        let authoredSeam = try ClosedSweepSectionCorrespondence(loops: sectionLoops,
            authoredAction: authoredAction, tolerance: tolerance, admission: admission)
        var originalLengthLaw: OriginalCurvedSweepArcLengthLaw?
        for _ in 0..<6 {
            var corrected = values
            corrected.twistAngles = zip(authoredPositions, authoredAngles).map { fraction, angle in
                angle + correction * fraction
            }
            corrected.twistPositions = authoredPositions
            if originalLengthLaw == nil, corrected.twistAngles.contains(where: { $0 != 0 }) {
                originalLengthLaw = try OriginalCurvedSweepArcLengthLaw(spans: pathSpans,
                    tolerance: tolerance, budget: sourceBudget)
            }
            let plan = try Self(sectionLoops: sectionLoops, sectionIsClosed: sectionIsClosed,
                                profilePlane: section.plane(), pathSpans: pathSpans, sweep: sweep, values: corrected,
                                pathIsClosed: true, closesSeam: true, authoredSeam: authoredSeam, sourceBudget: sourceBudget,
                                originalLengthLaw: originalLengthLaw,
                                originalPathPieces: originalPathPieces,
                                featureID: featureID, tolerance: tolerance)
            if plan.seamClosed { return plan }
            correction = -plan.closingTurn
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
    /// A linear map of the plane across the path, in its lateral coordinates: (x, y) to
    /// (a·x + b·y, c·x + d·y).
    private struct LinearMap {
        let a: Double
        let b: Double
        let c: Double
        let d: Double

        static let identity = LinearMap(a: 1, b: 0, c: 0, d: 1)
        var determinant: Double { a * d - b * c }
        /// The Frobenius norm, bounding how far the map stretches any offset.
        var norm: Double { (a * a + b * b + c * c + d * d).squareRoot() }
        func midway(to other: LinearMap) -> LinearMap {
            LinearMap(a: 0.5 * (a + other.a), b: 0.5 * (b + other.b), c: 0.5 * (c + other.c), d: 0.5 * (d + other.d))
        }
        func distance(to other: LinearMap) -> Double {
            LinearMap(a: a - other.a, b: b - other.b, c: c - other.c, d: d - other.d).norm
        }
    }

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

private extension OriginalSweepPathPiece {
    func jet(over place: Place, order: Int) throws -> PathJet {
        PathJet(originalPosition: try derivativeJet(over: place, order: order))
    }

    func pointJet(at place: Place, order: Int) throws -> PathJet {
        try jet(over: place, order: order)
    }
}

/// The complete original path position derivative enclosure.
private struct PathJet {
    let originalPosition: IntervalVectorDerivativeJet
    var position: IntervalVectorDerivativeJet? { originalPosition }

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
