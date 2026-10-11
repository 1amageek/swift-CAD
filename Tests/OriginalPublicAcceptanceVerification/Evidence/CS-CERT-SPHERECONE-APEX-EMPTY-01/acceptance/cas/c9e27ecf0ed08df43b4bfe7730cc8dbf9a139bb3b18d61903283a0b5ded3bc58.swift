#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
import CADCore
@testable import CADGeometry

/// Exercises the actual SSI constructor and the ordinary complete-empty CS authority.
@main struct CertifiedSphereConeApexEmptyAcceptance {
    struct Failure: Error { let line: Int }
    typealias Base = RetainedHostAdapters.OriginalPhysicalAngleScalarDomain
    typealias Value = RetainedHostAdapters.OriginalPhysicalAngleValue
    typealias Source = CertifiedApexSourcePhase.OriginalCertifiedSphereConeApexSnapshot
    typealias Receipt = CertifiedApexSourcePhase.OriginalCertifiedSphereConeApexPlaneSeparationReceipt
    typealias Interval = RetainedHostAdapters.ExactParameterInterval<Value>
    // Exact authored binary input recorded by the independent source worksheet.
    static let authoredHalfAngle = Double(bitPattern: 0x3fddac670561bb50)
    static func require(_ condition: Bool, line: Int = #line) throws {
        if !condition { throw Failure(line: line) }
    }
    static func ledger(work: Int = 8_388_608, bytes: Int = 268_435_456,
        valueDepth: Int = 32, coefficientDepth: Int = 32) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: bytes,
            valueDepth: valueDepth, coefficientDepth: coefficientDepth))
    }
    static func limits(sourceDepth: Int = 1, charts: Int = 1) throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: sourceDepth), maximumTransportDepth: 0,
            maximumCharts: charts, maximumFamilies: 0, maximumIdentityProofs: 0)
    }
    static func equal(_ lhs: Value, _ rhs: Value, field: Base, using a: inout ExactScalarLedger) throws {
        try require(field.compare(lhs, rhs, using: &a) == .equal)
    }
    static func input() throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 1))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 1, y: 0, z: 0),
            axis: .unitZ, halfAngle: authoredHalfAngle))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere, second: cone, tolerance: .standard)
        var selected: CertifiedAnalyticAnalyticIntersectionCurve?
        var components = 0
        for intersection in intersections {
            guard case .curve(let result) = intersection,
                case .analyticAnalytic(let exact) = result.truth,
                case .sphereCone(let curve) = exact.definition,
                curve.componentKind == .apexReducedAngularInterval else { continue }
            components += 1
            if let previous = selected, let old = previous.sphereConeCurve {
                if curve.lowerAngle < old.lowerAngle { selected = exact }
            } else { selected = exact }
        }
        guard components == 2, let selected, let original = selected.sphereConeCurve else {
            throw Failure(line: #line)
        }
        try require(original.lowerAngle == 0 && original.upperAngle == Double.pi)
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower: 0, upper: 1)
        options.surfaceURange = try .init(lower: -2, upper: 2)
        options.surfaceVRange = try .init(lower: -2, upper: 2)
        return (selected.curve, .analytic(.plane(origin: .init(x: 0, y: 0, z: 2), normal: .unitZ)), options)
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456,
            cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            maximumWork = work; maximumBytes = bytes
            self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1; return state.work
            }
            if reached == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = next.partialValue; return state.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10)); divisor /= 10 } while divisor > 0
        putchar(10); fflush(nil)
    }
    static func admitted(_ curve: Curve3D, _ plane: Surface3D, _ options: CurveSurfaceIntersectionOptions,
        _ counter: Counter, sourceDepth: Int = 8, algebraicDepth: Int = 32,
        charts: Int = 262_144) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: options, tolerance: .standard, maximumSpanCount: charts,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: algebraicDepth)
    }
    static func closed<S: Sendable>(_ selection: OriginalParameterSelection<S, Base>, axis: Int,
        lower: Double, upper: Double, using a: inout ExactScalarLedger) throws {
        try require(selection.axes[axis].intervalCount == 1)
        let interval = selection.axes[axis].intervals.first!
        guard case .finite(let lo) = interval.lower, case .finite(let hi) = interval.upper else {
            throw Failure(line: #line)
        }
        try require(!interval.isEmpty && interval.includesLower && interval.includesUpper)
        let f = selection.frame.scalarField
        try equal(lo, f.binary64(exactly: lower, using: &a), field: f, using: &a)
        try equal(hi, f.binary64(exactly: upper, using: &a), field: f, using: &a)
    }
    static func verify(_ result: CurveSurfaceIntersectionResult, options: CurveSurfaceIntersectionOptions) throws {
        guard let reading = result.originalCertifiedApexPlaneExclusion else { throw Failure(line: #line) }
        let owner = reading.original, proof = owner.exclusion, f = proof.field
        var a = try ledger()
        try owner.admitProof(limits: limits(), using: &a)
        try require(reading.isEmpty && !reading.hasPositiveDimensionalSolutions && !reading.hasPositiveDimensionalImage)
        try require(owner.isEmpty && !owner.hasPositiveDimensionalSolutions && !owner.hasPositiveDimensionalImage)
        try require(result.points.isEmpty && result.overlaps.isEmpty && !result.hasPositiveDimensionalSolutions)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let fifteen = try f.integer(15, using: &a), sixteen = try f.integer(16, using: &a)
        let independent = try f.dividing(fifteen, sixteen, using: &a)
        // This strict whole-phase bound excludes every source T, all target UV,
        // every incident, image and fiber. No sampled parent-sphere equality is used.
        try require(f.compare(proof.heightUpperBound, independent, using: &a) == .less)
        try require(f.compare(independent, one, using: &a) == .less
            && f.compare(one, two, using: &a) == .less)
        try require(f.sign(of: proof.signedDistanceUpper, using: &a) == .negative
            && f.compare(proof.signedDistanceLower, proof.signedDistanceUpper, using: &a) == .less)
        try equal(proof.support.lower, zero, field: f, using: &a)
        try equal(proof.support.upper, one, field: f, using: &a)
        try require(proof.source.sourceDepth == 1 && proof.plane.source.sourceDepth == 0)
        let snapshot = proof.source.original, original = snapshot.original
        try require(original.componentKind == .apexReducedAngularInterval
            && original.lowerAngle == 0 && original.upperAngle == Double.pi)
        try require(snapshot.halfAngle.bitPattern == 0x3fddac670561bb50
            && f.originalRadians.bitPattern == snapshot.halfAngle.bitPattern)
        try require(snapshot.apex == .init(x: 1, y: 0, z: 0) && snapshot.axis == .unitZ)
        try require(snapshot.basisU == .unitY && snapshot.basisV == -.unitX)
        try require(snapshot.axialCenter == 0 && snapshot.quadraticC == 0)
        try require(snapshot.slantDenominator > 0 && snapshot.inverseQuadraticCosine > 0
            && snapshot.slantScale > 0 && snapshot.cosine > 0)
        let binary = [snapshot.halfAngle, original.lowerAngle, original.upperAngle,
            snapshot.apex.x, snapshot.apex.y, snapshot.apex.z, snapshot.axis.x, snapshot.axis.y, snapshot.axis.z,
            snapshot.basisU.x, snapshot.basisU.y, snapshot.basisU.z, snapshot.basisV.x, snapshot.basisV.y, snapshot.basisV.z,
            snapshot.axialCenter, snapshot.radialCosine, snapshot.radialSine, snapshot.quadraticA, snapshot.quadraticC,
            snapshot.sine, snapshot.cosine, snapshot.slope, snapshot.slantDenominator,
            snapshot.inverseQuadraticCosine, snapshot.slantScale]
        try require(proof.binaryCoefficients.count == binary.count && proof.physicalCoefficients.count == 4
            && proof.commonEnvelope.count == 27)
        for index in binary.indices {
            try equal(proof.binaryCoefficients[index], f.binary64(exactly: binary[index], using: &a), field: f, using: &a)
        }
        let sine = try f.sine(using: &a), cosine = try f.cosine(using: &a)
        let slope = try f.dividing(sine, cosine, using: &a)
        let quadratic = try f.adding(one, f.multiplying(slope, slope, using: &a), using: &a)
        for (index, expected) in [sine, cosine, slope, quadratic].enumerated() {
            try equal(proof.physicalCoefficients[index], expected, field: f, using: &a)
        }
        func fraction(_ numerator: Int, _ denominator: Int) throws -> Value {
            try f.dividing(f.integer(numerator, using: &a), f.integer(denominator, using: &a), using: &a)
        }
        let denominator = try f.multiplying(quadratic, cosine, using: &a)
        let inverse = try f.dividing(one, denominator, using: &a)
        let scale = try f.multiplying(two, inverse, using: &a)
        // Independent rational worksheet: positive k in (31/64,33/64),
        // c in (7/8,29/32), A=1+k*k, D=A*c, inverse=1/D, scale=2/D.
        // Monotonicity proves the full intervals without re-signing expanded A/D.
        var envelope: [Value] = []
        for (numerator, denominator) in [(7,16),(15,32),(7,8),(29,32),(31,64),(33,64),
            (79,64),(81,64),(1,64),(65,64),(553,512),(2349,2048),(512,553),(1024,553)] {
            envelope.append(try fraction(numerator, denominator))
        }
        envelope += [denominator, inverse, scale, try fraction(1089,2048), try fraction(15,16)]
        for (numerator, denominator) in [(5057,4096),(5185,4096),(35399,32768),(150365,131072),
            (131072,150365),(32768,35399),(262144,150365),(65536,35399)] {
            envelope.append(try fraction(numerator, denominator))
        }
        for index in envelope.indices {
            try equal(proof.commonEnvelope[index], envelope[index], field: f, using: &a)
        }
        // Independent worksheet fractions, not approximate residual acceptance.
        try equal(proof.heightUpperBound, f.dividing(f.integer(31581, using: &a),
            f.integer(35392, using: &a), using: &a), field: f, using: &a)
        try equal(proof.signedDistanceLower, f.subtracting(f.negated(proof.heightUpperBound, using: &a), two, using: &a), field: f, using: &a)
        try equal(proof.signedDistanceUpper, f.subtracting(proof.heightUpperBound, two, using: &a), field: f, using: &a)
        try equal(proof.clearance, f.subtracting(two, proof.heightUpperBound, using: &a), field: f, using: &a)
        try equal(proof.plane.origin[0], zero, field: f, using: &a)
        try equal(proof.plane.origin[1], zero, field: f, using: &a)
        try equal(proof.plane.origin[2], two, field: f, using: &a)
        for axis in 0..<3 { try equal(proof.plane.normal[axis], axis == 2 ? one : zero, field: f, using: &a) }
        try require(owner.support.frame.source.owner === proof.source.owner
            && owner.request.frame.source.owner === proof.source.owner && owner.effective.frame.source.owner === proof.source.owner)
        try require(owner.plane.source.owner === proof.plane.source.owner
            && owner.plane.law.source.owner === proof.plane.source.owner)
        for candidate in [owner.support.frame.scalarField, owner.request.frame.scalarField,
            owner.effective.frame.scalarField, owner.plane.support.frame.scalarField,
            owner.plane.request.frame.scalarField, owner.plane.effective.frame.scalarField] {
            _ = try f.importing(candidate.integer(0, using: &a), using: &a)
        }
        try closed(owner.support, axis: 0, lower: 0, upper: 1, using: &a)
        let range = options.curveRange!
        try closed(owner.request, axis: 0, lower: range.lower, upper: range.upper, using: &a)
        let lower = max(0, range.lower), upper = min(1, range.upper)
        if lower > upper { try require(owner.effective.isEmpty) }
        else { try closed(owner.effective, axis: 0, lower: lower, upper: upper, using: &a) }
        for axis in 0..<2 {
            try require(owner.plane.support.axes[axis].intervalCount == 1)
            let whole = owner.plane.support.axes[axis].intervals.first!
            guard case .negativeInfinity = whole.lower, case .positiveInfinity = whole.upper else {
                throw Failure(line: #line)
            }
            try require(!whole.isEmpty && !whole.includesLower && !whole.includesUpper)
            if let range = axis == 0 ? options.surfaceURange : options.surfaceVRange {
                try closed(owner.plane.request, axis: axis, lower: range.lower, upper: range.upper, using: &a)
                try closed(owner.plane.effective, axis: axis, lower: range.lower, upper: range.upper, using: &a)
            }
        }
        try require(result.originalAngularPlaneRelation == nil && result.originalRevolutionAxisRelation == nil
            && result.originalNativePoints == nil && result.originalNativeRelations == nil
            && result.originalPolynomialPoints == nil && result.originalAffinePoints == nil
            && result.originalCoonsPoints == nil && result.originalExactGeometricRelation == nil
            && result.originalIssuedGeometricRelation == nil && result.originalIssuedNumericalPoints == nil
            && result.originalContainedLiftPlaneFamily == nil)
    }
    static func interval(_ lower: Double, _ upper: Double, includesLower: Bool = true,
        includesUpper: Bool = true, field f: Base, using a: inout ExactScalarLedger) throws -> Interval {
        try .checked(field: f, lower: .finite(f.binary64(exactly: lower, using: &a)),
            upper: .finite(f.binary64(exactly: upper, using: &a)), includesLower: includesLower,
            includesUpper: includesUpper, depth: .init(value: 0, coefficient: 0), using: &a)
    }
    static func resourceFailure(_ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
    }
    static func sourceFailure(_ expected: OriginalSourceIssuanceFailure,
        _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as OriginalSourceIssuanceFailure {
            switch (expected, error) {
            case (.unsupportedRepresentation, .unsupportedRepresentation),
                (.unsupportedCoefficientField, .unsupportedCoefficientField),
                (.sourceDepthLimit, .sourceDepthLimit), (.scalar(.incompatibleDomain), .scalar(.incompatibleDomain)): return
            default: throw error
            }
        }
    }
    static func sourceControls(_ curve: Curve3D, _ plane: Surface3D) throws {
        var a = try ledger()
        let f = try Base(originalRadians: authoredHalfAngle, using: &a), other = try Base(originalRadians: authoredHalfAngle, using: &a)
        let l = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let provider = CertifiedApexSourcePhase.OriginalCertifiedSphereConeApexSnapshotProvider(field: f, tolerance: .standard)
        let source = try DefaultOriginalSourceBindingIssuer(provider: provider).bind(curve, limits: l, using: &a)
        func basis(_ plane: Surface3D, field f: Base, using a: inout ExactScalarLedger) throws
            -> OriginalPlaneBasisReceipt<AngularSourcePhase.OriginalPlaneSnapshot, Base> {
            let target = try DefaultOriginalSourceBindingIssuer(provider:
                AngularSourcePhase.OriginalPlaneSnapshotProvider(tolerance: .standard)).bind(plane, limits: l, using: &a)
            let one = try f.integer(1, using: &a)
            return try DefaultOriginalPlaneBasisIssuer<AngularSourcePhase.OriginalPlaneSnapshot, Base>()
                .issue(source: target, field: f, firstLength: one, normalLength: one, limits: l, using: &a)
        }
        let issuer = CertifiedApexSourcePhase.DefaultOriginalCertifiedSphereConeApexPlaneSeparationIssuer()
        let receipt = try issuer.issue(source: source, plane: basis(plane, field: f, using: &a), limits: l, using: &a)
        try receipt.admitProof(limits: l, using: &a)
        try sourceFailure(.scalar(.incompatibleDomain)) {
            _ = try issuer.issue(source: source, plane: basis(plane, field: other, using: &a), limits: l, using: &a)
        }
        let intersecting = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        try sourceFailure(.unsupportedRepresentation) {
            _ = try issuer.issue(source: source, plane: basis(intersecting, field: f, using: &a), limits: l, using: &a)
        }
        let unrelated = Curve3D.circle(.init(center: .origin, normal: .unitZ, radius: 1))
        try sourceFailure(.unsupportedRepresentation) { _ = try provider.snapshot(unrelated, limits: l, using: &a) }
        let changed = try Base(originalRadians: 0.5, using: &a)
        let changedProvider = CertifiedApexSourcePhase.OriginalCertifiedSphereConeApexSnapshotProvider(field: changed, tolerance: .standard)
        try sourceFailure(.unsupportedCoefficientField) { _ = try changedProvider.snapshot(curve, limits: l, using: &a) }
        try sourceFailure(.sourceDepthLimit) {
            _ = try provider.snapshot(curve, limits: .init(remainingSourceDepth: 0), using: &a)
        }
        for angle in [0.0, Double.nan, Double.infinity] {
            do { _ = try Base(originalRadians: angle, using: &a); throw Failure(line: #line) }
            catch let error as ExactScalarFailure { guard case .invalidSource = error else { throw error } }
        }
        guard case .certifiedIntersection(.sphereCone(let selectedOriginal)) = curve else { throw Failure(line: #line) }
        let originals = try DefaultSurfaceSurfaceIntersector().intersections(first: selectedOriginal.sphereSurface,
            second: selectedOriginal.coneSurface, tolerance: .standard)
        var declined = 0
        for intersection in originals {
            guard case .curve(let result) = intersection, case .analyticAnalytic(let exact) = result.truth,
                case .sphereCone(let otherBranch) = exact.definition,
                otherBranch.componentKind == .apexReducedAngularInterval, otherBranch.lowerAngle == Double.pi else { continue }
            declined += 1
            try require(!CertifiedApexSourcePhase.OriginalCertifiedSphereConeApexSnapshotProvider.supports(exact.curve))
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: 0, upper: 1)
            options.surfaceURange = try .init(lower: -2, upper: 2)
            options.surfaceVRange = try .init(lower: -2, upper: 2)
            let declinedResult = try DefaultCurveSurfaceIntersector().intersectionResult(curve: exact.curve, surface: plane,
                options: options, tolerance: .standard)
            try require(declinedResult.originalCertifiedApexPlaneExclusion == nil)
        }
        try require(declined == 1)
        print("PASS actual source snapshot/whole-phase proof; unsupported nonseparation/profile, foreign physical owner and invalid scalar rejected")
    }
    static func run() async throws {
        let (curve, plane, options) = try input()
#if hasFeature(Embedded)
        let group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "complete"
#else
        let group = CommandLine.arguments[1]
#endif
        func query(_ selected: CurveSurfaceIntersectionOptions) throws -> CurveSurfaceIntersectionResult {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
                options: selected, tolerance: .standard)
        }
        if group == "complete" {
            try verify(query(options), options: options)
            print("PASS complete actualSSI minapex ordinary rich CS: absZ<15/16<1<2; all source tuples/UV/incidents/image/fiber empty")
        } else if group == "dispatch" {
            try require(DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard).isEmpty)
            try verify(admitted(curve, plane, options, Counter()), options: options)
            let counter = Counter()
            let bare = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard, maximumSpanCount: 262_144,
                maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
                maximumAlgebraicDepth: 32)
            try require(bare.isEmpty && counter.totals.work > 0 && counter.totals.bytes > 0)
            print("PASS all four ordinary bare/rich and standard/callback public entries preserve complete-empty authority")
        } else if group == "source" { try sourceControls(curve, plane)
        } else if group == "requests" {
            for control in 0..<7 {
                var selected = options
                if control == 0 { selected.curveRange = try .init(lower: 0.25, upper: 0.5) }
                if control == 1 { selected.curveRange = try .init(lower: 2, upper: 3) }
                if control == 2 { selected.curveRange = try .init(lower: 0, upper: 0) }
                if control == 3 { selected.curveRange = try .init(lower: 1, upper: 1) }
                if control == 4 { selected.surfaceURange = try .init(lower: 0, upper: 0) }
                if control == 5 { selected.surfaceVRange = try .init(lower: 7, upper: 7) }
                if control == 6 { selected.surfaceURange = nil; selected.surfaceVRange = nil }
                try verify(query(selected), options: selected)
            }
            let owner = try query(options).originalCertifiedApexPlaneExclusion!.original
            var a = try ledger()
            let f = owner.exclusion.field, l = try limits()
            let uv = [try interval(-2, 2, field: f, using: &a)]
            for control in 0..<4 {
                let i: Interval
                if control == 0 { i = try interval(0, 1, includesLower: false, includesUpper: false, field: f, using: &a) }
                else if control == 1 { i = try interval(0, 0, includesLower: false, field: f, using: &a) }
                else if control == 2 { i = try .empty(depth: .init(value: 0, coefficient: 0), using: &a) }
                else { i = try interval(0.5, 0.5, field: f, using: &a) }
                let selected = try OriginalCertifiedApexPlaneExclusion.resolve(exclusion: owner.exclusion,
                    curveIntervals: [i], planeIntervals: [uv, uv], limits: l, using: &a)
                try require(selected.isEmpty)
                try require(selected.effective.isEmpty == (control == 1 || control == 2))
                if control == 0 {
                    let effective = selected.effective.axes[0].intervals.first!
                    try require(!effective.includesLower && !effective.includesUpper)
                }
            }
            let foreign = try Base(originalRadians: authoredHalfAngle, using: &a)
            do {
                _ = try OriginalCertifiedApexPlaneExclusion.resolve(exclusion: owner.exclusion,
                    curveIntervals: [interval(0, 1, field: foreign, using: &a)], planeIntervals: [uv, uv], limits: l, using: &a)
                throw Failure(line: #line)
            } catch let error as OriginalDomainIdentityFailure {
                guard case .domain(.scalar(.incompatibleDomain)) = error else { throw error }
            }
            print("PASS closed/open/empty/singleton/source-external requests and same-owner selections; foreign request scalar rejected")
        } else if group == "resources" {
            let baseline = Counter(), result = try admitted(curve, plane, options, baseline)
            try verify(result, options: options)
            let totals = baseline.totals
            try require(totals.work > 1 && totals.bytes > 0)
            logCount("QUERY_WORK", totals.work); logCount("QUERY_STORAGE", totals.bytes)
            let exact = Counter(work: totals.work, bytes: totals.bytes)
            try verify(admitted(curve, plane, options, exact), options: options)
            try require(exact.totals.work == totals.work && exact.totals.bytes == totals.bytes)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(work: totals.work - 1)) }
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(bytes: totals.bytes - 1)) }
            try verify(admitted(curve, plane, options, Counter(), sourceDepth: 1), options: options)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(), sourceDepth: 0) }
            let owner = result.originalCertifiedApexPlaneExclusion!.original, depth = owner.proofDepth
            logCount("ATTAINED_VALUE_DEPTH", depth.value); logCount("ATTAINED_COEFFICIENT_DEPTH", depth.coefficient)
            let attained = max(depth.value, depth.coefficient)
            try verify(admitted(curve, plane, options, Counter(), algebraicDepth: attained), options: options)
            if attained > 0 { try resourceFailure { _ = try admitted(curve, plane, options, Counter(), algebraicDepth: attained - 1) } }
            var a = try ledger()
            try owner.admitProof(limits: limits(charts: 1), using: &a)
            do { try owner.admitProof(limits: limits(charts: 0), using: &a); throw Failure(line: #line) }
            catch let error as OriginalDomainIdentityFailure { guard case .chartLimit = error else { throw error } }
            // An empty contact has no candidate pair. The exact supported count is zero.
            var count = options; count.maximumCandidateCount = 1
            try verify(admitted(curve, plane, count, Counter()), options: count)
            for tick in [1, totals.work / 2] {
                let counter = Counter(cancelAt: tick)
                do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
                catch is CancellationError {}
                try require(counter.totals.work == tick)
            }
            print("PASS measured exact N/N-1 work/storage, attained scalar/source depth, chart1/0, no fabricated positive pair count and entry/mid cancellation")
        } else if group == "readmission" {
            let owner = try query(options).originalCertifiedApexPlaneExclusion!.original
            var a = try ledger()
            try owner.admitProof(limits: limits(), using: &a)
            let work = a.work, bytes = a.storageBytes
            logCount("READMISSION_WORK", work); logCount("READMISSION_STORAGE", bytes)
            var exact = try ledger(work: work, bytes: bytes)
            try owner.admitProof(limits: limits(), using: &exact)
            try require(exact.work == work && exact.storageBytes == bytes)
            for control in 0..<2 {
                var limited = try ledger(work: control == 0 ? work - 1 : work, bytes: control == 1 ? bytes - 1 : bytes)
                do { try owner.admitProof(limits: limits(), using: &limited); throw Failure(line: #line) }
                catch let error as ExactScalarFailure { guard case .resourceLimit = error else { throw error } }
                catch let error as OriginalSourceIssuanceFailure { guard case .scalar(.resourceLimit) = error else { throw error } }
            }
            let depth = owner.proofDepth
            logCount("READMISSION_VALUE_DEPTH", depth.value)
            logCount("READMISSION_COEFFICIENT_DEPTH", depth.coefficient)
            var depthExact = try ledger(valueDepth: depth.value, coefficientDepth: depth.coefficient)
            try owner.admitProof(limits: limits(), using: &depthExact)
            try require(depthExact.valueDepth == depth.value && depthExact.coefficientDepth == depth.coefficient)
            if depth.coefficient > 0 {
                var depthLimited = try ledger(valueDepth: depth.value, coefficientDepth: depth.coefficient - 1)
                do { try owner.admitProof(limits: limits(), using: &depthLimited); throw Failure(line: #line) }
                catch let error as ExactScalarFailure {
                    guard case .resourceLimit(.coefficientDepth) = error else { throw error }
                }
            }
            try sourceFailure(.sourceDepthLimit) { try owner.admitProof(limits: limits(sourceDepth: 0), using: &a) }
            print("PASS retained proof readmission exact N/N-1 work/storage/coefficient depth and sourceDepth1/0 without decomposition or solving")
        } else if group == "cancel-entry" {
            withUnsafeCurrentTask { $0?.cancel() }
            let counter = Counter()
            do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            print("PASS entry cancellation before any exact work or storage")
        } else if group == "cancel-final" {
            let baseline = Counter()
            _ = try admitted(curve, plane, options, baseline)
            let counter = Counter(cancelStorageAt: baseline.totals.bytes)
            do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.bytes == baseline.totals.bytes)
            print("PASS cancellation at final empty publication storage checkpoint")
        } else if group == "cancel-reader" {
            let owner = try query(options).originalCertifiedApexPlaneExclusion!.original
            var a = ExactScalarLedger(limits: try .init(work: 8_388_608, storageBytes: 268_435_456,
                valueDepth: 32, coefficientDepth: 32))
            a.cancel()
            do { try owner.admitProof(limits: limits(), using: &a); throw Failure(line: #line) }
            catch let error as ExactScalarFailure { guard case .cancelled = error else { throw error } }
            try require(a.work == 0 && a.storageBytes == 0)
            print("PASS subsequent independent proof-query cancellation without partial success")
        } else if group == "lifetime" {
            let retained: CurveSurfaceIntersectionResult
            do {
                var (localCurve, localPlane, localOptions) = try input()
                retained = try admitted(localCurve, localPlane, localOptions, Counter())
                localCurve = .circle(.init(center: .origin, normal: .unitZ, radius: 7))
                localPlane = .analytic(.plane(origin: .origin, normal: .unitX))
                localOptions.curveRange = try .init(lower: 0, upper: 0)
                if case .circle(let changed) = localCurve { try require(changed.radius == 7) }
                try require(localPlane != plane)
            }
            let copied = retained
            try verify(copied, options: options)
            try await withThrowingTaskGroup(of: Void.self) { tasks in
                for _ in 0..<2 { tasks.addTask { try verify(retained, options: options) } }
                try await tasks.waitForAll()
            }
            print("PASS detached input/source lifetime, COW value independence and concurrent immutable readers")
        } else { throw Failure(line: #line) }
    }
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL certified apex complete-empty acceptance")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}
