#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
import CADCore
@testable import CADGeometry

/// The numerical point array is checked beside the complete original-source owner.
@main struct AngularPhysicalArcPlaneAcceptance {
    struct Failure: Error { let line: Int }
    typealias Base = RetainedHostAdapters.OriginalPiScalarDomain
    typealias Value = RetainedHostAdapters.OriginalPiValue
    typealias Field = PublicLiftPlane.ExactAlgebraicScalarDomain<Base>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>
    typealias CurveSource = AngularSourcePhase.OriginalAnalyticCoordinateSnapshot
    typealias PlaneSource = AngularSourcePhase.OriginalPlaneSnapshot

    static func require(_ condition: Bool, line: Int = #line) throws {
        if !condition { throw Failure(line: line) }
    }
    static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 8_388_608, storageBytes: 268_435_456,
            valueDepth: 32, coefficientDepth: 32))
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: 1), maximumTransportDepth: 32,
            maximumCharts: 262_144, maximumFamilies: 1, maximumIdentityProofs: 0)
    }
    static func equal(_ lhs: Value, _ rhs: Value, field: Base,
        using a: inout ExactScalarLedger) throws {
        try require(field.compare(lhs, rhs, using: &a) == .equal)
    }
    static func values(_ lhs: [Value], _ rhs: [Value], field: Base,
        using a: inout ExactScalarLedger) throws {
        try require(lhs.count == rhs.count)
        for i in rhs.indices { try equal(lhs[i], rhs[i], field: field, using: &a) }
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = Int.max, cancelAt: Int? = nil,
            cancelStorageAt: Int? = nil) {
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
    static func input(center: Point3D = .origin) throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
        var a = try ledger()
        let source = Curve3D.circle(.init(center: center, normal: .unitZ, radius: 3))
        let wrapper = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAngularTransportCurve3D(source: source,
                transport: .physicalRadianArc(start: .zero, end: .one, additionalTurns: 1),
                tolerance: .standard, usage: &usage)
        }.value
        let curve = Curve3D.originalAngularTransport(wrapper)
        let plane = Surface3D.analytic(.plane(origin: center, normal: .unitX))
        var options = CurveSurfaceIntersectionOptions()
        options.curveRange = try .init(lower: 0, upper: 1)
        options.surfaceURange = try .init(lower: -1, upper: 1)
        options.surfaceVRange = try .init(lower: -4, upper: 4)
        return (curve, plane, options)
    }
    static func admitted(_ curve: Curve3D, _ plane: Surface3D, _ options: CurveSurfaceIntersectionOptions,
        _ counter: Counter, sourceDepth: Int = 8, algebraicDepth: Int = 32) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: options, tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: algebraicDepth)
    }
    static func selected(_ t: Value, _ uv: [Value], options: CurveSurfaceIntersectionOptions,
        field f: Base, using a: inout ExactScalarLedger) throws -> Bool {
        guard let range = options.curveRange else { throw Failure(line: #line) }
        for (value, range) in [(t, range), (uv[0], options.surfaceURange!), (uv[1], options.surfaceVRange!)] {
            if try f.compare(value, f.binary64(exactly: range.lower, using: &a), using: &a) == .less { return false }
            if try f.compare(value, f.binary64(exactly: range.upper, using: &a), using: &a) == .greater { return false }
        }
        return true
    }
    static func singleton(_ partition: PublicLiftPlane.ExactRealCellPartition<Base>, expected: [Value],
        field: Field, using a: inout ExactScalarLedger) throws {
        try require(partition.source.variableCount == expected.count && partition.source.domains.count == expected.count)
        for axis in expected.indices {
            let interval = partition.source.domains[axis]
            guard case .finite(let lower) = interval.lower, case .finite(let upper) = interval.upper else {
                throw Failure(line: #line)
            }
            let value = try field.importingBase(expected[axis], using: &a)
            try require(interval.includesLower && interval.includesUpper)
            try require(field.compare(lower, value, using: &a) == .equal && field.compare(upper, value, using: &a) == .equal)
        }
        var terminals = 0
        for cell in partition.cells where cell.axis == expected.count - 1 {
            try require(cell.dimension == 0); terminals += 1
        }
        try require(terminals == 1)
    }
    static func verify(_ result: CurveSurfaceIntersectionResult, options: CurveSurfaceIntersectionOptions,
        center: Point3D = .origin) throws {
        guard let geometry = result.originalAngularPlaneRelation else { throw Failure(line: #line) }
        let raw = geometry.original, zeros = raw.zeros, f = raw.curve.law.field
        var a = try ledger()
        let l = try limits()
        try raw.admitProof(limits: l, using: &a)
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let two = try f.integer(2, using: &a), three = try f.integer(3, using: &a)
        let four = try f.integer(4, using: &a), five = try f.integer(5, using: &a)
        let pi = try f.pi(using: &a), gain = try f.adding(one, f.multiplying(two, pi, using: &a), using: &a)
        let halfPi = try f.dividing(pi, two, using: &a)
        let denominator = try f.multiplying(two, gain, using: &a)
        let first = try f.dividing(pi, denominator, using: &a)
        let second = try f.dividing(f.multiplying(three, pi, using: &a), denominator, using: &a)
        let b = try f.binary64(exactly: 2 * Double.pi, using: &a)
        let quarter = try f.dividing(b, four, using: &a)
        let centerValues = try [center.x, center.y, center.z].map { try f.binary64(exactly: $0, using: &a) }
        try require(f.compare(pi, two, using: &a) == .greater)
        try equal(zeros.gain, gain, field: f, using: &a)
        try equal(zeros.offset, zero, field: f, using: &a)
        try equal(zeros.supportLower, zero, field: f, using: &a)
        try equal(zeros.supportUpper, one, field: f, using: &a)
        try equal(zeros.phaseLower, zero, field: f, using: &a)
        try equal(zeros.phaseUpper, gain, field: f, using: &a)
        try equal(zeros.outsideLowerPhase, f.negated(halfPi, using: &a), field: f, using: &a)
        try equal(zeros.outsideUpperPhase, f.multiplying(five, halfPi, using: &a), field: f, using: &a)
        try require(f.compare(zeros.outsideLowerPhase, zeros.phaseLower, using: &a) == .less
            && f.compare(zeros.phaseUpper, zeros.outsideUpperPhase, using: &a) == .less)
        try equal(zeros.labelPeriod, b, field: f, using: &a)
        try require(zeros.roots.count == 2 && raw.decisions.count == 2)
        try require(raw.curve.source.owner === zeros.law.source.owner)
        let ring = zeros.law.polynomials
        try require(ring.variableCount == 2 && zeros.law.position.count == 3)
        for axis in 0..<3 {
            let constant = try ring.constant(centerValues[axis], using: &a)
            let expected = axis < 2 ? try ring.adding(constant,
                ring.scaled(ring.variable(axis, using: &a), by: three, using: &a), using: &a) : constant
            try require(ring.equals(zeros.law.position[axis], expected, using: &a))
        }
        try values(raw.plane.law.origin, centerValues, field: f, using: &a)
        try values(raw.plane.law.normal, [one, zero, zero], field: f, using: &a)
        try values(raw.plane.law.u, [zero, zero, one], field: f, using: &a)
        try values(raw.plane.law.v, [zero, try f.negated(one, using: &a), zero], field: f, using: &a)
        try equal(raw.coefficient, three, field: f, using: &a)
        try require(ring.isZero(raw.incidenceResidual, using: &a)
            && ring.equals(raw.incidence, ring.scaled(ring.variable(0, using: &a), by: three, using: &a), using: &a)
            && ring.equals(raw.incidence, raw.cosineMultiple, using: &a))
        var expectedOrdinals: [Int] = []
        for index in 0..<2 {
            let root = zeros.roots[index], decision = raw.decisions[index]
            let t = index == 0 ? first : second, sine = index == 0 ? one : try f.negated(one, using: &a)
            let phase = index == 0 ? halfPi : try f.multiplying(three, halfPi, using: &a)
            let label = index == 0 ? quarter : try f.multiplying(three, quarter, using: &a)
            let signedRadius = try f.multiplying(three, sine, using: &a)
            let xyz = [centerValues[0], try f.adding(centerValues[1], signedRadius, using: &a), centerValues[2]]
            let uv = [zero, try f.negated(signedRadius, using: &a)]
            let derivative = [try f.negated(f.multiplying(signedRadius, gain, using: &a), using: &a), zero, zero]
            try equal(root.parameter, t, field: f, using: &a)
            try equal(root.phase, phase, field: f, using: &a)
            try equal(root.childLabel, label, field: f, using: &a)
            try equal(root.sine, sine, field: f, using: &a)
            try values(root.position, xyz, field: f, using: &a)
            try values(root.derivative, derivative, field: f, using: &a)
            try require(f.compare(root.childLabel, root.phase, using: &a) != .equal)
            try require(decision.rootOrdinal == index)
            try values(decision.uv, uv, field: f, using: &a)
            try values(decision.planePosition, xyz, field: f, using: &a)
            try equal(decision.transverse, derivative[0], field: f, using: &a)
            let expected = try selected(t, uv, options: options, field: f, using: &a)
            try require(decision.selected == expected)
            let curveIncluded = try raw.curve.effective.contains([t], limits: l, using: &a)
            let planeIncluded = try raw.plane.effective.contains(uv, limits: l, using: &a)
            try require((curveIncluded && planeIncluded) == expected)
            try require(decision.curveIncidents.count == (curveIncluded ? 1 : 0)
                && decision.planeIncidents.count == (planeIncluded ? 1 : 0))
            for incident in decision.curveIncidents {
                let back = try DefaultOriginalParameterTransporter<CurveSource, Base>().forward([t], through: incident, limits: l, using: &a)
                try values(back, [t], field: f, using: &a)
            }
            for incident in decision.planeIncidents {
                let back = try DefaultOriginalParameterTransporter<PlaneSource, Base>().forward(uv, through: incident, limits: l, using: &a)
                try values(back, uv, field: f, using: &a)
            }
            if expected { expectedOrdinals.append(index) }
        }
        try require(raw.pairs.count == expectedOrdinals.count && geometry.pairs.count == expectedOrdinals.count
            && geometry.exactPoints.count == expectedOrdinals.count && result.points.count == expectedOrdinals.count)
        try require(result.overlaps.isEmpty && geometry.isEmpty == expectedOrdinals.isEmpty
            && !geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage)
        for index in expectedOrdinals.indices {
            let ordinal = expectedOrdinals[index], pair = raw.pairs[index], geometric = geometry.pairs[index]
            let exact = geometry.exactPoints[index], numeric = result.points[index]
            let root = zeros.roots[ordinal], decision = raw.decisions[ordinal]
            try require(pair.rootOrdinal == ordinal && exact.rootOrdinal == ordinal && exact.original === raw)
            try require(pair.relation.selection.cells.count == 1 && pair.relation.selection.cells[0].dimension == 0)
            try require(pair.relation.components.count == 1 && geometric.strata.count == 1)
            try singleton(pair.relation.selection.partition, expected: [root.parameter] + decision.uv,
                field: exact.local.witness.field, using: &a)
            for stratum in geometric.strata {
                try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
                try require(geometric.parameterCell(forStratum: stratum.ordinal) == pair.relation.selection.cells[0])
            }
            try require(exact.local.parameters.count == 3)
            let af = exact.local.witness.field
            for (actual, value) in zip(exact.local.parameters, [root.parameter] + decision.uv) {
                try require(af.compare(actual, af.importingBase(value, using: &a), using: &a) == .equal)
            }
            for (actual, value) in zip([exact.local.position.x, exact.local.position.y, exact.local.position.z], root.position) {
                try require(af.compare(actual, af.importingBase(value, using: &a), using: &a) == .equal)
            }
            try equal(exact.parameter, root.parameter, field: f, using: &a)
            try equal(exact.phase, root.phase, field: f, using: &a)
            try equal(exact.childLabel, root.childLabel, field: f, using: &a)
            try values(exact.position, root.position, field: f, using: &a)
            try values(exact.uv, decision.uv, field: f, using: &a)
            try require(exact.curveIncidents.count == 1 && exact.planeIncidents.count == 1)
            try require(numeric.curveParameter.isFinite && numeric.surfaceU.isFinite && numeric.surfaceV.isFinite
                && numeric.residual.isFinite && numeric.residual >= 0 && numeric.residual <= ModelingTolerance.standard.distance)
            try require(options.curveRange!.contains(numeric.curveParameter)
                && options.surfaceURange!.contains(numeric.surfaceU) && options.surfaceVRange!.contains(numeric.surfaceV))
            try require(numeric.kind == .transverse && numeric.iterations > 0 && numeric.iterations <= options.maximumIterations)
            var lower = max(0, options.curveRange!.lower), upper = min(1, options.curveRange!.upper)
            for _ in 0..<numeric.iterations {
                let midpoint = lower * 0.5 + upper * 0.5
                let order = try f.compare(root.parameter, f.binary64(exactly: midpoint, using: &a), using: &a)
                if order == .less { upper = midpoint }
                else if order == .greater { lower = midpoint }
                else { lower = midpoint; upper = midpoint }
            }
            try require(numeric.curveParameter == lower * 0.5 + upper * 0.5)
            try require(f.compare(f.binary64(exactly: lower, using: &a), root.parameter, using: &a) != .greater
                && f.compare(root.parameter, f.binary64(exactly: upper, using: &a), using: &a) != .greater)
            for (actual, value) in zip([numeric.point.x, numeric.point.y, numeric.point.z, numeric.surfaceU, numeric.surfaceV], root.position + decision.uv) {
                let tolerance = ModelingTolerance.standard.distance
                try require(f.compare(f.binary64(exactly: (actual - tolerance).nextDown, using: &a), value, using: &a) != .greater
                    && f.compare(value, f.binary64(exactly: (actual + tolerance).nextUp, using: &a), using: &a) != .greater)
            }
        }
    }
    static func resourceFailure(_ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
    }
    static func sourceControls() throws {
        var a = try ledger()
        let f = try Base(using: &a), other = try Base(using: &a)
        let l = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let circle = Curve3D.circle(.init(center: .origin, normal: .unitZ, radius: 3))
        func zeros(_ curve: Curve3D, using a: inout ExactScalarLedger) throws
            -> AngularSourcePhase.OriginalAnalyticCosineZeroReceipt<CurveSource, Base> {
            let source = try DefaultOriginalSourceBindingIssuer(provider:
                AngularSourcePhase.OriginalAnalyticCoordinateCurveSnapshotProvider(tolerance: .standard))
                .bind(curve, limits: l, using: &a)
            let law = try DefaultOriginalPhysicalAnalyticCoordinateIssuer<CurveSource, Base>()
                .issue(source: source, field: f, limits: l, using: &a)
            return try AngularSourcePhase.DefaultOriginalAnalyticCosineZeroIssuer<CurveSource, Base>()
                .issue(law: law, limits: l, using: &a)
        }
        let negative = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAngularTransportCurve3D(source: circle,
                transport: .physicalRadianArc(start: .natural(5, usage: &usage),
                    end: .natural(2, usage: &usage), additionalTurns: 0),
                tolerance: .standard, usage: &usage)
        }.value
        let receipt = try zeros(.originalAngularTransport(negative), using: &a)
        try receipt.admitProof(limits: l, using: &a)
        let pi = try f.pi(using: &a), two = try f.integer(2, using: &a), three = try f.integer(3, using: &a)
        let phase = try f.dividing(f.multiplying(three, pi, using: &a), two, using: &a)
        let t = try f.dividing(f.subtracting(f.integer(5, using: &a), phase, using: &a), three, using: &a)
        try require(receipt.roots.count == 1)
        try equal(receipt.gain, f.integer(-3, using: &a), field: f, using: &a)
        try equal(receipt.offset, f.integer(5, using: &a), field: f, using: &a)
        try equal(receipt.roots[0].parameter, t, field: f, using: &a)
        try equal(receipt.roots[0].phase, phase, field: f, using: &a)
        try values(receipt.roots[0].position, [f.integer(0, using: &a),
            f.integer(-3, using: &a), f.integer(0, using: &a)], field: f, using: &a)
        try values(receipt.roots[0].derivative, [f.integer(-9, using: &a),
            f.integer(0, using: &a), f.integer(0, using: &a)], field: f, using: &a)
        let wide = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAngularTransportCurve3D(source: circle,
                transport: .physicalRadianArc(start: .zero, end: .one, additionalTurns: 2),
                tolerance: .standard, usage: &usage)
        }.value
        for unsupported in [circle, .originalAngularTransport(wide)] {
            do { _ = try zeros(unsupported, using: &a); throw Failure(line: #line) }
            catch let error as OriginalSourceIssuanceFailure {
                guard case .unsupportedRepresentation = error else { throw error }
            }
        }
        let foreign = try other.pi(using: &a)
        do { _ = try f.compare(foreign, pi, using: &a); throw Failure(line: #line) }
        catch let error as ExactScalarFailure {
            guard case .incompatibleDomain = error else { throw error }
        }
        try equal(f.importing(foreign, using: &a), pi, field: f, using: &a)
        print("PASS original finite-window negative gain, complete one-root theorem, wider/unbounded refusal and foreign-owner refusal/import")
    }
    static func resolverControls() throws {
        let intersector = DefaultCurveSurfaceIntersector()
        let line = Curve3D.line(.init(origin: .init(x: -1, y: 3, z: 2), direction: .unitX))
        let plane = Surface3D.plane(.init(origin: .origin, normal: .unitX))
        var options = CurveSurfaceIntersectionOptions(curveRange: try .init(lower: 0, upper: 2),
            surfaceURange: try .init(lower: 1.5, upper: 2.5), surfaceVRange: try .init(lower: -3.5, upper: -2.5))
        let same = try intersector.intersectionResult(curve: line, surface: plane, options: options, tolerance: .standard)
        try require(same.overlaps.isEmpty && same.points.count == 1 && same.originalAngularPlaneRelation == nil)
        try require(same.points[0].curveParameter == 1 && same.points[0].surfaceU == 2 && same.points[0].surfaceV == -3
            && same.points[0].point == Point3D(x: 0, y: 3, z: 2))
        options.surfaceURange = try .init(lower: 0.25, upper: 0.5)
        let outside = try intersector.intersectionResult(curve: line, surface: plane, options: options, tolerance: .standard)
        try require(outside.points.isEmpty && outside.overlaps.isEmpty)
        let patch = Surface3D.bSpline(.init(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: 10, y: 20, z: 0), .init(x: 12, y: 20, z: 0)],
                [.init(x: 10, y: 24, z: 0), .init(x: 12, y: 24, z: 0)]]))
        let crossing = Curve3D.line(.init(origin: .init(x: 10.5, y: 21, z: -1), direction: .unitZ))
        options.surfaceURange = try .init(lower: 0.2, upper: 0.3)
        options.surfaceVRange = try .init(lower: 0.2, upper: 0.3)
        let converted = try intersector.intersectionResult(curve: crossing, surface: patch, options: options, tolerance: .standard)
        try require(converted.overlaps.isEmpty && converted.points.count == 1 && converted.originalAngularPlaneRelation == nil)
        try require(converted.points[0].curveParameter == 1 && converted.points[0].surfaceU == 0.25
            && converted.points[0].surfaceV == 0.25 && converted.points[0].point == Point3D(x: 10.5, y: 21, z: 0))
        options.surfaceVRange = try .init(lower: 0.5, upper: 0.75)
        let excluded = try intersector.intersectionResult(curve: crossing, surface: patch, options: options, tolerance: .standard)
        try require(excluded.points.isEmpty && excluded.overlaps.isEmpty)
        print("PASS actual non-angular resolver same-frame strict UV forwarding and synthetic affine proof-plane original UV conversion")
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
        if group == "readmission" {
            let result = try query(options)
            guard let geometry = result.originalAngularPlaneRelation else { throw Failure(line: #line) }
            var a = try ledger()
            let restricted = try OriginalDomainIdentityLimits(source: .init(remainingSourceDepth: 1),
                maximumTransportDepth: 1, maximumCharts: 262_144, maximumFamilies: 1, maximumIdentityProofs: 0)
            do {
                try geometry.original.admitProof(limits: restricted, using: &a)
                print("STOP readmission accepted retained incident transport depth2 under maximumTransportDepth1")
                throw Failure(line: #line)
            } catch let error as OriginalDomainIdentityFailure {
                guard case .transportDepthLimit = error else { throw error }
            }
            print("PASS retained incident transport depth2 rejected by follow-up maximumTransportDepth1")
        } else if group == "source" { try sourceControls()
        } else if group == "resolver" { try resolverControls()
        } else if group == "complete" {
            let result = try query(options)
            try verify(result, options: options)
            try require(result.points.count == 2)
            print("PASS complete ordinary angular source/domain/L5/L6: exact two Q(pi) roots and excluded complement")
        } else if group == "dispatch" {
            let ordinary = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard)
            let admittedResult = try admitted(curve, plane, options, Counter())
            try verify(admittedResult, options: options)
            try require(ordinary == admittedResult.points)
            let counter = Counter()
            let callback = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
                options: options, tolerance: .standard, maximumSpanCount: 262_144,
                maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
                maximumAlgebraicDepth: 32)
            try require(callback == ordinary)
            print("PASS ordinary/callback bare and rich dispatch share the same two exact-source points")
        } else if group == "requests" {
            for control in 0..<9 {
                var selected = options
                if control == 0 { selected.curveRange = try .init(lower: 0, upper: 0.25) }
                if control == 1 { selected.curveRange = try .init(lower: 0.5, upper: 1) }
                if control == 2 { selected.curveRange = try .init(lower: 0.25, upper: 0.5) }
                if control == 3 { selected.surfaceVRange = try .init(lower: 0, upper: 4) }
                if control == 4 { selected.surfaceURange = try .init(lower: 0.25, upper: 1) }
                if control == 5 { selected.curveRange = try .init(lower: 2, upper: 3) }
                if control == 6 { selected.surfaceURange = try .init(lower: 0, upper: 0) }
                if control == 7 { selected.surfaceVRange = try .init(lower: -3, upper: -3) }
                if control == 8 { selected.curveRange = try .init(lower: 0, upper: 0) }
                try verify(query(selected), options: selected)
            }
            print("PASS exact subrequests and full source/T/UV exclusion with retained whole zero theorem")
        } else if group == "resources" {
            let baseline = Counter(), result = try admitted(curve, plane, options, baseline)
            try verify(result, options: options)
            let totals = baseline.totals
            try require(totals.work > 1 && totals.work <= 8_388_608 && totals.bytes > 0)
            logCount("QUERY_WORK", totals.work); logCount("QUERY_STORAGE", totals.bytes)
            let exact = Counter(work: totals.work, bytes: totals.bytes)
            try verify(admitted(curve, plane, options, exact), options: options)
            try require(exact.totals.work == totals.work && exact.totals.bytes == totals.bytes)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(work: totals.work - 1)) }
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(bytes: totals.bytes - 1)) }
            try verify(admitted(curve, plane, options, Counter(), sourceDepth: 1), options: options)
            try resourceFailure { _ = try admitted(curve, plane, options, Counter(), sourceDepth: 0) }
            guard let geometry = result.originalAngularPlaneRelation else { throw Failure(line: #line) }
            let depth = geometry.original.depth
            var transport = 0
            for decision in geometry.original.decisions {
                for incident in decision.curveIncidents { transport = max(transport, incident.depth) }
                for incident in decision.planeIncidents { transport = max(transport, incident.depth) }
            }
            let attained = max(depth.value, depth.coefficient, transport)
            logCount("ATTAINED_VALUE_DEPTH", depth.value); logCount("ATTAINED_COEFFICIENT_DEPTH", depth.coefficient)
            logCount("ATTAINED_TRANSPORT_DEPTH", transport)
            try verify(admitted(curve, plane, options, Counter(), algebraicDepth: attained), options: options)
            if attained > 0 {
                try resourceFailure { _ = try admitted(curve, plane, options, Counter(), algebraicDepth: attained - 1) }
            }
            var count = options; count.maximumCandidateCount = 2
            try verify(admitted(curve, plane, count, Counter()), options: count)
            count.maximumCandidateCount = 1
            try resourceFailure { _ = try admitted(curve, plane, count, Counter()) }
            for tick in [1, totals.work / 2] {
                let counter = Counter(cancelAt: tick)
                do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
                catch is CancellationError {}
                try require(counter.totals.work == tick)
            }
            print("PASS measured N/N-1 work/storage, attained depth, source depth, pair count and entry/mid callback cancellation")
        } else if group == "cancel-entry" {
            let counter = Counter()
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try admitted(curve, plane, options, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            print("PASS task cancellation before public work/storage")
        } else if group == "cancel-final" || group == "cancel-empty" {
            var selected = options
            if group == "cancel-empty" { selected.curveRange = try .init(lower: 0.25, upper: 0.5) }
            let baseline = Counter(), result = try admitted(curve, plane, selected, baseline)
            try verify(result, options: selected)
            let counter = Counter(cancelStorageAt: baseline.totals.bytes)
            do { _ = try admitted(curve, plane, selected, counter); throw Failure(line: #line) }
            catch is CancellationError {}
            try require(counter.totals.bytes == baseline.totals.bytes)
            print("PASS final allocation cancellation before nonempty/empty publication")
        } else if group == "lifetime" {
            let retained: CurveSurfaceIntersectionResult
            do {
                var (localCurve, localPlane, localOptions) = try input()
                retained = try admitted(localCurve, localPlane, localOptions, Counter())
                localCurve = .circle(.init(center: .origin, normal: .unitZ, radius: 7))
                localPlane = .analytic(.plane(origin: .init(x: 7, y: 0, z: 0), normal: .unitX))
                localOptions.curveRange = try .init(lower: 0, upper: 0.1)
                if case .circle(let changed) = localCurve { try require(changed.radius == 7) }
            }
            try verify(retained, options: options)
            try await withThrowingTaskGroup(of: Void.self) { tasks in
                for _ in 0..<2 { tasks.addTask { try verify(retained, options: options) } }
                try await tasks.waitForAll()
            }
            print("PASS detached source/result lifetime, authored value independence and concurrent immutable readers")
        } else if group == "plane" {
            let center = Point3D(x: 2, y: -1, z: 4)
            let (shiftedCurve, shiftedPlane, shiftedOptions) = try input(center: center)
            try verify(admitted(shiftedCurve, shiftedPlane, shiftedOptions, Counter()), options: shiftedOptions, center: center)
            print("PASS actual plane source inverse/forward and translated same-frame source incidence")
        } else { throw Failure(line: #line) }
    }
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL angular physical arc plane acceptance")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}
