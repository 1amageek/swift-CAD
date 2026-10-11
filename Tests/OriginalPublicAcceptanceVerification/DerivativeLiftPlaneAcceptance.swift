#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
import Synchronization
@testable import CADGeometry
@testable import DerivativeLiftPlanePort

/// Actual ordinary derivative-host queries retain distinct parameters and every exact incident.
@main struct DerivativeLiftPlaneAcceptance {
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init(work: Int = 8_388_608) throws {
            ledger = .init(limits: try .init(work: work, storageBytes: 400_000_000,
                valueDepth: 32, coefficientDepth: 32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) { try ledger.consumeWork(count) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes: bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try ledger.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try ledger.admitDepth(value: value, coefficient: coefficient)
        }
    }

    struct Failure: Error { let line: Int }
    nonisolated static func require(_ value: Bool, line: Int = #line) throws {
        if !value { throw Failure(line: line) }
    }
    typealias Field = OriginalExactScalarDomain
    typealias Result = DerivativeLiftPlanePort.CurveSurfaceIntersectionResult
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelTask: Bool
        let cancelStorageAt: Int?
        init(work: Int = Int.max, bytes: Int = Int.max, cancelAt: Int? = nil, cancelTask: Bool = false, cancelStorageAt: Int? = nil) {
            maximumWork = work; maximumBytes = bytes; self.cancelAt = cancelAt; self.cancelTask = cancelTask
            self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1; return state.work
            }
            if reached == cancelAt {
                if cancelTask { withUnsafeCurrentTask { $0?.cancel() } }
                else { throw CancellationError() }
            }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = next.partialValue
                return state.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }

    static func marker(_ value: StaticString) { print(value); fflush(nil) }
#if hasFeature(Embedded)
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat {
            putchar(Int32(48 + value / divisor % 10))
            divisor /= 10
        } while divisor > 0
        putchar(10)
    }
#endif
    static func group() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString: value) }
        return "ordinary"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ordinary"
