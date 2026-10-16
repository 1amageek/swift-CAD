import CADCore
import Synchronization
@testable import CADGeometry

/// Portable controls for the actual narrow Native boundary correspondence proof.
@main
struct NativeBoundaryPortable {
    enum Failure: Error { case mismatch, missingRefusal }

    static func require(_ condition: Bool, line: UInt32 = #line) throws {
        guard condition else {
            print("FAIL native boundary portable oracle line=\(line)")
            throw Failure.mismatch
        }
    }

    static func originalFailure(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return originalFailure(retained.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let retained) = scalar {
            return originalFailure(retained)
        }
        return error
    }

    static func retainedFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let retained = error as? OriginalQueryFailure { return retained }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let retained) = scalar {
            return retainedFailure(retained)
        }
        return nil
    }

    static func isCancelled(_ error: any Error) -> Bool {
        guard let scalar = originalFailure(error) as? ExactScalarFailure,
              case .cancelled = scalar else { return false }
        return true
    }

    static func expectFailure<Result>(_ predicate: (any Error) -> Bool,
        _ operation: () throws -> Result) throws {
        do { _ = try operation() }
        catch {
            guard predicate(error) else { throw error }
            return
        }
        throw Failure.missingRefusal
    }

    static func nativeArch() -> BSplineSurface3D {
        .init(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [.init(x: 0, y: 0, z: 0.25), .init(x: 0.5, y: 0, z: -0.25), .init(x: 1, y: 0, z: 0.25)],
                [.init(x: 0, y: 1, z: 0.25), .init(x: 0.5, y: 1, z: -0.25), .init(x: 1, y: 1, z: 0.25)]
            ])
    }

    static func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: sourceDepth, maximumTransportDepth: 16,
            maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

    static func boundary(_ index: Int, on surface: BSplineSurface3D,
        using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        if index < 2 {
            return try surface.uIsoparametricCurve(atV: Double(index), tolerance: .standard, using: &execution)
        }
        return try surface.vIsoparametricCurve(atU: Double(index - 2), tolerance: .standard, using: &execution)
    }

    static func chart(_ index: Int, from start: Double, to end: Double) -> SurfaceParameterCurve {
        if index < 2 { return .constantV(v: Double(index), uStart: start, uEnd: end) }
        return .constantU(u: Double(index - 2), vStart: start, vEnd: end)
    }

    static func bound(_ curve: BSplineCurve3D, on surface: BSplineSurface3D,
        from start: Double = 0, to end: Double = 1, chart: SurfaceParameterCurve,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(
            curve: .bSpline(curve), from: start, to: end, surface: .bSpline(surface), parameterCurve: chart,
            options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 1_048_576,
                maximumDeviation: ModelingTolerance.standard.distance * 8),
            tolerance: .standard, maximumSpanCount: 1_048_576, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
    }

    static func isWork(_ error: any Error) -> Bool {
        guard let scalar = originalFailure(error) as? ExactScalarFailure,
              case .resourceLimit(.work) = scalar else { return false }
        return true
    }

    static func allFourBoundariesAndBothStoredAndTraversalDirectionsAreExactlyZero(_ degree: Int) throws {
        var native = nativeArch()
        if degree == 1 {
            native = .bilinearPatch(bottomLeft: .origin, bottomRight: .init(x: 1, y: 0, z: 0),
                topRight: .init(x: 1, y: 1, z: 0), topLeft: .init(x: 0, y: 1, z: 0))
        }
        var preparing = try execution(OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456))
        var query = try execution(OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456))
        for index in 0..<4 {
            let source = try boundary(index, on: native, using: &preparing)
            let reversed = try source.reversed(tolerance: .standard, using: &preparing)
            for storedReverse in [false, true] {
                for traversalReverse in [false, true] {
                    let start = traversalReverse ? 1.0 : 0
                    let end = traversalReverse ? 0.0 : 1
                    let uvStart = storedReverse ? end : start
                    let uvEnd = storedReverse ? start : end
                    let value = try bound(storedReverse ? reversed : source, on: native,
                        from: start, to: end, chart: chart(index, from: uvStart, to: uvEnd), using: &query)
                    try require(value == 0)
                }
            }
        }
    }

    static func nearPayloadAndForeignDirectedMapsCannotMintTheZeroProof(_ variant: Int) throws {
        var preparing = try execution(OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456))
        var native = nativeArch()
        var source = try boundary(0, on: native, using: &preparing)
        let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var measuring = try execution(measured)
        let exact = try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &measuring)
        try require(exact == 0)
        var parameter = chart(0, from: 0, to: 1)
        var start = 0.0, end = 1.0
        switch variant {
        case 0: source.controlPoints[1].z = source.controlPoints[1].z.nextUp
        case 1: source.weights[1] = 1.0.nextUp
        case 2: native.controlPoints[0][1].z = native.controlPoints[0][1].z.nextUp
        case 3: parameter = .constantV(v: ModelingTolerance.standard.distance / 2, uStart: 0, uEnd: 1)
        case 4: parameter = .constantV(v: 0, uStart: 0, uEnd: 1.0.nextDown)
        case 5: parameter = .constantV(v: 0, uStart: 1, uEnd: 0)
        case 6: start = 0.25; end = 0.75
        default:
            for index in 3..<source.knots.count { source.knots[index] = 1.0.nextUp }
        }
        // Only the exact structural law fits this measured work allowance. A
        // mismatch must enter the original proof and propagate its work refusal.
        let budget = try OriginalQueryBudget(workLimit: measured.snapshot.work)
        var query = try execution(budget)
        try expectFailure(isWork) {
            try bound(source, on: native, from: start, to: end, chart: parameter, using: &query)
        }
    }

    static func exactCallerWorkAndBytesAndRetainedInputLifetimeRemainObservable() throws {
        var preparing = try execution(OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456))
        var callerSurface = nativeArch()
        var callerCurve = try boundary(0, on: callerSurface, using: &preparing)
        let surface = callerSurface, curve = callerCurve
        callerSurface.controlPoints[0][1].z = 99
        callerCurve.weights[0] = 2
        try require(surface != callerSurface && curve != callerCurve)
        let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var measuring = try execution(measured)
        let measuredValue = try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &measuring)
        try require(measuredValue == 0)
        let complete = measured.snapshot
        try require(complete.work > 0 && complete.storageBytes > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes)
        var exact = try execution(exactBudget, sourceDepth: 0)
        let exactValue = try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &exact)
        try require(exactValue == 0)
        try require(exactBudget.snapshot.work == complete.work)
        try require(exactBudget.snapshot.storageBytes == complete.storageBytes)
        try expectFailure(isWork) {
            try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &exact)
        }
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? complete.work - 1 : nil,
                storageByteLimit: resource == .storage ? complete.storageBytes - 1 : nil)
            var query = try execution(budget)
            try expectFailure({ error in
                guard let scalar = originalFailure(error) as? ExactScalarFailure,
                      case .resourceLimit(let actual) = scalar else { return false }
                return actual == resource
            }) {
                try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &query)
            }
        }
        // Existing proof-scope metadata is retained by this same execution;
        // the borrowed boundary comparison itself creates no further payload.
        let previous = measured.snapshot
        let repeatedValue = try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &measuring)
        try require(repeatedValue == 0)
        try require(measured.snapshot.work == previous.work + complete.work)
        try require(measured.snapshot.storageBytes == previous.storageBytes)
        let mappedBudget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var mapped = try execution(mappedBudget, sourceDepth: 0)
        try expectFailure({ error in retainedFailure(error)?.context.resource?.axis == .sourceDepth }) {
            try mapped.withSourceDepthOffset(1) { execution in
                try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &execution)
            }
        }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { count in count += 1; return count }
            if ordinal == cancelAt { throw .cancelled }
        }
    }

    static func entryAndTerminalCancellationCannotPublishZero() throws {
        let native = nativeArch()
        var preparing = try execution(OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456))
        let source = try boundary(0, on: native, using: &preparing)
        let checkpoints = Checkpoints()
        let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456, checkpoint: { try checkpoints.checkpoint() })
        var measuring = try execution(measured)
        let measuredValue = try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &measuring)
        try require(measuredValue == 0)
        let complete = measured.snapshot
        try require(checkpoints.count > 1)
        for stop in [1, checkpoints.count] {
            let cancellation = Checkpoints(cancelAt: stop)
            let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456, checkpoint: { try cancellation.checkpoint() })
            var query = try execution(budget)
            try expectFailure(isCancelled) {
                try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &query)
            }
            try require(budget.snapshot.work == (stop == 1 ? 0 : complete.work))
            try require(budget.snapshot.storageBytes == (stop == 1 ? 0 : complete.storageBytes))
        }
    }
    static func main() throws {
        for degree in [1, 2] {
            try allFourBoundariesAndBothStoredAndTraversalDirectionsAreExactlyZero(degree)
        }
        print("PASS native boundary whole closed laws")
        for variant in 0..<8 {
            try nearPayloadAndForeignDirectedMapsCannotMintTheZeroProof(variant)
        }
        print("PASS native boundary exact payload and map refusal")
        try exactCallerWorkAndBytesAndRetainedInputLifetimeRemainObservable()
        print("PASS native boundary caller resources and lifetime")
        try entryAndTerminalCancellationCannotPublishZero()
        print("PASS native boundary cancellation")
        print("PASS native boundary portable all")
    }
}
