#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A path-normal Sweep along a path with corners, its arms joined at mitred or round corners.
///
/// The path is cut into legs: straight spans running on one way, and curved spans running on
/// smoothly, whose section the certified curved sweep carries (`CertifiedCurvedPathSweepPlan`,
/// the section placed where the leg starts). A corner joins two straight legs (arms). The section
/// moves with the path's least-rotation frame: along an arm it slides, along a curved leg it turns
/// with the curved sweep's frame, and at a corner it turns by the least rotation taking the arm's
/// direction to the next one's. Each arm
/// is the prism its section sweeps between the arm's two ends, each end the section pushed along
/// the arm onto the mitre plane through the corner (the plane whose normal is the sum of the two
/// directions), so neighbouring arms meet on that plane in the same curve. An open path is capped
/// by the section at its start and where the frame carries it at its end; a closed path closes on
/// itself when its frame comes back to where it started.
///
/// A round corner keeps the mitre on the inside of the turn and rounds the outside: the section is
/// split where it crosses the plane through the path holding the arm and the corner's axis (the
/// line through the corner across both arms), the outer pieces end on the plane across each arm
/// through the corner, and between those ends they turn about the axis by the corner's angle as
/// original rational revolution tensors. An end on the axis retains its collapsed UV boundary
/// use; original coefficient classification owns its singular topology.
package struct MitredPolylineSweepBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Whether a sweep takes this route: a path-normal sweep along a path with at least one
    /// corner between its spans.
    package static func applies(_ options: SweepOptions, pathSpans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance, sourceBudget: CurvedSweepSourceBudget? = nil) throws -> Bool {
        guard options.alignment == .normal, pathSpans.count >= 2 else { return false }
        let invocation = try sourceBudget ?? CurvedSweepSourceBudget(tolerance: tolerance)
        let admission = try invocation.conversionAdmission()
        let builder = MitredPolylineSweepBuilder(tolerance: tolerance)
        return try zip(pathSpans, pathSpans.dropFirst()).contains { before, after in
            builder.smooth(try builder.tangent(of: before, atEnd: true, admission: admission), try builder.tangent(of: after, atEnd: false, admission: admission)) == false
        }
    }

    /// Whether two unit tangents run on the same way.
    private func smooth(_ a: Vector3D, _ b: Vector3D) -> Bool {
        a.cross(b).length <= sin(tolerance.angle) && a.dot(b) > 0
    }

    /// Whether the retained original span is a straight segment.
    private func isStraight(_ span: ExactBSplineCurveSpan, admission: GeometryConversionAdmission) throws -> Bool {
        try OriginalSweepPathLinearity(tolerance: tolerance, admission: admission)
            .containsOnlyLinearArms([span])
    }

    /// A span's unit tangent at its start or end, along its run.
    private func tangent(of span: ExactBSplineCurveSpan, atEnd: Bool, admission: GeometryConversionAdmission) throws -> Vector3D {
        if try isStraight(span, admission: admission) { return try (span.endPoint - span.startPoint).normalized(tolerance: tolerance.distance) }
        guard case let .closed(lower, upper) = span.curve.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A sweep path span is unbounded.")
        }
        let jet = try Curve3D.bSpline(span.curve).differentialGeometry(at: atEnd ? upper : lower, tolerance: tolerance)
        return try jet.firstDerivative.normalized(tolerance: tolerance.distance)
    }

    /// The path's legs in order: straight spans running on one way are one straight leg, curved
    /// spans running on smoothly one curved leg.
    private func legs(of spans: [ExactBSplineCurveSpan], admission: GeometryConversionAdmission) throws -> [Leg] {
        var legs: [Leg] = []
        for span in spans {
            try admission.chargeWork()
            let straight = try isStraight(span, admission: admission)
            let (startTangent, endTangent) = (try tangent(of: span, atEnd: false, admission: admission), try tangent(of: span, atEnd: true, admission: admission))
            if let last = legs.last, last.isStraight == straight, smooth(last.endTangent, startTangent) {
                legs[legs.count - 1].spans.append(span)
                legs[legs.count - 1].end = span.endPoint
                legs[legs.count - 1].endTangent = endTangent
            } else {
                legs.append(Leg(spans: [span], isStraight: straight, start: span.startPoint, end: span.endPoint,
                                startTangent: startTangent, endTangent: endTangent))
            }
        }
        return legs
    }

    /// The direction of an open section made of straight spans along one line, nil otherwise.
    private func straightSectionDirection(_ loops: [[ExactBSplineCurveSpan]]) throws -> Vector3D? {
        let points = loops.flatMap { $0.flatMap { $0.curve.controlPoints } }
        guard let first = points.first, let far = points.max(by: { ($0 - first).length < ($1 - first).length }),
              (far - first).length > tolerance.distance else { return nil }
        let direction = try (far - first).normalized(tolerance: tolerance.distance)
        let straight = points.allSatisfy { let offset = $0 - first; return (offset - direction * offset.dot(direction)).length <= tolerance.distance }
        return straight ? direction : nil
    }

    package struct Request {
        package let request: BRepSewingRequest
        package let armCount: Int
        package let includesCaps: Bool
        package let includesEndCap: Bool
        /// The section's spans per loop, after a round corner's splits.
        package let profileSpanCounts: [Int]
        /// The stable identities of round corners' faces, in corner, loop and span order.
        package let cornerFaceIDs: [String]
    }

    package func request(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        pathIsClosed: Bool,
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID,
        guidesAreEmpty: Bool = true,
        sourceBudget: CurvedSweepSourceBudget? = nil
    ) throws -> Request {
        try tolerance.validate()
        let options = sweep.options
        let sourceBudget = try sourceBudget ?? CurvedSweepSourceBudget(tolerance: tolerance)
        let admission = try sourceBudget.conversionAdmission()
        try admission.chargeWork()
        guard !pathSpans.isEmpty, !sectionLoops.isEmpty else {
            throw failure(.invalidInput, "Corner Sweep requires original path and section spans.", featureID)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): corner-arm scale retains its original affine law,
        // but twist and guide deformation at a corner still require their original producer.
        // Production path: MitredPolylineSweepBuilder for path-normal straight-arm sweeps.
        // Complete only when original twist and guide laws retain whole-domain certificates
        // through the corner and published measured sections verify those laws.
        guard values.twistAngle == 0, options.twistLaw == nil, guidesAreEmpty, sweep.guides.isEmpty else {
            throw failure(.sweepRoundCornerUnavailable,
                "A sweep corner requires the original twist and guide deformation producer.", featureID)
        }
        guard options.resultKind == .sheet || sectionIsClosed else {
            throw failure(.invalidInput, "A solid sweep needs a closed section.", featureID)
        }
        guard values.distanceFraction == 1 else {
            throw failure(.invalidInput, "A sweep along a path with corners runs the whole path.", featureID)
        }
        guard values.endScale.isFinite, values.endScale >= 0,
              !pathIsClosed || values.endScale == 1 else {
            throw failure(.invalidInput, "Corner Sweep scale must be nonnegative and periodic on a closed path.", featureID)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Production Corner Sweep now shares
        // the caller's original work/storage ledger, but lower patch admission,
        // tensor/pcurve constructors and intersection temporaries still require
        // their bounded callback ports before full resource admission is complete.
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let sectionPlane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance).plane
        for loop in sectionLoops {
            try admission.chargeWork(loop.count)
            try patches.validateSectionContinuity(loop, isClosed: sectionIsClosed)
            try patches.validateProfileSpans(loop, on: sectionPlane)
        }
        // Legs: straight spans running on one way are one straight leg, curved spans running on
        // smoothly one curved leg; a corner is where the path's tangent turns between two legs.
        var legs = try self.legs(of: pathSpans, admission: admission)
        if pathIsClosed, legs.count > 1, let first = legs.first, let last = legs.last,
           smooth(last.endTangent, first.startTangent), first.isStraight == last.isStraight {
            // The closing leg runs on into the first: one leg through the path's start.
            legs[0] = Leg(spans: last.spans + first.spans, isStraight: first.isStraight, start: last.start, end: first.end,
                          startTangent: last.startTangent, endTangent: first.endTangent)
            legs.removeLast()
        }
        var normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        // An open straight section lies in many planes: when its sketch plane runs along the first
        // arm (a line drawn in the path's plane), it is taken in the plane through it square to
        // that one, so it sweeps a flat ribbon along the path.
        if sectionIsClosed == false, abs(normal.dot(legs[0].startTangent)) <= max(tolerance.relative, sin(tolerance.angle)),
           let line = try straightSectionDirection(sectionLoops) {
            normal = try line.cross(normal).normalized(tolerance: tolerance.distance)
        }
        func cornerBefore(_ index: Int, in legs: [Leg]) -> Bool {
            guard index > 0 || pathIsClosed else { return false }
            let before = legs[(index + legs.count - 1) % legs.count]
            return smooth(before.endTangent, legs[index].startTangent) == false
        }
        if pathIsClosed {
            // A closed path starts at the corner nearest the section, leaving along the leg that
            // runs most across the section's plane.
            let sectionPoints = sectionLoops.flatMap { $0.flatMap { $0.curve.controlPoints } }
            let centroid = sectionPoints.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(max(sectionPoints.count, 1)))
            guard let nearest = legs.indices.filter({ cornerBefore($0, in: legs) })
                .min(by: { (legs[$0].start - .origin - centroid).length < (legs[$1].start - .origin - centroid).length }) else {
                throw failure(.invalidInput, "A closed sweep path has no corners.", featureID)
            }
            legs = Array(legs[nearest...] + legs[..<nearest])
            if abs(normal.dot(legs[legs.count - 1].endTangent)) > abs(normal.dot(legs[0].startTangent)) {
                legs = try legs.reversed().map { try $0.reversed(tolerance: tolerance) }
            }
        }
        let legCount = legs.count
        let corners = (0..<legCount).map { cornerBefore($0, in: legs) }
        // Each leg starts where the one before it ends, so rows built at the join coincide.
        for index in legs.indices.dropFirst() { legs[index].start = legs[index - 1].end }
        for index in legs.indices where corners[index] {
            let before = legs[(index + legCount - 1) % legCount]
            guard before.isStraight, legs[index].isStraight else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a corner beside a curved span would cut the
                // curved sweep by the mitre plane, which has no exact trimming curve, so it is
                // refused. Production path: MitredPolylineSweepBuilder for every path-normal sweep
                // along a path with corners. Complete only when such corners join, verified by a
                // sweep along a path whose arc meets a line at a corner.
                throw failure(.sweepRoundCornerUnavailable,
                    "A sweep path's corners are between straight spans; a curve meets this one.", featureID)
            }
        }
        let advance = normal.dot(legs[0].startTangent)
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw failure(.sweepProfilePlaneDegenerate, "The section's plane runs along the path.", featureID)
        }
        let origin = legs[0].start
        /// A curved leg's sweep: the certified curved plan of the section placed where the leg
        /// starts by the frame `rotation`, and the frame it carries the section to at the leg's end.
        func curvedSweep(_ leg: Leg, rotation: Rotation, loops: [[ExactBSplineCurveSpan]])
            throws -> (plan: CertifiedCurvedPathSweepPlan, carried: Rotation) {
            let placed = try loops.map { loop in
                try loop.map { span in
                    try ExactBSplineCurveSpan(curve: BSplineCurve3D(
                        degree: span.curve.degree, knots: span.curve.knots,
                        controlPoints: span.curve.controlPoints.map { leg.start + rotation.applied(to: $0 - origin) },
                        weights: span.curve.weights
                    ), tolerance: tolerance)
                }
            }
            guard let anchor = placed.first?.first?.startPoint else {
                throw failure(.invalidInput, "A sweep's section has no span.", featureID)
            }
            let plan = try CertifiedCurvedPathSweepPlan(
                sectionLoops: placed, sectionIsClosed: sectionIsClosed,
                profilePlane: .plane(Plane3D(origin: anchor, normal: rotation.applied(to: normal))),
                pathSpans: leg.spans, sweep: sweep, values: values, sourceBudget: sourceBudget, featureID: featureID, tolerance: tolerance
            )
            // The frame the plan carries the section in: its first loop's rows at the leg's two
            // ends, each read as the tangent there and the section's farthest point across it.
            let starts = try plan.surfaces[0][0].flatMap { try $0.uIsoparametricCurve(atV: 0, tolerance: tolerance).controlPoints }
            let ends = try plan.surfaces[0][plan.pieceCount - 1].flatMap { try $0.uIsoparametricCurve(atV: 1, tolerance: tolerance).controlPoints }
            func across(_ point: Point3D, from base: Point3D, tangent: Vector3D) -> Vector3D {
                let offset = point - base
                return offset - tangent * offset.dot(tangent)
            }
            guard starts.count == ends.count,
                  let far = starts.indices.max(by: { across(starts[$0], from: leg.start, tangent: leg.startTangent).length
                      < across(starts[$1], from: leg.start, tangent: leg.startTangent).length }),
                  across(starts[far], from: leg.start, tangent: leg.startTangent).length > tolerance.distance else {
                throw failure(.invalidInput, "A sweep's section reaches nowhere across a curved stretch of its path.", featureID)
            }
            let e0 = try across(starts[far], from: leg.start, tangent: leg.startTangent).normalized(tolerance: tolerance.distance)
            let e1 = try across(ends[far], from: leg.end, tangent: leg.endTangent).normalized(tolerance: tolerance.distance)
            let carried = Rotation(frame: (leg.endTangent, e1, leg.endTangent.cross(e1)))
                .composed(with: Rotation(frame: (leg.startTangent, e0, leg.startTangent.cross(e0))).transposed)
            // The section moves rigidly: every point of the rows is where the frame carries it.
            for (start, end) in zip(starts, ends) {
                let miss = (leg.end + carried.applied(to: start - leg.start) - end).length
                guard miss <= plan.positionErrorUpperBound + tolerance.distance else {
                    throw failure(.invalidInput, "A curved stretch of a sweep path does not carry its section rigidly.", featureID)
                }
            }
            return (plan, carried)
        }
        /// The frame at each leg's start (the least rotations through the corners, the curved
        /// sweeps' frames along curved legs) and at the path's end, with each curved leg's plan.
        func frames(_ loops: [[ExactBSplineCurveSpan]]) throws -> (starts: [Rotation], end: Rotation, plans: [Int: CertifiedCurvedPathSweepPlan]) {
            var starts: [Rotation] = []
            var plans: [Int: CertifiedCurvedPathSweepPlan] = [:]
            var current = Rotation.identity
            for (index, leg) in legs.enumerated() {
                if index > 0, corners[index] {
                    current = try Rotation(from: legs[index - 1].endTangent, to: leg.startTangent, tolerance: tolerance).composed(with: current)
                }
                starts.append(current)
                if leg.isStraight == false {
                    let (plan, carried) = try curvedSweep(leg, rotation: current, loops: loops)
                    plans[index] = plan
                    current = carried.composed(with: current)
                }
            }
            return (starts, current, plans)
        }
        let firstFrames = try frames(sectionLoops)
        let rotations = firstFrames.starts
        if pathIsClosed {
            let closing = corners[0]
                ? try Rotation(from: legs[legCount - 1].endTangent, to: legs[0].startTangent, tolerance: tolerance).composed(with: firstFrames.end)
                : firstFrames.end
            guard closing.isIdentity(tolerance: tolerance) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a closed path whose frame comes back turned
                // (a non-planar loop) is refused. Production path: MitredPolylineSweepBuilder for
                // every closed path-normal sweep. Complete only when the turn is spread along the
                // arms as a twist, verified by a sweep around a non-planar closed polyline.
                throw failure(.sweepRoundCornerUnavailable,
                    "A closed sweep path brings its frame back turned; it must lie in a plane.", featureID)
            }
        }
        var cornerScales = Array(repeating: 1.0, count: legCount + 1)
        if values.endScale != 1 {
            // FIXME(INCOMPLETE_IMPLEMENTATION): mixed curved-leg Corner Sweep retains
            // rigid unit-scale transport. Its production path requires original scale
            // through curved legs and corners before nonunit scale can be admitted.
            // The existing retained affine scale law belongs to straight-arm sweeps.
            guard legs.allSatisfy({ $0.isStraight }) else {
                throw failure(.sweepRoundCornerUnavailable,
                    "A sweep containing curved legs takes no end scale.", featureID)
            }
            var cumulative = [0.0]
            for leg in legs {
                try admission.chargeWork()
                let length = (leg.end - leg.start).length
                guard length.isFinite, length > tolerance.distance else {
                    throw failure(.invalidInput, "A scaled Sweep arm requires a finite positive original length.", featureID)
                }
                cumulative.append(cumulative[cumulative.count - 1] + length)
            }
            guard let totalLength = cumulative.last, totalLength.isFinite, totalLength > 0 else {
                throw failure(.resourceLimitExceeded, "Corner Sweep arc-length accumulation is nonfinite.", featureID)
            }
            cornerScales = cumulative.enumerated().map { index, length in
                index + 1 == cumulative.count ? values.endScale : 1 + (values.endScale - 1) * (length / totalLength)
            }
        }
        // Round corners: corner `j` joins leg `j - 1` (the last leg for the closing corner) to leg
        // `j`; its inner side, carried back to the section's frame, splits the section.
        var roundCorners: [Int: RoundCorner] = [:]
        if options.cornerStyle == .round {
            for j in 0..<legCount where corners[j] {
                let before = (j + legCount - 1) % legCount
                let (incoming, outgoing) = (legs[before].endTangent, legs[j].startTangent)
                let turn = incoming.cross(outgoing)
                let inner = try (outgoing - incoming * incoming.dot(outgoing)).normalized(tolerance: tolerance.distance)
                roundCorners[j] = RoundCorner(
                    before: before, point: legs[j].start,
                    axis: try turn.normalized(tolerance: tolerance.distance),
                    angle: atan2(turn.length, incoming.dot(outgoing)),
                    inner: rotations[before].transposed.applied(to: inner)
                )
            }
        }
        var remainingPlaneVisits = 65_536
        func consumePlaneWork() throws {
            try admission.chargeWork()
            guard remainingPlaneVisits > 0 else {
                throw failure(.resourceLimitExceeded,
                    "Corner Sweep original plane proof exhausted its request budget.", featureID)
            }
            remainingPlaneVisits -= 1
        }
        let loops = try splitSections(sectionLoops, origin: origin, across: roundCorners.values.map { $0.inner },
            consumeWork: consumePlaneWork, admission: admission)
        // The curved legs' plans over the section as split (their frames do not depend on it).
        let plans = loops.map { $0.count } == sectionLoops.map { $0.count } ? firstFrames.plans : try frames(loops).plans
        /// Whether a section span lies on the outer side of round corner `j`.
        func isOuter(_ span: ExactBSplineCurveSpan, corner j: Int) throws -> Bool {
            guard let corner = roundCorners[j] else { return false }
            return try originalSpanPlaneSide(span.curve, origin: origin,
                normal: corner.inner, featureID: featureID, consumeWork: consumePlaneWork) == .negative
        }
        /// Where a section point on straight leg `leg` meets the leg's start (`end` false) or end:
        /// the section carried there by the leg's frame, at a corner pushed along the leg onto the
        /// mitre plane, or for the outside of a round corner onto the plane across the leg.
        func place(_ point: Point3D, leg: Int, end: Bool, outer: Bool) throws -> Point3D {
            let offset = rotations[leg].applied(to: point - origin) * cornerScales[end ? leg + 1 : leg]
            let direction = legs[leg].startTangent
            let anchor = end ? legs[leg].end : legs[leg].start
            if outer { return anchor + (offset - direction * offset.dot(direction)) }
            let neighbour: Vector3D?
            if end {
                let next = (leg + 1) % legCount
                neighbour = (leg + 1 < legCount || pathIsClosed) && corners[next] ? legs[next].startTangent : nil
            } else {
                neighbour = corners[leg] ? legs[(leg + legCount - 1) % legCount].endTangent : nil
            }
            guard let neighbour else { return anchor + offset }
            let mitre = direction + neighbour
            let along = direction.dot(mitre)
            guard along > max(tolerance.relative, sin(tolerance.angle)) else {
                throw failure(.sweepRoundCornerUnavailable, "A sweep path turns back on itself at a corner.", featureID)
            }
            return anchor + (offset - direction * (offset.dot(mitre) / along))
        }
        // Each straight leg's sides: per section span, the ruled surface between its two ends;
        // each curved leg's, its plan's rows. Side faces are numbered along the path.
        var sides: [[BRepSewingFacePatch]] = loops.map { _ in [] }
        let windingSigns = try loops.map { loop in
            sectionIsClosed ? try patches.profileWindingSign(loop, normal: normal, featureID: featureID) : 1.0
        }
        let orientations: [Orientation] = windingSigns.map { sign in
            sectionIsClosed ? (sign * (advance > 0 ? 1 : -1) > 0 ? .forward : .reversed) : .forward
        }
        func sideID(_ piece: Int, _ loopIndex: Int, _ spanIndex: Int) -> String {
            loopIndex == 0 ? "sweep:side:path:\(piece):profile:\(spanIndex)"
                : "sweep:side:path:\(piece):inner:\(loopIndex - 1):profile:\(spanIndex)"
        }
        var startRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        var endRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        // Each leg's end rows, kept for the round corner after it.
        var legEndRows: [[[BSplineCurve3D]]] = []
        var piece = 0
        for leg in 0..<legCount {
            var legEnds: [[BSplineCurve3D]] = loops.map { _ in [] }
            if let plan = plans[leg] {
                for (loopIndex, _) in loops.enumerated() {
                    for p in 0..<plan.pieceCount {
                        for (spanIndex, surface) in plan.surfaces[loopIndex][p].enumerated() {
                            sides[loopIndex].append(try patches.tensorSidePatch(
                                surface: surface, orientation: orientations[loopIndex], stableID: sideID(piece + p, loopIndex, spanIndex)
                            ))
                        }
                    }
                    let first = try plan.surfaces[loopIndex][0].map { try $0.uIsoparametricCurve(atV: 0, tolerance: tolerance) }
                    let last = try plan.surfaces[loopIndex][plan.pieceCount - 1].map { try $0.uIsoparametricCurve(atV: 1, tolerance: tolerance) }
                    if leg == 0 { startRows[loopIndex] = first }
                    if leg == legCount - 1 { endRows[loopIndex] = last }
                    legEnds[loopIndex] = last
                }
                piece += plan.pieceCount
                legEndRows.append(legEnds)
                continue
            }
            let endCorner = (leg + 1) % legCount
            for (loopIndex, loop) in loops.enumerated() {
                let orientation = orientations[loopIndex]
                for (spanIndex, span) in loop.enumerated() {
                    try admission.chargeWork()
                    let outerAtStart = try isOuter(span, corner: leg)
                    let outerAtEnd = (leg + 1 < legCount || pathIsClosed) ? try isOuter(span, corner: endCorner) : false
                    let bytes = span.curve.controlPoints.count.multipliedReportingOverflow(by: 2 * MemoryLayout<Point3D>.stride)
                    guard !bytes.overflow else { throw failure(.resourceLimitExceeded, "Corner Sweep row payload overflows.", featureID) }
                    try admission.chargeStorage(bytes: bytes.partialValue)
                    // After a curved leg the leg starts on that leg's last row.
                    let starts = try leg > 0 && plans[leg - 1] != nil
                        ? legEndRows[leg - 1][loopIndex][spanIndex].controlPoints
                        : span.curve.controlPoints.map {
                            try admission.chargeWork()
                            return try place($0, leg: leg, end: false, outer: outerAtStart)
                        }
                    let ends = try span.curve.controlPoints.map {
                        try admission.chargeWork()
                        return try place($0, leg: leg, end: true, outer: outerAtEnd)
                    }
                    // The leg must run forward from its start to its end at every point.
                    for (start, end) in zip(starts, ends) where (end - start).dot(legs[leg].startTangent) <= tolerance.distance {
                        throw failure(.sweepRoundCornerUnavailable,
                            "The section is wider than an arm of the path allows at its mitres.", featureID)
                    }
                    let surface = BSplineSurface3D(
                        uDegree: span.curve.degree, vDegree: 1,
                        uKnots: span.curve.knots, vKnots: [0, 0, 1, 1],
                        controlPoints: [starts, ends], weights: [span.curve.weights, span.curve.weights]
                    )
                    try surface.validate(tolerance: tolerance)
                    sides[loopIndex].append(try patches.tensorSidePatch(
                        surface: surface, orientation: orientation, stableID: sideID(piece, loopIndex, spanIndex)
                    ))
                    if leg == 0 { startRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 0, tolerance: tolerance)) }
                    if leg == legCount - 1 { endRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance)) }
                    legEnds[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance))
                }
            }
            piece += 1
            legEndRows.append(legEnds)
        }
        let pieceCount = piece
        // Round corners' outer pieces turn about the corner's axis from one leg's end to the next
        // leg's start.
        var cornerFaceIDs: [String] = []
        for j in roundCorners.keys.sorted() {
            guard let corner = roundCorners[j] else { continue }
            for (loopIndex, loop) in loops.enumerated() {
                for (spanIndex, span) in loop.enumerated() where try isOuter(span, corner: j) {
                    let stableID = loopIndex == 0
                        ? "sweep:corner:\(j):profile:\(spanIndex)"
                        : "sweep:corner:\(j):inner:\(loopIndex - 1):profile:\(spanIndex)"
                    sides[loopIndex].append(try revolvedPatch(
                        legEndRows[corner.before][loopIndex][spanIndex], about: corner,
                        orientation: orientations[loopIndex], stableID: stableID, patches: patches,
                        admission: admission
                    ))
                    cornerFaceIDs.append(stableID)
                }
            }
        }
        let includesCaps = options.resultKind == .solid && !pathIsClosed
        var caps: [BRepSewingFacePatch] = []
        if includesCaps {
            caps.append(try cap(startRows, normal: normal, outerWinding: windingSigns[0], advance: advance, atEnd: false, patches: patches))
            if values.endScale != 0 {
                caps.append(try cap(endRows, normal: firstFrames.end.applied(to: normal), outerWinding: windingSigns[0],
                    advance: advance, atEnd: true, patches: patches))
            }
        }
        let request: BRepSewingRequest
        if options.resultKind == .solid {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                shells: [BRepSewingShell(stableID: "sweep:shell", patches: caps + sides.flatMap { $0 })])
        } else {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: sides.enumerated().map { index, patches in
                BRepSewingShell(stableID: index == 0 ? "sweep:shell" : "sweep:inner:\(index - 1):shell", patches: patches)
            })
        }
        return Request(request: request, armCount: pieceCount, includesCaps: includesCaps, includesEndCap: values.endScale != 0,
                       profileSpanCounts: loops.map { $0.count }, cornerFaceIDs: cornerFaceIDs)
    }

    /// `loops` with each span split where it crosses one of the planes through `origin` across
    /// `normals`, so every piece lies on one side of each.
    private func splitSections(
        _ loops: [[ExactBSplineCurveSpan]], origin: Point3D, across normals: [Vector3D],
        consumeWork: () throws -> Void,
        admission: GeometryConversionAdmission
    ) throws -> [[ExactBSplineCurveSpan]] {
        var planes: [Vector3D] = []
        for normal in normals where !planes.contains(where: { $0 == normal || $0 == -normal }) {
            planes.append(normal)
        }
        guard !planes.isEmpty else { return loops }
        let intersector = DefaultCurveSurfaceIntersector()
        var remainingContacts = 65_536
        return try loops.map { loop in
            try loop.flatMap { span -> [ExactBSplineCurveSpan] in
                let curve = Curve3D.bSpline(span.curve)
                let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(span.curve.domain)
                var roots: [Double] = []
                for normal in planes {
                    try consumeWork()
                    let signs = try originalControlPlaneSigns(span.curve, origin: origin, normal: normal,
                        consumeWork: consumeWork)
                    if signs.allSatisfy({ $0 == .zero || $0 == .positive })
                        || signs.allSatisfy({ $0 == .zero || $0 == .negative }) { continue }
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Production Round Sweep
                    // must retain original root charts and share this caller's
                    // complete intersection work/byte admission; numeric events
                    // remain proposals and cannot establish exact pole endpoints.
                    let contacts = try intersector.intersections(curve: curve,
                        surface: .plane(Plane3D(origin: origin, normal: normal)),
                        options: .init(curveRange: ScalarInterval(lower: bounds.lower, upper: bounds.upper)),
                        tolerance: tolerance)
                    guard contacts.count <= remainingContacts else {
                        throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                            tolerance: tolerance, message: "Round Sweep split contacts exhausted their request budget.")
                    }
                    remainingContacts -= contacts.count
                    roots.append(contentsOf: contacts.map { $0.curveParameter })
                }
                var cuts: [Double] = []
                for root in roots.sorted() where root > bounds.lower && root < bounds.upper {
                    if cuts.last != root { cuts.append(root) }
                }
                guard !cuts.isEmpty else { return [span] }
                let breaks = [bounds.lower] + cuts + [bounds.upper]
                return try zip(breaks, breaks.dropFirst()).map { lower, upper in
                    try consumeWork()
                    return try ExactBSplineCurveSpan(curve: span.curve.trimmed(from: lower, to: upper, tolerance: tolerance),
                        tolerance: tolerance,
                        originalChart: span.originalChart.restricted(from: lower, to: upper,
                            in: span.curve.domain, tolerance: tolerance), admission: admission)
                }
            }
        }
    }

    private func originalControlPlaneSigns(_ curve: BSplineCurve3D, origin: Point3D,
        normal: Vector3D, consumeWork: () throws -> Void) throws -> [RobustSign] {
        guard curve.weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original split-side hull requires positive native weights.")
        }
        return try curve.controlPoints.map { point in
            try OriginalPointPlaneSide().sign(point: point, origin: origin, normal: normal, consumeWork: consumeWork)
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): complete side proof consumes the retained native
    // curve, but general algebraic split endpoints still need their original contact chart.
    // Production Round Sweep must not infer an exact pole from a numeric trimmed endpoint;
    // full completion also requires original contact-chart and whole pole-normal receipts.
    private func originalSpanPlaneSide(_ curve: BSplineCurve3D, origin: Point3D,
        normal: Vector3D, featureID: FeatureID, consumeWork: () throws -> Void) throws -> RobustSign {
        let signs = try originalControlPlaneSigns(curve, origin: origin, normal: normal, consumeWork: consumeWork)
        if signs.allSatisfy({ $0 == .zero }) { return .zero }
        if signs.allSatisfy({ $0 == .zero || $0 == .positive }) { return .positive }
        if signs.allSatisfy({ $0 == .zero || $0 == .negative }) { return .negative }
        let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(curve.domain)
        let startsOnPlane = signs.first == .zero
            && curve.knots.prefix(curve.degree + 1).allSatisfy({ $0 == bounds.lower })
        let endsOnPlane = signs.last == .zero
            && curve.knots.suffix(curve.degree + 1).allSatisfy({ $0 == bounds.upper })
        let source = try NativeCurveDerivativeEncloser(curve: .bSpline(curve),
            tolerance: tolerance, consumeWork: consumeWork)
        var stack: [(lower: Double, upper: Double, depth: Int)] = [(bounds.lower, bounds.upper, 0)]
        var retainedSide: RobustSign?
        func projection(_ values: [OutwardScalarInterval]) -> OutwardScalarInterval {
            values[0] * .exact(normal.x) + values[1] * .exact(normal.y) + values[2] * .exact(normal.z)
        }
        while let cell = stack.popLast() {
            try consumeWork()
            let jet = try source.derivatives(over: ScalarInterval(lower: cell.lower, upper: cell.upper), tolerance: tolerance)
            let position = jet.derivative(0)
            let value = projection([position[0] - .exact(origin.x),
                position[1] - .exact(origin.y), position[2] - .exact(origin.z)])
            let derivative = projection(jet.derivative(1))
            let side: RobustSign?
            if value.lower >= 0 { side = .positive }
            else if value.upper <= 0 { side = .negative }
            else if cell.lower == bounds.lower && startsOnPlane && derivative.lower > 0 { side = .positive }
            else if cell.lower == bounds.lower && startsOnPlane && derivative.upper < 0 { side = .negative }
            else if cell.upper == bounds.upper && endsOnPlane && derivative.lower > 0 { side = .negative }
            else if cell.upper == bounds.upper && endsOnPlane && derivative.upper < 0 { side = .positive }
            else { side = nil }
            if let side {
                guard retainedSide == nil || retainedSide == side else {
                    throw failure(.classificationFailure,
                        "Round Sweep retained span crosses its original split plane.", featureID)
                }
                retainedSide = side
                continue
            }
            let middle = cell.lower + 0.5 * (cell.upper - cell.lower)
            guard cell.depth < 32, middle > cell.lower, middle < cell.upper else {
                throw failure(.classificationFailure,
                    "Round Sweep original side remains unresolved at its split contact.", featureID)
            }
            stack.append((middle, cell.upper, cell.depth + 1))
            stack.append((cell.lower, middle, cell.depth + 1))
        }
        guard let retainedSide else {
            throw failure(.classificationFailure,
                "Round Sweep original side proof produced no admitted span.", featureID)
        }
        return retainedSide
    }

    /// The surface `row` sweeps turning about `corner`'s axis by its angle, rational quadratic in
    /// the turn (two pieces past a right angle), bounded by `row`, the turned row and the arcs its
    /// ends trace. An original axis end retains a collapsed face-local UV use.
    private func revolvedPatch(
        _ row: BSplineCurve3D, about corner: RoundCorner, orientation: Orientation, stableID: String,
        patches: ExactLinearSectionSweepFacePatchBuilder,
        admission: GeometryConversionAdmission
    ) throws -> BRepSewingFacePatch {
        let pieces = corner.angle > 0.5 * Double.pi + tolerance.angle ? 2 : 1
        let step = corner.angle / Double(pieces)
        func turned(_ offset: Vector3D, by angle: Double) -> Vector3D {
            offset * cos(angle) + corner.axis.cross(offset) * sin(angle)
        }
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        var remainingAxisComponents = 65_536
        func isOriginalAxisPoint(_ point: Point3D) throws -> Bool {
            try OriginalPointLineIncidence().contains(point: point, origin: corner.point,
                direction: corner.axis, consumeWork: {
                    try admission.chargeWork()
                    guard remainingAxisComponents > 0 else {
                        throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                            tolerance: tolerance, message: "Round Sweep axis incidence exhausted its component budget.")
                    }
                    remainingAxisComponents -= 1
                })
        }
        for piece in 0...pieces {
            try admission.chargeWork()
            let bytes = row.controlPoints.count.multipliedReportingOverflow(by: MemoryLayout<Point3D>.stride)
            guard !bytes.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Round Sweep row payload overflows.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
            let angle = step * Double(piece)
            rows.append(try row.controlPoints.map { point in
                try admission.chargeWork()
                if piece == 0 { return point }
                if try isOriginalAxisPoint(point) { return point }
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                return center + turned(point - center, by: angle)
            })
            weights.append(row.weights)
            guard piece < pieces else { break }
            try admission.chargeStorage(bytes: bytes.partialValue)
            rows.append(try row.controlPoints.map { point in
                try admission.chargeWork()
                if try isOriginalAxisPoint(point) { return point }
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                let offset = point - center
                return center + (turned(offset, by: angle) + turned(offset, by: angle + step)) * (1 / (1 + cos(step)))
            })
            let weightBytes = row.weights.count.multipliedReportingOverflow(by: MemoryLayout<Double>.stride)
            guard !weightBytes.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Round Sweep weight payload overflows.")
            }
            try admission.chargeStorage(bytes: weightBytes.partialValue)
            weights.append(try row.weights.map { value in
                try admission.chargeWork()
                return value * cos(0.5 * step)
            })
        }
        let vKnots = pieces == 1 ? [0.0, 0, 0, 1, 1, 1] : [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        let surface = BSplineSurface3D(uDegree: row.degree, vDegree: 2, uKnots: row.knots, vKnots: vKnots,
                                       controlPoints: rows, weights: weights)
        try surface.validate(tolerance: tolerance)
        let u = try patches.closedBounds(surface.uDomain)
        let v = try patches.closedBounds(surface.vDomain)
        let host = Surface3D.bSpline(surface)
        let boundary: [(curve: BSplineCurve3D, reversed: Bool, pcurve: SurfaceParameterCurve, name: String)] = [
            (try surface.uIsoparametricCurve(atV: v.lower, tolerance: tolerance), false,
             .constantV(v: v.lower, uStart: u.lower, uEnd: u.upper), "bottom"),
            (try surface.vIsoparametricCurve(atU: u.upper, tolerance: tolerance), false,
             .constantU(u: u.upper, vStart: v.lower, vEnd: v.upper), "end"),
            (try surface.uIsoparametricCurve(atV: v.upper, tolerance: tolerance), true,
             .constantV(v: v.upper, uStart: u.upper, uEnd: u.lower), "top"),
            (try surface.vIsoparametricCurve(atU: u.lower, tolerance: tolerance), true,
             .constantU(u: u.lower, vStart: v.upper, vEnd: v.lower), "start")]
        let edges = try boundary.map { side in
            try patches.tensorBoundaryEdge(curve: side.curve, reversed: side.reversed, surface: host,
                pcurve: side.pcurve, stableID: "\(stableID):\(side.name)")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): source-only general pole construction now retains
        // the exact tensor and original singular UV uses. Production Round Sweep publication
        // still requires the deferred whole-face pole, sewing and solid behavioral evidence;
        // do not infer completion from the original coefficient admission alone.
        let patch = BRepSewingFacePatch(stableID: stableID, surface: host, orientation: orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func cap(
        _ rows: [[BSplineCurve3D]], normal: Vector3D, outerWinding: Double, advance: Double, atEnd: Bool,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let stableID = atEnd ? "sweep:cap:end" : "sweep:cap:start"
        let reversed = !atEnd
        let boundarySign = reversed ? -outerWinding : outerWinding
        let desiredSign = (atEnd ? 1.0 : -1.0) * (advance > 0 ? 1 : -1)
        guard let first = rows.first?.first else { throw FeatureEvaluationError.emptyResult("A mitred sweep's cap has no section span.") }
        let surface = Surface3D.plane(Plane3D(
            origin: try Curve3D.bSpline(first).point(at: patches.closedBounds(first.domain).lower, tolerance: tolerance),
            normal: normal * boundarySign
        ))
        let loops = try rows.enumerated().map { loopIndex, loop in
            let prefix = loopIndex == 0 ? stableID : "\(stableID):inner:\(loopIndex - 1)"
            let ordered = reversed ? Array(loop.indices.reversed()) : Array(loop.indices)
            return BRepSewingLoop(stableID: "\(prefix):loop", role: loopIndex == 0 ? .outer : .inner, edges: try ordered.map { index in
                try patches.exactEdge(loop[index], reversed: reversed,
                    surfaceParameterCurve: try patches.planarPcurve(loop[index], reversed: reversed, on: surface),
                    stableID: "\(prefix):edge:\(index)")
            })
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: surface,
            orientation: boundarySign == desiredSign ? .forward : .reversed, loops: loops)
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}

/// A round corner: the arm before it, its point, the unit axis it turns about (across both arms),
/// the angle it turns by, and the unit inner direction across the arm before it carried back to
/// the section's frame.
private struct RoundCorner {
    let before: Int
    let point: Point3D
    let axis: Vector3D
    let angle: Double
    let inner: Vector3D
}

/// A stretch of a sweep path between corners or where it turns from straight to curved: its
/// spans, its ends and its unit tangents there.
private struct Leg {
    var spans: [ExactBSplineCurveSpan]
    let isStraight: Bool
    var start: Point3D
    var end: Point3D
    var startTangent: Vector3D
    var endTangent: Vector3D

    /// The leg run the other way.
    func reversed(tolerance: ModelingTolerance) throws -> Leg {
        Leg(spans: try spans.reversed().map { try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: tolerance), tolerance: tolerance) },
            isStraight: isStraight, start: end, end: start, startTangent: endTangent * -1, endTangent: startTangent * -1)
    }
}

