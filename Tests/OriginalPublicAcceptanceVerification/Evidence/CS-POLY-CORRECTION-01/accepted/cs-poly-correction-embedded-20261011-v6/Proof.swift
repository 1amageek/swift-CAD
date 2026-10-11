import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import enum PublicLiftPlane.NativeExactGeometryPublicationFailure
import enum PublicLiftPlane.GeometryExactScalarFailure
import struct PublicLiftPlane.DefaultExactOriginalScalarTransporter
import class PublicLiftPlane.ExactAlgebraicCalculation
import struct PublicLiftPlane.ExactAlgebraicEmbedding
import protocol PublicLiftPlane.ExactAlgebraicExtending
import struct PublicLiftPlane.ExactAlgebraicExtension
import struct PublicLiftPlane.ExactAlgebraicScalar
import struct PublicLiftPlane.ExactAlgebraicScalarDomain
import struct PublicLiftPlane.ExactOriginalScalarTransferReceipt
import protocol PublicLiftPlane.ExactOriginalScalarTransferring
import struct PublicLiftPlane.ExactRealRoot
import enum PublicLiftPlane.ExactRealRootBound
import enum PublicLiftPlane.ExactRealRootClassification
import struct PublicLiftPlane.ExactRealRootCount
import struct PublicLiftPlane.ExactRealRootDomain
import enum PublicLiftPlane.ExactRealRootFailure
import struct PublicLiftPlane.ExactRealRootInterval
import struct PublicLiftPlane.ExactRealRootLimits
import protocol PublicLiftPlane.ExactRealRootPreparing
import protocol PublicLiftPlane.ExactRealRootProducing
import protocol PublicLiftPlane.ExactRealRootQuerying
import struct PublicLiftPlane.ExactRealRootSeparation
import struct PublicLiftPlane.ExactRealRootSet
import struct PublicLiftPlane.ExactRealRootSigns
import struct PublicLiftPlane.ExactRealRootSource
import struct PublicLiftPlane.ExactRealRootTransport
import protocol PublicLiftPlane.ExactRealRootTransporting
import struct PublicLiftPlane.ExactRealCellBoundaryRoot
import struct PublicLiftPlane.ExactRealCellCondition
import struct PublicLiftPlane.ExactRealCellDefinition
import struct PublicLiftPlane.ExactRealCellDefinitionStep
import protocol PublicLiftPlane.ExactRealCellDescribing
import struct PublicLiftPlane.ExactRealCellDomain
import enum PublicLiftPlane.ExactRealCellFailure
import struct PublicLiftPlane.ExactRealCellID
import enum PublicLiftPlane.ExactRealCellInstruction
import enum PublicLiftPlane.ExactRealCellKind
import struct PublicLiftPlane.ExactRealCellLimits
import struct PublicLiftPlane.ExactRealCellPartition
import struct PublicLiftPlane.ExactRealCellPredicate
import protocol PublicLiftPlane.ExactRealCellPreparing
import protocol PublicLiftPlane.ExactRealCellProducing
import struct PublicLiftPlane.ExactRealCellProjectionBinding
import struct PublicLiftPlane.ExactRealCellProjectionEvidence
import enum PublicLiftPlane.ExactRealCellProjectionWitness
import protocol PublicLiftPlane.ExactRealCellQuerying
import struct PublicLiftPlane.ExactRealCellSample
import protocol PublicLiftPlane.ExactRealCellSelecting
import struct PublicLiftPlane.ExactRealCellSelection
import struct PublicLiftPlane.ExactRealCellSignInvariant
import enum PublicLiftPlane.ExactRealCellSignRelation
import struct PublicLiftPlane.ExactRealCellSource
import struct PublicLiftPlane.ExactRealCellStackEvidence
import protocol PublicLiftPlane.ExactRealCellTraversing
import struct PublicLiftPlane.ExactRealCellView
import struct PublicLiftPlane.ExactRealAttachment
import struct PublicLiftPlane.ExactRealCellPullback
import protocol PublicLiftPlane.ExactRealCellPullbackResolving
import struct PublicLiftPlane.ExactRealClosure
import protocol PublicLiftPlane.ExactRealClosureProducing
import enum PublicLiftPlane.ExactRealClosureProof
import enum PublicLiftPlane.ExactRealClosureStrategy
import struct PublicLiftPlane.ExactRealComponents
import protocol PublicLiftPlane.ExactRealComponentsProducing
import struct PublicLiftPlane.ExactRealIncidence
import struct PublicLiftPlane.ExactRealIncidencePair
import protocol PublicLiftPlane.ExactRealIncidenceProducing
import struct PublicLiftPlane.ExactRealProjection
import struct PublicLiftPlane.ExactRealProjectionLifts
import protocol PublicLiftPlane.ExactRealProjectionProducing
import typealias PublicLiftPlane.ExactRealTopology
import struct PublicLiftPlane.ExactRealTopologyDomain
import struct PublicLiftPlane.ExactRealTopologyElimination
import struct PublicLiftPlane.ExactRealTopologyFactor
import enum PublicLiftPlane.ExactRealTopologyFailure
import struct PublicLiftPlane.ExactRealTopologyLimits
import protocol PublicLiftPlane.ExactRealTopologyQuerying
import struct PublicLiftPlane.ExactRealTopologyReduction
import struct PublicLiftPlane.ExactRealTopologyRegion
import struct PublicLiftPlane.ExactRealTopologySignInvariant
import struct PublicLiftPlane.ExactParametricConstraintDivision
import struct PublicLiftPlane.ExactParametricGraph
import protocol PublicLiftPlane.ExactParametricGraphConstructing
import struct PublicLiftPlane.ExactParametricGraphRelation
import struct PublicLiftPlane.ExactParametricGraphRelationSource
import protocol PublicLiftPlane.ExactParametricGraphResolving
import struct PublicLiftPlane.ExactParametricGuardDivision
import struct PublicLiftPlane.ExactParametricGuardRemainder
import struct PublicLiftPlane.ExactParametricMap
import struct PublicLiftPlane.ExactParametricRelation
import protocol PublicLiftPlane.ExactParametricRelationConstructing
import struct PublicLiftPlane.ExactParametricRelationDomain
import enum PublicLiftPlane.ExactParametricRelationFailure
import enum PublicLiftPlane.ExactParametricRelationKind
import protocol PublicLiftPlane.ExactParametricRelationResolving
import struct PublicLiftPlane.ExactParametricRelationSource
import struct PublicLiftPlane.ExactParametricSquareReduction
import struct PublicLiftPlane.DefaultExactGeometricGraphRelationResolver
import struct PublicLiftPlane.DefaultExactGeometricRelationResolver
import enum PublicLiftPlane.ExactCurveParameterBoundary
import struct PublicLiftPlane.ExactCurveParameterSpan
import enum PublicLiftPlane.ExactGeometricEvidenceKind
import struct PublicLiftPlane.ExactGeometricFiber
import struct PublicLiftPlane.ExactGeometricGraphFiber
import struct PublicLiftPlane.ExactGeometricGraphPoint
import struct PublicLiftPlane.ExactGeometricGraphRelation
import protocol PublicLiftPlane.ExactGeometricGraphRelationResolving
import struct PublicLiftPlane.ExactGeometricRelation
import enum PublicLiftPlane.ExactGeometricRelationFailure
import struct PublicLiftPlane.ExactGeometricRelationLimits
import protocol PublicLiftPlane.ExactGeometricRelationQuerying
import protocol PublicLiftPlane.ExactGeometricRelationResolving
import enum PublicLiftPlane.ExactGeometricStation
import struct PublicLiftPlane.ExactGeometricStratumID
import struct PublicLiftPlane.ExactGeometricStratumRecord
import struct PublicLiftPlane.ExactGeometricStratumView
import struct PublicLiftPlane.ExactUV
import struct PublicLiftPlane.ExactXYZ
import struct PublicLiftPlane.DefaultOriginalIssuedGraphCompiler
import struct PublicLiftPlane.DefaultOriginalIssuedGraphParameterRefiner
import struct PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver
import enum PublicLiftPlane.NativeExactRelationFailure
import protocol PublicLiftPlane.OriginalIssuedGraphCompiling
import struct PublicLiftPlane.OriginalIssuedGraphFamily
import protocol PublicLiftPlane.OriginalIssuedGraphFamilyPreparing
import struct PublicLiftPlane.OriginalIssuedGraphParameterRefinement
import protocol PublicLiftPlane.OriginalIssuedGraphParameterRefining
import struct PublicLiftPlane.OriginalIssuedGraphPreparation
import protocol PublicLiftPlane.OriginalIssuedGraphRelationOwning
import struct PublicLiftPlane.OriginalIssuedGraphRelationPair
import protocol PublicLiftPlane.OriginalIssuedGraphRelationResolving
import struct PublicLiftPlane.OriginalIssuedGraphRelations
import struct PublicLiftPlane.DefaultOriginalIssuedGeometricRelationResolver
import enum PublicLiftPlane.NativeExactGeometricRelationFailure
import struct PublicLiftPlane.OriginalIssuedExactIntersectionPoint
import struct PublicLiftPlane.OriginalIssuedGeometricRelationPair
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationReading
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationResolving
import struct PublicLiftPlane.OriginalIssuedGeometricRelations
import struct PublicLiftPlane.OriginalLiftPlaneParameterRestriction
import protocol PublicLiftPlane.OriginalPlaneGraphCompiling
import struct PublicLiftPlane.OriginalIssuedPlaneGraph
import struct PublicLiftPlane.DefaultOriginalPlaneGraphCompiler
import struct PublicLiftPlane.OriginalLiftPlaneRelations
import protocol PublicLiftPlane.OriginalLiftPlaneRelationResolving
import struct PublicLiftPlane.DefaultOriginalLiftPlaneRelationResolver
import struct PublicLiftPlane.OriginalLiftPlaneGeometricRelations
import CADCore

