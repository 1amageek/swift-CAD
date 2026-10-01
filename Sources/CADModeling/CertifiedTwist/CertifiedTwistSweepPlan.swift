import CADCore
import CADGeometry
import CADIR

/// Request-local proof and geometry, shared by preflight and actual evaluation.
package struct CertifiedTwistSweepPlan: Sendable {
    package let profileSpanLoops: [[ExactBSplineCurveSpan]]
    /// Whether the section's loops close (a profile, or a closed curve); an open curve sweeps a sheet.
    package let sectionIsClosed: Bool
    package let pathSpans: [ExactBSplineCurveSpan]
    /// Indexed by loop, then axial interval, then profile span.
    package let surfaces: [[[BSplineSurface3D]]]
    package let positionErrorUpperBound: Double
    package let profilePlane: SketchPlane

    /// Whether the options ask for a certified twist: a twist law, or an allowance with a twist
    /// angle that is not a literal zero. An allowance alone asks for no twist; it bounds whichever
    /// approximation a sweep needs. A twist without an allowance is refused by capability planning.
    package static func requested(_ options: SweepOptions) -> Bool {
        if options.twistLaw != nil { return true }
        guard options.approximationTolerance != nil else { return false }
        if case .constant(let angle) = options.twistAngle, angle.value == 0 { return false }
        return true
    }

    package init(
        profile: Profile,
        pathSegments: [EvaluatedCurvePathSegment],
        sweep: SweepFeature,
        values: SweepOptionValues,
        tolerance: ModelingTolerance
    ) throws {
        try self.init(sectionLoops: try ExactBSplineCurveSpanBuilder(tolerance: tolerance).profileLoopSpans(from: profile),
                      sectionIsClosed: true, profilePlane: profile.plane, pathSegments: pathSegments, sweep: sweep,
                      values: values, tolerance: tolerance)
    }

    /// The plan for a resolved section: a profile's loops, or a curve as one open or closed loop.
    package init(
        section: ResolvedModelingSection,
        pathSegments: [EvaluatedCurvePathSegment],
        sweep: SweepFeature,
        values: SweepOptionValues,
        tolerance: ModelingTolerance
    ) throws {
        let spans = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        switch section {
        case .profile(let profile, _):
            try self.init(sectionLoops: try spans.profileLoopSpans(from: profile), sectionIsClosed: true,
                          profilePlane: profile.plane, pathSegments: pathSegments, sweep: sweep, values: values, tolerance: tolerance)
        case .curve(let curve):
            try self.init(sectionLoops: [try spans.sectionSpans(from: curve)], sectionIsClosed: curve.isClosed,
                          profilePlane: try section.plane(), pathSegments: pathSegments, sweep: sweep, values: values, tolerance: tolerance)
        }
    }

    private init(
        sectionLoops loops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSegments: [EvaluatedCurvePathSegment],
        sweep: SweepFeature,
        values: SweepOptionValues,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard sweep.options.resultKind == .sheet || sectionIsClosed else {
            throw Self.failure("A solid twisted sweep needs a closed section.", tolerance)
        }
        try SweepEvaluationCapabilities().validateStaticOptions(sweep.options, tolerance: tolerance)
        guard let allowance = values.approximationTolerance, allowance.isFinite, allowance > 0,
              values.endScale == 1, sweep.guides.isEmpty,
              sweep.options.booleanOperation == .newBody else {
            throw Self.failure("Certified twist requires an explicit positive allowance, unit scale, no guides and new-body output.", tolerance)
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        let originalPath = try spanBuilder.pathSpans(from: pathSegments)
        // A two-control rational degree-one curve traces exactly one line.
        // No sampled or tolerance-flattened curved path is admitted.
        guard originalPath.count == 1, let path = originalPath.first,
              path.curve.degree == 1, path.curve.controlPointCount == 2 else {
            throw Self.failure("Certified twist initially requires one exact linear path span.", tolerance)
        }
        let start = path.startPoint
        let fullEnd = path.endPoint
        let end = start + (fullEnd - start) * values.distanceFraction
        let direction = end - start
        let plane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance)
        let normal = try direction.normalized(tolerance: tolerance.distance)
        guard normal.cross(plane.plane.normal).length <= tolerance.angle else {
            throw Self.failure("Certified twist requires a profile-normal straight path.", tolerance)
        }
        let spanCount = loops.reduce(0) { $0 + $1.count }
        let controlCount = loops.flatMap { $0 }.reduce(0) { $0 + $1.curve.controlPointCount }
        // Bounded work before tensor or topology allocation. These are refusal
        // ceilings, not a geometric sampling density or a quality fallback.
        guard spanCount > 0, spanCount <= 4096, controlCount <= 65536 else {
            throw Self.exhausted(tolerance)
        }
        let maximumIntervals = min(4096 / spanCount, 262144 / max(4 * controlCount, 1))
        guard maximumIntervals > 0 else { throw Self.exhausted(tolerance) }
        let positions = values.twistPositions
        let angles = values.twistAngles
        guard positions.count == angles.count, positions.count >= 2,
              angles.allSatisfy({ $0.isFinite && abs($0) <= 16 }) else {
            throw Self.failure("Certified twist requires finite source angles in [-16, 16] radians.", tolerance)
        }
        let sourcePlane: Plane3D
        switch profilePlane {
        case .xy: sourcePlane = Plane3D(origin: .origin, normal: .unitZ)
        case .yz: sourcePlane = Plane3D(origin: .origin, normal: .unitX)
        case .zx: sourcePlane = Plane3D(origin: .origin, normal: .unitY)
        case .plane(let value): sourcePlane = value
        }
        let arithmetic = try CertifiedTwistCoordinates(start: start, fullEnd: fullEnd,
            fraction: values.distanceFraction, plane: sourcePlane, tolerance: tolerance)
        var radius = 0.0
        for span in loops.flatMap({ $0 }) {
            for point in span.curve.controlPoints {
                radius = max(radius, arithmetic.radialBound(point))
            }
        }
        guard radius.isFinite else { throw Self.exhausted(tolerance) }
        var divisions = Array(repeating: 1, count: positions.count - 1)
        for index in divisions.indices {
            while true {
                let delta = (OutwardScalarInterval.exact(angles[index + 1]) - .exact(angles[index]))
                    * .exact(1 / Double(divisions[index]))
                let remainder = Self.remainder(radius: radius, delta: delta)
                if remainder <= allowance * 0.25, delta.absoluteUpperBound <= 0.5 { break }
                guard divisions[index] <= maximumIntervals / 2 else { throw Self.exhausted(tolerance) }
                divisions[index] *= 2
            }
        }
        guard divisions.reduce(0, +) <= maximumIntervals else { throw Self.exhausted(tolerance) }
        var built: [[[BSplineSurface3D]]] = loops.map { _ in [] }
        var paths: [ExactBSplineCurveSpan] = []
        var maximumError = 0.0
        for lawIndex in divisions.indices {
            let count = divisions[lawIndex]
            let lawStart = OutwardScalarInterval.exact(positions[lawIndex])
            let lawWidth = OutwardScalarInterval.exact(positions[lawIndex + 1]) - lawStart
            let angleStart = OutwardScalarInterval.exact(angles[lawIndex])
            let angleWidth = OutwardScalarInterval.exact(angles[lawIndex + 1]) - angleStart
            for index in 0..<count {
                let lowerRatio = Double(index) / Double(count)
                let upperRatio = Double(index + 1) / Double(count)
                // Dyadic subdivision makes these ratios exactly representable.
                let s0 = index == 0 ? lawStart : lawStart + lawWidth * .exact(lowerRatio)
                let s1 = index + 1 == count ? .exact(positions[lawIndex + 1]) : lawStart + lawWidth * .exact(upperRatio)
                let a0 = index == 0 ? angleStart : angleStart + angleWidth * .exact(lowerRatio)
                let a1 = index + 1 == count ? .exact(angles[lawIndex + 1]) : angleStart + angleWidth * .exact(upperRatio)
                let delta = angleWidth * .exact(1 / Double(count))
                let width = lawWidth * .exact(1 / Double(count))
                let t0 = try CertifiedRotationTrigonometry.evaluate(a0, tolerance: tolerance)
                let t1 = try CertifiedRotationTrigonometry.evaluate(a1, tolerance: tolerance)
                let remainder = Self.remainder(radius: radius, delta: delta)
                let third = OutwardScalarInterval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)
                let cosine = [t0.cosine, t0.cosine - t0.sine * delta * third,
                              t1.cosine + t1.sine * delta * third, t1.cosine]
                let sine = [t0.sine, t0.sine + t0.cosine * delta * third,
                            t1.sine - t1.cosine * delta * third, t1.sine]
                let station = [s0, s0 + width * third, s1 - width * third, s1]
                // A <= 0.5-radian interval has a rotation approximation error
                // below 1/4; coefficient uncertainty must preserve this margin.
                guard cosine.allSatisfy({ $0.isFinite && $0.width < 0.01 }),
                      sine.allSatisfy({ $0.isFinite && $0.width < 0.01 }) else {
                    throw Self.failure("Rotation coefficients cannot certify a nonsingular transform.", tolerance)
                }
                for (loopIndex, spans) in loops.enumerated() {
                    var row: [BSplineSurface3D] = []
                    for span in spans {
                        var controls: [[Point3D]] = []
                        var numeric = 0.0
                        for j in 0..<4 {
                            var controlRow: [Point3D] = []
                            for point in span.curve.controlPoints {
                                let enclosure = arithmetic.transformed(point, station: station[j], cosine: cosine[j], sine: sine[j])
                                let chosen = enclosure.map(\.midpoint)
                                let error = zip(enclosure, chosen).reduce(OutwardScalarInterval.exact(0)) {
                                    $0 + .exact(($1.0 - .exact($1.1)).absoluteUpperBound)
                                }.upper
                                numeric = max(numeric, error)
                                controlRow.append(Point3D(x: chosen[0], y: chosen[1], z: chosen[2]))
                            }
                            controls.append(controlRow)
                        }
                        let error = (OutwardScalarInterval.exact(numeric) + .exact(remainder)).upper
                        guard error.isFinite, error <= allowance,
                              numeric <= tolerance.distance * 0.125 else {
                            throw Self.failure("Requested positional allowance is below the certified coefficient and Hermite error.", tolerance)
                        }
                        maximumError = max(maximumError, error)
                        let surface = BSplineSurface3D(uDegree: span.curve.degree, vDegree: 3,
                            uKnots: span.curve.knots, vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                            controlPoints: controls, weights: Array(repeating: span.curve.weights, count: 4))
                        try surface.validate(tolerance: tolerance)
                        row.append(surface)
                    }
                    built[loopIndex].append(row)
                }
                paths.append(try ExactBSplineCurveSpan(curve: BSplineCurve3D(degree: 1,
                    knots: [0, 0, 1, 1], controlPoints: [start + direction * s0.midpoint, start + direction * s1.midpoint]), tolerance: tolerance))
            }
        }
        profileSpanLoops = loops
        self.sectionIsClosed = sectionIsClosed
        self.profilePlane = profilePlane
        pathSpans = paths
        surfaces = built
        positionErrorUpperBound = maximumError
    }

    private static func remainder(radius: Double, delta: OutwardScalarInterval) -> Double {
        let a = OutwardScalarInterval.exact(delta.absoluteUpperBound)
        // Conservative vector bound: R |delta|^4 / 128 > 2 R |delta|^4 / 384.
        return (.exact(radius) * a * a * a * a * .exact(1.0 / 128)).upper
    }

    package static func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .sweepTwistUnavailable, tolerance: tolerance, message: message)
    }

    private static func exhausted(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Certified twist exceeds 4096 patches or 262144 tensor controls.")
    }
}