/// A rotation as a 3 × 3 matrix, composed from least rotations between unit directions.
private struct Rotation {
    let rows: [[Double]]

    static let identity = Rotation(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    init(rows: [[Double]]) {
        self.rows = rows
    }

    /// The least rotation taking unit `a` to unit `b`: `R v = (a·b) v + (a×b)×v + (a×b)((a×b)·v)/(1 + a·b)`.
    init(from a: Vector3D, to b: Vector3D, tolerance: ModelingTolerance) throws {
        let c = a.cross(b), d = a.dot(b)
        guard 1 + d > tolerance.relative else {
            throw KernelError(phase: .evaluation, code: .sweepRoundCornerUnavailable, tolerance: tolerance,
                message: "A sweep path turns back on itself at a corner.")
        }
        let k = 1 / (1 + d)
        let columns = [Vector3D.unitX, .unitY, .unitZ].map { v in v * d + c.cross(v) + c * (c.dot(v) * k) }
        rows = (0..<3).map { r in columns.map { [$0.x, $0.y, $0.z][r] } }
    }

    /// The rotation taking the standard axes to the orthonormal frame's (its columns).
    init(frame: (Vector3D, Vector3D, Vector3D)) {
        let columns = [frame.0, frame.1, frame.2]
        rows = (0..<3).map { r in columns.map { [$0.x, $0.y, $0.z][r] } }
    }

    func applied(to v: Vector3D) -> Vector3D {
        Vector3D(
            x: rows[0][0] * v.x + rows[0][1] * v.y + rows[0][2] * v.z,
            y: rows[1][0] * v.x + rows[1][1] * v.y + rows[1][2] * v.z,
            z: rows[2][0] * v.x + rows[2][1] * v.y + rows[2][2] * v.z
        )
    }

    /// `self` after `other`.
    func composed(with other: Rotation) -> Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + rows[r][$1] * other.rows[$1][c] } } })
    }

    var transposed: Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in rows[c][r] } })
    }

    func isIdentity(tolerance: ModelingTolerance) -> Bool {
        (0..<3).allSatisfy { r in (0..<3).allSatisfy { c in abs(rows[r][c] - (r == c ? 1 : 0)) <= max(tolerance.angle, 1e-12) } }
    }
}
