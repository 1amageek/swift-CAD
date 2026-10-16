import CADCore
import CADGeometry
import CADModeling
import Synchronization

/// Shared controls call the actual Loft source factory and real geometry converter.
enum LoftPlaneDerivativeOwnershipChecks {
    private struct Failure: Error { let message: String }
    private final class StopAtFirstWork: Sendable {
        private let work = Mutex(0)
        var count: Int { work.withLock { $0 } }
        func record(_ units: Int) { work.withLock { $0 += units } }
        func check() throws {
            let cancelled = work.withLock { $0 > 0 }
            if cancelled { throw CancellationError() }
        }
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    private static let tolerance = ModelingTolerance.standard

    private static func allowance(storage: Int = 268_435_456, work: Int = 80_000_000)
        throws -> OriginalQueryBudget {
        try .init(workLimit: work, storageByteLimit: exactScalarPayloadBytes(count: storage, of: UInt32.self),
            cellLimit: 80_000_000, cellVisitWorkUnits: 0)
    }
    private static func execution(_ budget: OriginalQueryBudget? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try budget ?? allowance(),
            limits: try .init(maximumValueDepth: 64, maximumCoefficientDepth: 64,
                remainingSourceDepth: 32, maximumSubdivisionDepth: 8, maximumSpans: 1))
    }
    private static func isResourceFailure(_ error: any Error) -> Bool {
        OriginalQueryFailure.classification(of: OriginalQueryFailure.published(error,
            context: .unspecified, tolerance: tolerance))?.code == .resourceLimitExceeded
    }
    private static func plane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
    }

    private static func payload() throws -> OriginalPlaneDerivativeSurface3D {
        var usage = try execution()
        func boundary(_ a: Point3D, _ b: Point3D) throws -> OriginalCurveRootSpan3D {
            try .init(source: .bSpline(.init(degree: 1, knots: [0,0,1,1], controlPoints: [a,b])),
                start: .authored(0), end: .authored(1), maximumParameterWidth: tolerance.relative,
                maximumSubdivisionDepth: 0, tolerance: tolerance,
                usage: &usage,
                maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 32)
        }
        let boundaries = try OriginalCoonsSurface3D(
            vMinimumBoundary: boundary(.origin, .init(x: 1,y: 0,z: 0)),
            vMaximumBoundary: boundary(.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)),
            uMinimumBoundary: boundary(.origin, .init(x: 0,y: 1,z: 0)),
            uMaximumBoundary: boundary(.init(x: 1,y: 0,z: 0), .init(x: 1,y: 1,z: 0)),
            tolerance: tolerance, using: &usage)
        let construction = try OriginalBoundaryCorrectedSurface3D(construction: plane(), boundaries: boundaries,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, tolerance: tolerance, using: &usage)
        return try .init(construction: construction, boundaries: boundaries, startConstraints: [],
            endConstraints: [], remainingSourceDepth: 32, tolerance: tolerance, using: &usage)
    }

    private static func certify(_ surface: Surface3D, using admission: inout OriginalQueryExecution)
        throws -> GeometryConversionGuarantee {
        try admission.withProofScope(maximum: ExactScalarDepth(value: 32, coefficient: 32)) { admission in
            let source = try NativeSurfaceConversionSource(surface, tolerance: tolerance, using: &admission)
            return try CertifiedGeometryConverter().certifySurface(
                source: source, candidate: plane(),
                over: .init(u: .init(lower: 0,upper: 1), v: .init(lower: 0,upper: 1)),
                requirements: .init(maximumPositionError: tolerance.distance,
                    maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance,
                    maximumDegree: 3, maximumCertificationBoxes: 256),
                tolerance: tolerance, using: &admission)
        }
    }

    static func admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease() throws {
        let retained: LoftSideSurfaceSource
        let originalHash: Int
        let admitted = try allowance()
        do {
            let original = try payload()
            originalHash = original.hashValue
            var usage = try execution(admitted)
            retained = try .admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                let word = MemoryLayout<UInt32>.stride
                let inner = (MemoryLayout<OriginalPlaneDerivativeSurface3D>.stride + word - 1) / word * word
                let outer = (MemoryLayout<(OriginalPlaneDerivativeSurface3D, ProceduralSurface3D, GeometryConversionGuarantee)>.stride + word - 1) / word * word
                try require(admitted.snapshot.storageBytes == inner + outer, "Loft ownership predicate failed: admitted.snapshot.storageBytes == inner + outer .")
                return try certify(surface, using: &execution)
            }
        }
        let copied = retained
        let first = retained.surface, second = copied.surface
        guard case .originalPlaneDerivative(let keptSource, _, let guarantee) = copied else {
            throw Failure(message: "The copied side lost its original source and conversion guarantee.")
        }
        try require(keptSource.hashValue == originalHash, "Loft ownership predicate failed: keptSource.hashValue == originalHash .")
        try require(guarantee.positionErrorUpperBound.isFinite, "Loft ownership predicate failed: guarantee.positionErrorUpperBound.isFinite .")
        try require(guarantee.tangentAngleUpperBound.isFinite, "Loft ownership predicate failed: guarantee.tangentAngleUpperBound.isFinite .")
        try require(guarantee.curvatureErrorUpperBound.isFinite, "Loft ownership predicate failed: guarantee.curvatureErrorUpperBound.isFinite .")
        try require(guarantee.certifiedBoxCount > 0, "Loft ownership predicate failed: guarantee.certifiedBoxCount > 0 .")
        guard case .procedural(.originalPlaneDerivative(let published)) = first else {
            throw Failure(message: "Publication replaced the original plane-derivative source law.")
        }
        try require(published.hashValue == originalHash, "Loft ownership predicate failed: published.hashValue == originalHash .")
        try require(first == second, "Loft ownership predicate failed: first == second .")
        let point = try first.point(u: 0.5, v: 0.5, tolerance: tolerance)
        try require(point.isApproximatelyEqual(to: .init(x: 0.5,y: 0.5,z: 0), tolerance: tolerance.distance), "Loft ownership predicate failed: point.isApproximatelyEqual(to: .init(x: 0.5,y: 0.5,z: 0), tolerance: tolerance.distance) .")
        try require(try second.point(u: 0.5, v: 0.5, tolerance: tolerance) == point, "Loft ownership predicate failed: try second.point(u: 0.5, v: 0.5, tolerance: tolerance) == point .")
        try require(admitted.snapshot.storageBytes > 0, "Loft ownership predicate failed: admitted.snapshot.storageBytes > 0 .")
    }

    static func eachNewCapacityRefusesBeforeCertification(secondReservation: Bool) throws {
        let original = try payload()
        let word = MemoryLayout<UInt32>.stride
        let payloadWords = (MemoryLayout<OriginalPlaneDerivativeSurface3D>.stride + word - 1) / word
        let fieldWords = (MemoryLayout<(OriginalPlaneDerivativeSurface3D, ProceduralSurface3D, GeometryConversionGuarantee)>.stride + word - 1) / word
        let admitted = try allowance(storage: payloadWords + (secondReservation ? fieldWords : 0) - 1)
        var usage = try execution(admitted)
        var invoked = false
        do {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                invoked = true
                return try certify(surface, using: &execution)
            }
            throw Failure(message: "Exhausted retained capacity unexpectedly published a side source.")
        } catch { try require(isResourceFailure(error), "Loft ownership predicate failed: isResourceFailure(error) .") }
        try require(!invoked, "Loft ownership predicate failed: !invoked .")
        try require(admitted.snapshot.storageBytes / word == (secondReservation ? payloadWords : 0), "Loft ownership predicate failed: admitted.snapshot.storageBytes / word == (secondReservation ? payloadWords : 0) .")
    }

    static func unchangedSourceCasesRetainTheirValuesAndActualLayouts() throws {
        let original = try payload()
        let native = LoftSideSurfaceSource.native(plane())
        let coons = LoftSideSurfaceSource.originalCoons(original.boundaries)
        let corrected = LoftSideSurfaceSource.originalBoundaryCorrected(original.construction)
        try require(native.surface == .bSpline(plane()), "Loft ownership predicate failed: native.surface == .bSpline(plane()) .")
        try require(coons.surface == .procedural(.originalCoons(original.boundaries)), "Loft ownership predicate failed: coons.surface == .procedural(.originalCoons(original.boundaries)) .")
        try require(corrected.surface == .procedural(.originalBoundaryCorrected(original.construction)), "Loft ownership predicate failed: corrected.surface == .procedural(.originalBoundaryCorrected(original.construction)) .")
        let tupleStride = MemoryLayout<(OriginalPlaneDerivativeSurface3D, ProceduralSurface3D, GeometryConversionGuarantee)>.stride
        try require(MemoryLayout<LoftSideSurfaceSource>.stride < tupleStride, "Loft ownership predicate failed: MemoryLayout<LoftSideSurfaceSource>.stride < tupleStride .")
        print("LOFT_SIDE_LAYOUT native=\(MemoryLayout<BSplineSurface3D>.stride) coons=\(MemoryLayout<OriginalCoonsSurface3D>.stride) corrected=\(MemoryLayout<OriginalBoundaryCorrectedSurface3D>.stride) plane=\(MemoryLayout<OriginalPlaneDerivativeSurface3D>.stride) procedural=\(MemoryLayout<ProceduralSurface3D>.stride) guarantee=\(MemoryLayout<GeometryConversionGuarantee>.stride) tuple=\(tupleStride) side=\(MemoryLayout<LoftSideSurfaceSource>.stride)")
    }

    static func actualConverterUsesExactCumulativeStorageBoundary() throws {
        let original = try payload()
        func run(storageByteLimit: Int?) throws -> (LoftSideSurfaceSource, OriginalQueryBudgetSnapshot) {
            let budget = try OriginalQueryBudget(workLimit: 80_000_000,
                storageByteLimit: storageByteLimit, cellLimit: 80_000_000, cellVisitWorkUnits: 0)
            var usage = try execution(budget)
            let result = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                try certify(surface, using: &execution)
            }
            return (result, budget.snapshot)
        }
        let (baseline, measured) = try run(storageByteLimit: nil)
        try require(measured.storageBytes > 0, "Loft ownership predicate failed: measured.storageBytes > 0 .")
        let (exact, accepted) = try run(storageByteLimit: measured.storageBytes)
        try require(accepted.storageBytes == measured.storageBytes, "Loft ownership predicate failed: accepted.storageBytes == measured.storageBytes .")
        try require(accepted.work == measured.work, "Loft ownership predicate failed: accepted.work == measured.work .")
        try require(baseline.surface == exact.surface, "Loft ownership predicate failed: baseline.surface == exact.surface .")
        guard case .originalPlaneDerivative(_, _, let expectedGuarantee) = baseline,
              case .originalPlaneDerivative(_, _, let actualGuarantee) = exact else {
            throw Failure(message: "Exact storage admission changed the retained source family.")
        }
        try require(actualGuarantee.positionErrorUpperBound == expectedGuarantee.positionErrorUpperBound, "Loft ownership predicate failed: actualGuarantee.positionErrorUpperBound == expectedGuarantee.positionErrorUpperBound .")
        try require(actualGuarantee.tangentAngleUpperBound == expectedGuarantee.tangentAngleUpperBound, "Loft ownership predicate failed: actualGuarantee.tangentAngleUpperBound == expectedGuarantee.tangentAngleUpperBound .")
        try require(actualGuarantee.curvatureErrorUpperBound == expectedGuarantee.curvatureErrorUpperBound, "Loft ownership predicate failed: actualGuarantee.curvatureErrorUpperBound == expectedGuarantee.curvatureErrorUpperBound .")
        try require(actualGuarantee.certifiedBoxCount == expectedGuarantee.certifiedBoxCount, "Loft ownership predicate failed: actualGuarantee.certifiedBoxCount == expectedGuarantee.certifiedBoxCount .")
        var published = false
        do {
            _ = try run(storageByteLimit: measured.storageBytes - 1)
            published = true
            throw Failure(message: "N-1 storage published a certified Loft side source.")
        } catch { try require(isResourceFailure(error), "Loft ownership predicate failed: isResourceFailure(error) .") }
        try require(!published, "Loft ownership predicate failed: !published .")
    }

    static func actualConverterFailurePreventsSidePublication() throws {
        let original = try payload()
        let admitted = try allowance(work: 0)
        var usage = try execution(admitted)
        do {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                try certify(surface, using: &execution)
            }
            throw Failure(message: "Exhausted converter work unexpectedly published a side source.")
        } catch {
            try require(isResourceFailure(error), "Converter work refusal lost its original resource failure.")
        }
        try require(admitted.snapshot.work == 0, "Loft ownership predicate failed: admitted.snapshot.work == 0 .")
    }

    static func actualConverterCancellationPreventsSidePublication() throws {
        let original = try payload()
        let cancellation = StopAtFirstWork()
        let admitted = try OriginalQueryBudget(workLimit: 80_000_000,
            storageByteLimit: exactScalarPayloadBytes(count: 268_435_456, of: UInt32.self),
            cellLimit: 80_000_000, cellVisitWorkUnits: 0,
            consumeWorkUnits: { cancellation.record($0) },
            checkpoint: { try cancellation.check() })
        var usage = try execution(admitted)
        var invoked = false
        var published = false
        func originalCause(_ error: any Error) -> any Error {
            if let failure = error as? OriginalQueryFailure { return originalCause(failure.originalError) }
            if let failure = error as? ExactScalarFailure {
                if case .admissionRejected(let cause) = failure { return originalCause(cause) }
                if case .cancelled = failure { return CancellationError() }
            }
            return error
        }
        do {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                invoked = true
                return try certify(surface, using: &execution)
            }
            published = true
            throw Failure(message: "Cancelled conversion published a Loft side source.")
        } catch {
            guard originalCause(error) is CancellationError else { throw error }
        }
        let paidWork = cancellation.count
        try require(invoked && !published, "Actual conversion cancellation did not prevent side publication.")
        try require(paidWork > 0 && admitted.snapshot.work == paidWork && usage.localWork == paidWork,
            "Conversion cancellation lost the same caller's committed work.")
        let point = try original.point(u: 0.5, v: 0.5, tolerance: tolerance)
        try require(point.isApproximatelyEqual(to: .init(x: 0.5, y: 0.5, z: 0), tolerance: tolerance.distance),
            "Conversion cancellation invalidated the retained original source.")
    }
}