/// Outward Rodrigues evaluation encloses normalization and all coefficient math.
private struct CertifiedTwistCoordinates {
    typealias I = OutwardScalarInterval
    let start: [I]
    let advance: [I]
    let anchor: [I]
    let axis: [I]

    init(start: Point3D, fullEnd: Point3D, fraction: Double, plane: Plane3D, tolerance: ModelingTolerance) throws {
        self.start = Self.values(start)
        advance = zip(Self.values(fullEnd), Self.values(start)).map { ($0 - $1) * .exact(fraction) }
        let squared = advance.reduce(I.exact(0)) { $0 + $1 * $1 }
        let length = I(lower: squared.lower.squareRoot().nextDown, upper: squared.upper.squareRoot().nextUp)
        guard length.isFinite, length.lower > tolerance.distance else {
            throw CertifiedTwistSweepPlan.failure("Sweep axis has no certified positive length.", tolerance)
        }
        axis = try advance.map {
            guard let component = $0.divided(by: length) else {
                throw CertifiedTwistSweepPlan.failure("Sweep axis normalization failed.", tolerance)
            }
            return component
        }
        let planeNormal = [I.exact(plane.normal.x), .exact(plane.normal.y), .exact(plane.normal.z)]
        let offset = zip(Self.values(start), Self.values(plane.origin)).map { $0 - $1 }
        let numerator = zip(planeNormal, offset).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        let denominator = zip(planeNormal, advance).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        guard let ratio = numerator.divided(by: denominator) else {
            throw CertifiedTwistSweepPlan.failure("Sweep axis has no certified intersection with the section plane.", tolerance)
        }
        anchor = zip(Self.values(start), advance).map { $0 - $1 * ratio }
    }

    func radialBound(_ point: Point3D) -> Double {
        zip(Self.values(point), anchor).reduce(I.exact(0)) { $0 + .exact(($1.0 - $1.1).absoluteUpperBound) }.upper
    }

    func transformed(_ point: Point3D, station: I, cosine: I, sine: I) -> [I] {
        let r = zip(Self.values(point), anchor).map { $0 - $1 }
        let projection = zip(axis, r).reduce(I.exact(0)) { $0 + $1.0 * $1.1 }
        let axial = axis.map { $0 * projection }
        let cross = [axis[1] * r[2] - axis[2] * r[1],
                     axis[2] * r[0] - axis[0] * r[2],
                     axis[0] * r[1] - axis[1] * r[0]]
        return (0..<3).map { i in
            start[i] + advance[i] * station + axial[i] + cosine * (r[i] - axial[i]) + sine * cross[i]
        }
    }

    private static func values(_ p: Point3D) -> [I] { [.exact(p.x), .exact(p.y), .exact(p.z)] }
}
