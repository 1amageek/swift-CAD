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
    package let terminalSectionCollapsed: Bool
    package let admission: GeometryConversionAdmission

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
        tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil
    ) throws {
        let admission = try admission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        try self.init(sectionLoops: try ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission).profileLoopSpans(from: profile),
                      sectionIsClosed: true, profilePlane: profile.plane, pathSegments: pathSegments, sweep: sweep,
                      values: values, tolerance: tolerance, admission: admission)
    }

    /// The plan for a resolved section: a profile's loops, or a curve as one open or closed loop.
    package init(
        section: ResolvedModelingSection,
        pathSegments: [EvaluatedCurvePathSegment],
        sweep: SweepFeature,
        values: SweepOptionValues,
        tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil
    ) throws {
        let admission = try admission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        let spans = ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission)
        switch section {
        case .profile, .face, .constructedRegion:
            try self.init(sectionLoops: try spans.loopSpans(from: section), sectionIsClosed: true,
                          profilePlane: try section.plane(), pathSegments: pathSegments, sweep: sweep, values: values, tolerance: tolerance, admission: admission)
        case .curve(let curve):
            try self.init(sectionLoops: [try spans.sectionSpans(from: curve)], sectionIsClosed: curve.isClosed,
                          profilePlane: try section.plane(), pathSegments: pathSegments, sweep: sweep, values: values, tolerance: tolerance, admission: admission)
        }
    }

    private init(
        sectionLoops loops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSegments: [EvaluatedCurvePathSegment],
        sweep: SweepFeature,
        values: SweepOptionValues,
        tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil
    ) throws {
        try tolerance.validate()
        let admission = try admission ?? CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission()
        try admission.chargeWork()
        guard sweep.options.resultKind == .sheet || sectionIsClosed else {
            throw Self.failure("A solid twisted sweep needs a closed section.", tolerance)
        }
        try SweepEvaluationCapabilities().validateStaticOptions(sweep.options, tolerance: tolerance)
        guard let allowance = values.approximationTolerance, allowance.isFinite, allowance > 0,
              values.endScale.isFinite, values.endScale >= 0, sweep.guides.isEmpty,
              sweep.options.booleanOperation == .newBody else {
            throw Self.failure("Certified twist requires an explicit positive allowance, a nonnegative original linear scale, no guides and new-body output.", tolerance)
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance, admission: admission)
        let originalPath = try spanBuilder.pathSpans(from: pathSegments)
        // Whole original incidence and directed speed prove the linear locus;
        // no construction control net establishes the original path law.
        guard originalPath.count == 1, let path = originalPath.first,
              try OriginalSweepPathLinearity(tolerance: tolerance, admission: admission).isStraight(originalPath) else {
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
        let controlCount = loops.reduce(0) { total, loop in
            total + loop.reduce(0) { $0 + $1.curve.controlPointCount }
        }
        // Bounded work before tensor or topology allocation. These are refusal
        // ceilings, not a geometric sampling density or a quality fallback.
        guard spanCount > 0, spanCount <= 4096, controlCount <= 65536 else {
            throw Self.exhausted(tolerance)
        }
        let maximumIntervals = min(4096 / spanCount, 262144 / max(5 * controlCount, 1))
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
        let originalPathSource = try OriginalCurveConstructionSource(chart: path.originalChart,
            domain: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, admission: admission)
        let originalStart = try originalPathSource.enclosure(over: ScalarInterval(lower: 0, upper: 0),
            tolerance: tolerance, admission: admission).position
        let originalEnd = try originalPathSource.enclosure(over: ScalarInterval(lower: 1, upper: 1),
            tolerance: tolerance, admission: admission).position
        let arithmetic = try CertifiedTwistCoordinates(start: originalStart, fullEnd: originalEnd,
            fraction: values.distanceFraction, plane: sourcePlane, tolerance: tolerance, admission: admission)
        var originalSectionError = 0.0
        for loop in loops {
            for span in loop {
                try admission.chargeWork()
                originalSectionError = max(originalSectionError,
                    span.correspondence.guarantee?.positionErrorUpperBound ?? 0)
            }
        }
        var radius = 0.0
        for loop in loops {
            for span in loop {
                for point in span.curve.controlPoints {
                    radius = max(radius, try arithmetic.radialBound(point))
                }
            }
        }
        radius = (OutwardScalarInterval.exact(radius) + .exact(originalSectionError)).upper
        guard radius.isFinite else { throw Self.exhausted(tolerance) }
        try Self.retain(positions.count - 1, of: Int.self, admission: admission, tolerance: tolerance)
        var divisions = Array(repeating: 1, count: positions.count - 1)
        for index in divisions.indices {
            while true {
                try admission.chargeWork()
                let delta = (OutwardScalarInterval.exact(angles[index + 1]) - .exact(angles[index]))
                    * .exact(1 / Double(divisions[index]))
                let remainder = Self.remainder(radius: (OutwardScalarInterval.exact(radius) * .exact(max(1, values.endScale))).upper, delta: delta)
                if remainder <= allowance * 0.25, delta.absoluteUpperBound <= 0.5 { break }
                guard divisions[index] <= maximumIntervals / 2 else { throw Self.exhausted(tolerance) }
                divisions[index] *= 2
            }
        }
        guard divisions.reduce(0, +) <= maximumIntervals else { throw Self.exhausted(tolerance) }
        let intervalCount = divisions.reduce(0, +)
        try Self.retain(loops.count, of: [[BSplineSurface3D]].self, admission: admission, tolerance: tolerance)
        var built: [[[BSplineSurface3D]]] = []
        built.reserveCapacity(loops.count)
        for _ in loops {
            try admission.chargeWork()
            try Self.retain(intervalCount, of: [BSplineSurface3D].self, admission: admission, tolerance: tolerance)
            var intervals: [[BSplineSurface3D]] = []
            intervals.reserveCapacity(intervalCount)
            built.append(intervals)
        }
        try Self.retain(intervalCount, of: ExactBSplineCurveSpan.self, admission: admission, tolerance: tolerance)
        var paths: [ExactBSplineCurveSpan] = []
        paths.reserveCapacity(intervalCount)
        var maximumError = 0.0
        for lawIndex in divisions.indices {
            let count = divisions[lawIndex]
            let lawStart = OutwardScalarInterval.exact(positions[lawIndex])
            let lawWidth = OutwardScalarInterval.exact(positions[lawIndex + 1]) - lawStart
            let angleStart = OutwardScalarInterval.exact(angles[lawIndex])
            let angleWidth = OutwardScalarInterval.exact(angles[lawIndex + 1]) - angleStart
            for index in 0..<count {
                try admission.chargeWork()
                try Self.retain(30, of: OutwardScalarInterval.self, admission: admission, tolerance: tolerance)
                try admission.chargeWork(30)
                let lowerRatio = Double(index) / Double(count)
                let upperRatio = Double(index + 1) / Double(count)
                // Dyadic subdivision makes these ratios exactly representable.
                let s0 = index == 0 ? lawStart : lawStart + lawWidth * .exact(lowerRatio)
                let s1 = index + 1 == count ? .exact(positions[lawIndex + 1]) : lawStart + lawWidth * .exact(upperRatio)
                let a0 = index == 0 ? angleStart : angleStart + angleWidth * .exact(lowerRatio)
                let a1 = index + 1 == count ? .exact(angles[lawIndex + 1]) : angleStart + angleWidth * .exact(upperRatio)
                let delta = angleWidth * .exact(1 / Double(count))
                let width = lawWidth * .exact(1 / Double(count))
                let t0 = try CertifiedRotationTrigonometry.evaluate(a0, tolerance: tolerance, consumeWork: { try admission.chargeWork() })
                let t1 = try CertifiedRotationTrigonometry.evaluate(a1, tolerance: tolerance, consumeWork: { try admission.chargeWork() })
                let remainder = Self.remainder(radius: (OutwardScalarInterval.exact(radius) * .exact(max(1, values.endScale))).upper, delta: delta)
                let third = OutwardScalarInterval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)
                let cosine = [t0.cosine, t0.cosine - t0.sine * delta * third,
                              t1.cosine + t1.sine * delta * third, t1.cosine]
                let sine = [t0.sine, t0.sine + t0.cosine * delta * third,
                            t1.sine - t1.cosine * delta * third, t1.sine]
                let growth = OutwardScalarInterval.exact(values.endScale) - .exact(1)
                let scales = [OutwardScalarInterval.exact(1) + growth * s0,
                    OutwardScalarInterval.exact(1) + growth * s1]
                func product(_ coefficients: [OutwardScalarInterval]) -> [OutwardScalarInterval] {
                    [coefficients[0] * scales[0],
                     coefficients[1] * scales[0] * .exact(0.75) + coefficients[0] * scales[1] * .exact(0.25),
                     coefficients[2] * scales[0] * .exact(0.5) + coefficients[1] * scales[1] * .exact(0.5),
                     coefficients[3] * scales[0] * .exact(0.25) + coefficients[2] * scales[1] * .exact(0.75),
                     coefficients[3] * scales[1]]
                }
                let scaledCosine = product(cosine), scaledSine = product(sine)
                let station = (0..<5).map { s0 + width * .exact(Double($0) / 4) }
                let scale = (0..<5).map { scales[0] + (scales[1] - scales[0]) * .exact(Double($0) / 4) }
                // A <= 0.5-radian interval has a rotation approximation error
                // below 1/4; coefficient uncertainty must preserve this margin.
                guard cosine.allSatisfy({ $0.isFinite && $0.width < 0.01 }),
                      sine.allSatisfy({ $0.isFinite && $0.width < 0.01 }) else {
                    throw Self.failure("Rotation coefficients cannot certify a nonsingular transform.", tolerance)
                }
                for (loopIndex, spans) in loops.enumerated() {
                    try Self.retain(spans.count, of: BSplineSurface3D.self, admission: admission, tolerance: tolerance)
                    var row: [BSplineSurface3D] = []
                    row.reserveCapacity(spans.count)
                    for span in spans {
                        try admission.chargeWork()
                        try Self.retain(5, of: [Point3D].self, admission: admission, tolerance: tolerance)
                        var controls: [[Point3D]] = []
                        controls.reserveCapacity(5)
                        var numeric = 0.0
                        for j in 0..<5 {
                            try Self.retain(span.curve.controlPointCount, of: Point3D.self, admission: admission, tolerance: tolerance)
                            var controlRow: [Point3D] = []
                            controlRow.reserveCapacity(span.curve.controlPointCount)
                            for point in span.curve.controlPoints {
                                let enclosure = try arithmetic.transformed(point, station: station[j],
                                    cosine: scaledCosine[j], sine: scaledSine[j], scale: scale[j])
                                let terminal = values.endScale == 0 && lawIndex == divisions.count - 1 && index + 1 == count && j == 4
                                try Self.retain(3, of: Double.self, admission: admission, tolerance: tolerance)
                                let chosen: [Double]
                                if terminal {
                                    chosen = try arithmetic.pathPoint(station: s1).map(\.midpoint)
                                } else {
                                    chosen = enclosure.map(\.midpoint)
                                }
                                let error = zip(enclosure, chosen).reduce(OutwardScalarInterval.exact(0)) {
                                    $0 + .exact(($1.0 - .exact($1.1)).absoluteUpperBound)
                                }.upper
                                numeric = max(numeric, error)
                                controlRow.append(Point3D(x: chosen[0], y: chosen[1], z: chosen[2]))
                            }
                            controls.append(controlRow)
                        }
                        let sourceError = OutwardScalarInterval.exact(span.correspondence.guarantee?.positionErrorUpperBound ?? 0)
                            * .exact(max(1, values.endScale))
                        let error = (OutwardScalarInterval.exact(numeric) + .exact(remainder) + sourceError).upper
                        guard error.isFinite, error <= allowance,
                              numeric <= tolerance.distance * 0.125 else {
                            throw Self.failure("Requested positional allowance is below the certified coefficient and Hermite error.", tolerance)
                        }
                        maximumError = max(maximumError, error)
                        try Self.retain(10, of: Double.self, admission: admission, tolerance: tolerance)
                        try Self.retain(5, of: [Double].self, admission: admission, tolerance: tolerance)
                        let surface = BSplineSurface3D(uDegree: span.curve.degree, vDegree: 4,
                            uKnots: span.curve.knots, vKnots: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
                            controlPoints: controls, weights: Array(repeating: span.curve.weights, count: 5))
                        try Surface3D.bSpline(surface).validateOriginalSource(tolerance: tolerance,
                            remainingSourceDepth: admission.remainingSourceDepth,
                            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                            consumeWork: { _ in try admission.chargeWork() },
                            consumeStorage: { try admission.chargeStorage(bytes: $0) })
                        row.append(surface)
                    }
                    built[loopIndex].append(row)
                }
                try Self.retain(4, of: Double.self, admission: admission, tolerance: tolerance)
                try Self.retain(2, of: Point3D.self, admission: admission, tolerance: tolerance)
                paths.append(try ExactBSplineCurveSpan(curve: BSplineCurve3D(degree: 1,
                    knots: [0, 0, 1, 1], controlPoints: [start + direction * s0.midpoint, start + direction * s1.midpoint]), tolerance: tolerance, admission: admission))
            }
        }
        profileSpanLoops = loops
        self.sectionIsClosed = sectionIsClosed
        self.profilePlane = profilePlane
        pathSpans = paths
        surfaces = built
        positionErrorUpperBound = maximumError
        terminalSectionCollapsed = values.endScale == 0
        self.admission = admission
    }

    private static func retain<T>(_ count: Int, of: T.Type,
        admission: GeometryConversionAdmission, tolerance: ModelingTolerance) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else { throw exhausted(tolerance) }
        try admission.chargeStorage(bytes: bytes.partialValue)
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