#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
import Synchronization
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicLiftPlanePort

/// Actual ordinary corrected-host queries retain distinct parameters and every exact incident.
@main struct CorrectedPolylineLiftPlaneAcceptance {
    typealias Field = OriginalExactScalarDomain
    typealias Result = PublicLiftPlanePort.CurveSurfaceIntersectionResult
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
    static func input(coons: Bool = false) throws -> (Curve3D, Surface3D) {
        var a = try PolylineLiftProof.Admission(work: 8_388_608)
        let shape = try PolylineAtlasLiftProof.shape(multi: coons, using: &a)
        let host: Surface3D = coons ? .procedural(.originalCoons(shape.0))
            : .procedural(.originalBoundaryCorrected(shape.1))
        return (.surfaceLift(.init(surface: host,
            parameterCurve: .polyline(PolylineLiftProof.points()))),
            .plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX)))
    }
    static func query(_ curve: Curve3D, _ plane: Surface3D, _ counter: Counter,
        options: CurveSurfaceIntersectionOptions = .init(), sourceDepth: Int = 8, algebraicDepth: Int = 32) throws -> Result {
        try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: options, tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
            remainingSourceDepth: sourceDepth, consumeWork: { try counter.consume($0) },
            consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: algebraicDepth)
    }
    static func numeric(_ points: [CurveSurfaceIntersection], corrected: Bool = true) throws {
        try PolylineLiftProof.require(points.count == 2)
        try PolylineLiftProof.require(abs(points[0].curveParameter - (2.0.squareRoot() - 1)) <= 1e-6
            && points[1].curveParameter == 1 && points[0].curveParameter < points[1].curveParameter)
        for point in points {
            try PolylineLiftProof.require(point.kind == .transverse)
            try PolylineLiftProof.require(abs(point.point.x - 0.5) <= 1e-6 && abs(point.point.y - 0.5) <= 1e-6
                && abs(point.point.z - (corrected ? 0.0625 : 0)) <= 1e-6)
            try PolylineLiftProof.require(abs(point.surfaceU - (corrected ? 0.0625 : 0)) <= 1e-6 && abs(point.surfaceV + 0.5) <= 1e-6)
        }
    }
    static func rich(_ result: Result, corrected: Bool = true) throws {
        try numeric(result.points, corrected: corrected)
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try PolylineLiftProof.require(result.representation == .numericalRepresentatives && !geometry.isEmpty
            && !geometry.hasPositiveDimensionalSolutions && geometry.pairs.count == (corrected ? 3 : 12))
        try PolylineLiftProof.require(geometry.exactPoints.count == (corrected ? 3 : 12) && mapping.count == 2
            && mapping.incidenceRanges[0].count == (corrected ? 2 : 8) && mapping.incidenceRanges[1].count == (corrected ? 1 : 4))
        try PolylineLiftProof.require(Set(mapping.incidenceOrdinals) == Set(0..<(corrected ? 3 : 12)))
        var a = try PolylineLiftProof.Admission(work: 8_388_608)
        let f = mapping.coordinates.field
        let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let half = try f.dividing(one, two, using: &a)
        let z = try corrected ? f.dividing(one, f.integer(16, using: &a), using: &a) : f.integer(0, using: &a)
        func root(_ t: Field.Value, group: Int) throws {
            if group == 0 {
                try PolylineLiftProof.require(f.sign(of: t, using: &a) == .positive && f.compare(t, one, using: &a) == .less)
                let equation = try f.subtracting(f.adding(f.multiplying(t, t, using: &a),
                    f.multiplying(two, t, using: &a), using: &a), one, using: &a)
                try PolylineLiftProof.require(f.sign(of: equation, using: &a) == .zero)
            } else { try PolylineLiftProof.require(f.compare(t, one, using: &a) == .equal) }
        }
        for group in mapping.incidenceRanges.indices {
            for index in mapping.incidenceRanges[group] {
                let ordinal = mapping.incidenceOrdinals[index], values = mapping.coordinates.values
                try root(values[6 * ordinal], group: group)
                for (axis, expected) in [z, try f.negated(half, using: &a), half, half, z].enumerated() {
                    try PolylineLiftProof.require(f.compare(values[6 * ordinal + axis + 1], expected, using: &a) == .equal)
                }
                let point = geometry.exactPoints[ordinal]
                guard let original = point.originalFirstCoordinates else { throw ExactScalarFailure.invalidEvidence }
                let q = point.local.witness.field, qone = try q.integer(1, using: &a)
                let qhalf = try q.dividing(qone, q.integer(2, using: &a), using: &a)
                try PolylineLiftProof.require(original.count == 3 && q.compare(original[1], qhalf, using: &a) == .equal
                    && q.compare(original[2], qhalf, using: &a) == .equal)
                if group == 0 {
                    let qt = original[0], qtwo = try q.integer(2, using: &a)
                    let polynomial = try q.subtracting(q.adding(q.multiplying(qt, qt, using: &a),
                        q.multiplying(qtwo, qt, using: &a), using: &a), qone, using: &a)
                    try PolylineLiftProof.require(q.sign(of: qt, using: &a) == .positive && q.sign(of: polynomial, using: &a) == .zero)
                } else { try PolylineLiftProof.require(q.compare(original[0], qone, using: &a) == .equal) }
            }
        }
    }
    static func empty(_ result: Result) throws {
        guard let geometry = result.originalIssuedGeometricRelation, let mapping = result.originalIssuedNumericalPoints else {
            throw ExactScalarFailure.invalidEvidence
        }
        try PolylineLiftProof.require(result.points.isEmpty && geometry.isEmpty && geometry.exactPoints.isEmpty
            && mapping.count == 0 && !geometry.hasPositiveDimensionalSolutions)
    }
    static func run() async throws {
        let selected = group(), (curve, plane) = try input()
        let counter = Counter()
        if selected == "ordinary" || selected == "coons-regression" {
            let corrected = selected == "ordinary"
            let (curve, plane) = try input(coons: !corrected)
            let bare = try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(curve: curve,
                surface: plane, options: .init(), tolerance: .standard)
            try numeric(bare, corrected: corrected)
            try rich(PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersectionResult(curve: curve,
                surface: plane, options: .init(), tolerance: .standard), corrected: corrected)
            let callbackBare = try PublicLiftPlanePort.DefaultCurveSurfaceIntersector().intersections(curve: curve,
                surface: plane, options: .init(), tolerance: .standard, maximumSpanCount: 262_144,
                maximumSubdivisionDepth: 8, remainingSourceDepth: 8,
                consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
                maximumAlgebraicDepth: 32)
            try numeric(callbackBare, corrected: corrected)
            try rich(query(curve, plane, Counter()), corrected: corrected)
            if corrected { marker("PASS corrected ordinary standard/callback bare/rich; distinct T, equal nonzero XYZ, source/plane UV and all3 incidents") }
            else { marker("PASS corrected port Coons regression standard/callback bare/rich; distinct T, zero Z/plane U and all12 incidents in8/4 groups") }
        } else if selected == "selections" {
            for (range, count) in [(try ScalarInterval(lower: 1, upper: 1), 1),
                (try ScalarInterval(lower: 0.6, upper: 0.9), 0), (try ScalarInterval(lower: 2, upper: 3), 0)] {
                var options = CurveSurfaceIntersectionOptions(); options.curveRange = range
                let result = try query(curve, plane, Counter(), options: options)
                try PolylineLiftProof.require(result.points.count == count)
                if count == 0 { try empty(result) }
                else {
                    try PolylineLiftProof.require(result.points[0].curveParameter == 1
                        && result.originalIssuedGeometricRelation?.exactPoints.count == 1)
                }
            }
            var options = CurveSurfaceIntersectionOptions(); options.surfaceURange = try .init(lower: 1, upper: 2)
            try empty(query(curve, plane, Counter(), options: options))
            marker("PASS corrected curve singleton/root-free/outside-support selections and plane UV exclusion complete empty")
        } else if selected == "query-work" {
            let finite = Counter(work: 8_388_608, bytes: 8_388_608)
            try rich(query(curve, plane, finite))
            for cap in [1, 1_000_000] {
                let (freshCurve, freshPlane) = try input(), bounded = Counter(work: cap)
                do { _ = try query(freshCurve, freshPlane, bounded); throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
                try PolylineLiftProof.require(bounded.totals.work == cap)
            }
#if hasFeature(Embedded)
            logCount("successfulWork", finite.totals.work)
            logCount("successfulBytes", finite.totals.bytes)
#else
            print("successfulWork", finite.totals.work, "successfulBytes", finite.totals.bytes)
#endif
            marker("PASS corrected finite allowance success; fixed work caps1/1000000 forward typed refusal at exact callback cap")
        } else if selected == "query-storage" {
            try rich(query(curve, plane, counter)); let totals = counter.totals
            let (exactCurve, exactPlane) = try input(), exact = Counter(bytes: totals.bytes)
            try rich(query(exactCurve, exactPlane, exact))
            try PolylineLiftProof.require(exact.totals.bytes == totals.bytes)
            let (shortCurve, shortPlane) = try input()
            do { _ = try query(shortCurve, shortPlane, Counter(bytes: totals.bytes - 1)); throw ExactScalarFailure.invalidEvidence }
            catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
#if hasFeature(Embedded)
            logCount("queryBytes", totals.bytes)
#else
            print("queryBytes", totals.bytes)
#endif
            marker("PASS corrected independent exact storage budget success and one-less typed resource refusal")
        } else if selected == "depth" {
            for depth in [0, 1] {
                do { _ = try query(curve, plane, Counter(), sourceDepth: depth); throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            }
            do { _ = try query(curve, plane, Counter(), algebraicDepth: 0); throw ExactScalarFailure.invalidEvidence }
            catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            for kind in 0..<2 {
                var options = CurveSurfaceIntersectionOptions()
                if kind == 0 { options.maximumCandidateCount = 2 } else { options.maximumPolynomialDegree = 0 }
                do { _ = try query(curve, plane, Counter(), options: options); throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError { try PolylineLiftProof.require(error.code == .resourceLimitExceeded) }
            }
            marker("PASS corrected source/algebraic depth and candidate/polynomial degree typed resource refusal")
        } else if selected == "cancel-entry" {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try query(curve, plane, counter); throw ExactScalarFailure.invalidEvidence }
            catch is CancellationError { }
            try PolylineLiftProof.require(counter.totals.work == 0 && counter.totals.bytes == 0)
            marker("PASS corrected entry Task cancellation before work/storage")
        } else if selected == "cancel-final" {
            try rich(query(curve, plane, counter)); let totals = counter.totals
            let (freshCurve, freshPlane) = try input(), canceled = Counter(cancelStorageAt: totals.bytes)
            do { _ = try query(freshCurve, freshPlane, canceled); throw ExactScalarFailure.invalidEvidence }
            catch is CancellationError { }
            try PolylineLiftProof.require(canceled.totals.bytes == totals.bytes)
            marker("PASS corrected current-Task cancellation at final result storage callback before publication")
        } else if selected == "cancel-callbacks" {
            for tick in [1, 1_000_000] {
                let (freshCurve, freshPlane) = try input(), canceled = Counter(cancelAt: tick)
                do { _ = try query(freshCurve, freshPlane, canceled); throw ExactScalarFailure.invalidEvidence }
                catch is CancellationError { }
                try PolylineLiftProof.require(canceled.totals.work == tick)
            }
            marker("PASS corrected entry/mid work callback cancellation at exact observed ticks")
        } else if selected == "lifetime" {
            let result: Result
            do {
                let (ownedCurve, ownedPlane) = try input()
                result = try query(ownedCurve, ownedPlane, Counter())
                guard case .surfaceLift(let lift) = ownedCurve, case .polyline(let points) = lift.parameterCurve else {
                    throw ExactScalarFailure.invalidEvidence
                }
                var changed = points; changed[2].u = 0.75
                try PolylineLiftProof.require(points[2].u == 0.5 && changed[2].u == 0.75)
            }
            try rich(result)
            try await withThrowingTaskGroup(of: Void.self) { readers in
                for _ in 0..<2 { readers.addTask { try rich(result) } }
                try await readers.waitForAll()
            }
            marker("PASS corrected detached input/result owners, COW source points and concurrent independent exact readers")
        } else { throw ExactScalarFailure.invalidEvidence }
    }
    static func main() async {
        do { try await run() }
        catch {
            marker("FAIL corrected ordinary lift/plane")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}