#endif
    }
    static func input(regression: Int = 0) throws -> (Curve3D, Surface3D) {
        var a = try Admission()
        let host: Surface3D
        let pcurve: SurfaceParameterCurve
        if regression == 0 {
            host = .procedural(.originalPlaneDerivative(try DerivativeHostShape.shape(
                weighted: true, projected: true, using: &a)))
            pcurve = .bSpline(.init(degree: 1, knots: [0,0,0.5,1,1], controlPoints: [
                .init(x:0,y:0), .init(x:0.5,y:0.5), .init(x:1,y:1)]))
        } else {
            let shape = try PolylineAtlasLiftProof.shape(multi: regression == 1, using: &a)
            host = regression == 1 ? .procedural(.originalCoons(shape.0))
                : .procedural(.originalBoundaryCorrected(shape.1))
            pcurve = .polyline(PolylineLiftProof.points())
        }
        return (.surfaceLift(.init(surface: host, parameterCurve: pcurve)),
            .plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX)))
    }
    static func query(_ curve: Curve3D, _ plane: Surface3D, _ counter: Counter,
        options: CurveSurfaceIntersectionOptions = .init(), sourceDepth: Int = 8, algebraicDepth: Int = 32) throws -> Result {
        try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: options, tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
            remainingSourceDepth: sourceDepth, consumeWork: { try counter.consume($0) },
            consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: algebraicDepth)
    }
    static func numeric(_ points: [CurveSurfaceIntersection], normalZ: Bool = false) throws {
        try require(points.count == 1 && points[0].kind == .transverse)
        let p = points[0], z = 5.0 / 32
        try require(p.curveParameter == 0.5 && abs(p.point.x - 0.5) <= 1e-6
            && abs(p.point.y - 0.5) <= 1e-6 && abs(p.point.z - z) <= 1e-6
            && abs(p.surfaceU - (normalZ ? 0.5 : z)) <= 1e-6 && abs(p.surfaceV + 0.5) <= 1e-6)
    }
    static func rich(_ result: Result, normalZ: Bool = false) throws {
        try numeric(result.points, normalZ: normalZ)
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try require(result.representation == .numericalRepresentatives && !geometry.isEmpty
            && !geometry.hasPositiveDimensionalSolutions && geometry.pairs.count == 8
            && geometry.exactPoints.count == 8 && mapping.count == 1
            && mapping.incidenceRanges.count == 1 && mapping.incidenceRanges[0].count == 8
            && Set(mapping.incidenceOrdinals) == Set(0..<8))
        var a = try Admission()
        let f = mapping.coordinates.field
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        let z = try f.dividing(f.integer(5, using: &a), f.integer(32, using: &a), using: &a)
        for ordinal in mapping.incidenceOrdinals {
            for (axis, expected) in [half, normalZ ? half : z, try f.negated(half, using: &a), half, half, z].enumerated() {
                try require(f.compare(mapping.coordinates.values[6 * ordinal + axis], expected, using: &a) == .equal)
            }
            let point = geometry.exactPoints[ordinal]
            guard let original = point.originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
            let q = point.local.witness.field
            let qhalf = try q.dividing(q.integer(1, using: &a), q.integer(2, using: &a), using: &a)
            try require(original.count == 3)
            for value in original { try require(q.compare(value, qhalf, using: &a) == .equal) }
            let pair = geometry.pairs[point.pairOrdinal]
            try require(!pair.geometry.hasPositiveDimensionalSolutions && !pair.geometry.strata.isEmpty)
            for stratum in pair.geometry.strata {
                try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0)
            }
        }
    }
    static func regression(_ result: Result, coons: Bool) throws {
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        let count = coons ? 12 : 3, z = coons ? 0.0 : 0.0625
        try require(result.points.count == 2 && geometry.exactPoints.count == count
            && !geometry.hasPositiveDimensionalSolutions && mapping.count == 2
            && mapping.incidenceRanges[0].count == (coons ? 8 : 2)
            && mapping.incidenceRanges[1].count == (coons ? 4 : 1)
            && Set(mapping.incidenceOrdinals) == Set(0..<count))
        try require(abs(result.points[0].curveParameter - (2.0.squareRoot() - 1)) <= 1e-6
            && result.points[1].curveParameter == 1)
        for p in result.points {
            try require(abs(p.point.x - 0.5) <= 1e-6 && abs(p.point.y - 0.5) <= 1e-6
                && abs(p.point.z - z) <= 1e-6 && abs(p.surfaceU - z) <= 1e-6
                && abs(p.surfaceV + 0.5) <= 1e-6)
        }
    }
    static func empty(_ result: Result) throws {
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try require(result.points.isEmpty && geometry.isEmpty && geometry.exactPoints.isEmpty
            && mapping.count == 0 && !geometry.hasPositiveDimensionalSolutions)
    }
    static func run() async throws {
        let selected = group(), (curve, plane) = try input()
        let counter = Counter()
        if selected == "ordinary" {
            let bare = try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(curve: curve,
                surface: plane, options: .init(), tolerance: .standard)
            try numeric(bare)
            try rich(DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(curve: curve,
                surface: plane, options: .init(), tolerance: .standard))
            let callbackBare = try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(curve: curve,
                surface: plane, options: .init(), tolerance: .standard, maximumSpanCount: 262_144,
                maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
                maximumAlgebraicDepth: 32)
            try numeric(callbackBare)
            try rich(query(curve, plane, Counter()))
#if hasFeature(Embedded)
            logCount("ordinaryCallbackWork", counter.totals.work)
            logCount("ordinaryCallbackBytes", counter.totals.bytes)
#else
            print("ordinaryCallbackWork", counter.totals.work, "ordinaryCallbackBytes", counter.totals.bytes)
#endif
            marker("PASS derivative ordinary standard/callback bare/rich; sole T=.5; exact5/32 XYZ/planeUV; sourceUV and all8 incidents")
        } else if selected == "regressions" {
            for kind in [1, 2] {
                let (curve, plane) = try input(regression: kind)
                let rich = try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(
                    curve: curve, surface: plane, options: .init(), tolerance: .standard)
                try regression(rich, coons: kind == 1)
                let bare = try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(
                    curve: curve, surface: plane, options: .init(), tolerance: .standard)
                try require(bare.count == rich.points.count)
                try regression(query(curve, plane, Counter()), coons: kind == 1)
                let callback = Counter()
                let callbackBare = try DerivativeLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(
                    curve: curve, surface: plane, options: .init(), tolerance: .standard,
                    maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                    consumeWork: { try callback.consume($0) }, consumeStorage: { try callback.retain($0) },
                    maximumAlgebraicDepth: 32)
                try require(callbackBare.count == rich.points.count)
                for index in callbackBare.indices {
                    try require(abs(callbackBare[index].curveParameter - rich.points[index].curveParameter) <= 1e-6
                        && abs(callbackBare[index].point.x - rich.points[index].point.x) <= 1e-6
                        && abs(callbackBare[index].point.y - rich.points[index].point.y) <= 1e-6
                        && abs(callbackBare[index].point.z - rich.points[index].point.z) <= 1e-6)
                }
            }
            marker("PASS derivative port original Coons/correction polyline regressions")
        } else if selected == "selections" {
            for (range, count) in [(try ScalarInterval(lower: 0.5, upper: 0.5), 1),
                (try ScalarInterval(lower: 0.6, upper: 0.9), 0), (try ScalarInterval(lower: 2, upper: 3), 0)] {
                var options = CurveSurfaceIntersectionOptions(); options.curveRange = range
                let result = try query(curve, plane, Counter(), options: options)
                try require(result.points.count == count)
                if count == 0 { try empty(result) }
                else {
                    try require(result.points[0].curveParameter == 0.5
                        && result.originalIssuedGeometricRelation?.exactPoints.count == 8)
                }
            }
            var options = CurveSurfaceIntersectionOptions(); options.surfaceURange = try .init(lower: 1, upper: 2)
            try empty(query(curve, plane, Counter(), options: options))
            marker("PASS derivative curve singleton/root-free/outside-support selections and plane UV exclusion complete empty")
        } else if selected == "remainder" {
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: 0.5, upper: 0.5)
            let horizontal = Surface3D.plane(.init(origin: .init(x: 0, y: 0, z: 5.0 / 32), normal: .unitZ))
            try rich(query(curve, horizontal, Counter(), options: options), normalZ: true)
            marker("PASS derivative same-input horizontal plane singleton preserves original high-degree residual request and all8 incidents")
        } else if selected == "query-work" {
            let finite = Counter(work: 8_388_608)
            try rich(query(curve, plane, finite))
            for cap in [1, 100_000] {
                let (freshCurve, freshPlane) = try input(), bounded = Counter(work: cap)
                do { _ = try query(freshCurve, freshPlane, bounded); throw Failure(line: #line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
                try require(bounded.totals.work == cap)
            }
#if hasFeature(Embedded)
            logCount("successfulWork", finite.totals.work)
            logCount("successfulBytes", finite.totals.bytes)
#else
            print("successfulWork", finite.totals.work, "successfulBytes", finite.totals.bytes)
#endif
            marker("PASS derivative finite allowance success; fixed work caps1/100000 forward typed refusal at exact callback cap")
        } else if selected == "query-storage" {
            try rich(query(curve, plane, counter)); let totals = counter.totals
            let (exactCurve, exactPlane) = try input(), exact = Counter(bytes: totals.bytes)
            try rich(query(exactCurve, exactPlane, exact))
            try require(exact.totals.bytes == totals.bytes)
            let (shortCurve, shortPlane) = try input()
            do { _ = try query(shortCurve, shortPlane, Counter(bytes: totals.bytes - 1)); throw Failure(line: #line) }
            catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
#if hasFeature(Embedded)
            logCount("queryBytes", totals.bytes)
#else
            print("queryBytes", totals.bytes)
#endif
            marker("PASS derivative independent exact storage budget success and one-less typed resource refusal")
        } else if selected == "depth" {
            for depth in [0, 1, 2] {
                do { _ = try query(curve, plane, Counter(), sourceDepth: depth); throw Failure(line: #line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
            }
            try rich(query(curve, plane, Counter(), sourceDepth: 3))
            try rich(query(curve, plane, Counter(), algebraicDepth: 0))
            var exactCandidates = CurveSurfaceIntersectionOptions()
            exactCandidates.maximumCandidateCount = 8
            try rich(query(curve, plane, Counter(), options: exactCandidates))
            for kind in 0..<2 {
                var options = CurveSurfaceIntersectionOptions()
                if kind == 0 { options.maximumCandidateCount = 7 } else { options.maximumPolynomialDegree = 0 }
                do { _ = try query(curve, plane, Counter(), options: options); throw Failure(line: #line) }
                catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
            }
            marker("PASS derivative source depth3 and candidate8 success; depth2/candidate7/polynomial0 typed refusal; rational-only algebraic depth0 succeeds")
        } else if selected == "cancel-entry" {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try query(curve, plane, counter); throw Failure(line: #line) }
            catch is CancellationError { }
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            marker("PASS derivative entry Task cancellation before work/storage")
        } else if selected == "cancel-final" {
            try rich(query(curve, plane, counter)); let totals = counter.totals
            let (freshCurve, freshPlane) = try input(), canceled = Counter(cancelStorageAt: totals.bytes)
            do { _ = try query(freshCurve, freshPlane, canceled); throw Failure(line: #line) }
            catch is CancellationError { }
            try require(canceled.totals.bytes == totals.bytes)
            marker("PASS derivative current-Task cancellation at final result storage callback before publication")
        } else if selected == "cancel-empty" {
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: 2, upper: 3)
            try empty(query(curve, plane, counter, options: options))
            let totals = counter.totals
            let (freshCurve, freshPlane) = try input(), canceled = Counter(cancelStorageAt: totals.bytes)
            do { _ = try query(freshCurve, freshPlane, canceled, options: options); throw Failure(line: #line) }
            catch is CancellationError { }
            try require(canceled.totals.bytes == totals.bytes)
            marker("PASS derivative current-Task cancellation at complete-empty final result allocation before publication")
        } else if selected == "cancel-callbacks" {
            for tick in [1, 100_000] {
                let (freshCurve, freshPlane) = try input(), canceled = Counter(cancelAt: tick)
                do { _ = try query(freshCurve, freshPlane, canceled); throw Failure(line: #line) }
                catch is CancellationError { }
                try require(canceled.totals.work == tick)
            }
            marker("PASS derivative entry/mid work callback cancellation at exact observed ticks")
        } else if selected == "lifetime" {
            let result: Result
            do {
                let (ownedCurve, ownedPlane) = try input()
                result = try query(ownedCurve, ownedPlane, Counter())
                guard case .surfaceLift(let lift) = ownedCurve,
                    case .bSpline(let pcurve) = lift.parameterCurve,
                    case .procedural(.originalPlaneDerivative(let host)) = lift.surface else {
                    throw ExactScalarFailure.invalidEvidence
                }
                var changed = pcurve; changed.controlPoints[1].x = 0.75
                var construction = host.construction.construction
                construction.controlPoints[0][0].z = 1
                try require(pcurve.controlPoints[1].x == 0.5 && changed.controlPoints[1].x == 0.75
                    && host.construction.construction.controlPoints[0][0].z == 0)

            }
            try rich(result)
            try await withThrowingTaskGroup(of: Void.self) { readers in
                for _ in 0..<2 { readers.addTask { try rich(result) } }
                try await readers.waitForAll()
            }
            marker("PASS derivative detached input/result owners, COW source points and concurrent independent exact readers")
        } else { throw ExactScalarFailure.invalidEvidence }
    }
    static func main() async {
        do { try await run() }
        catch {
            marker("FAIL derivative ordinary lift/plane")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}
