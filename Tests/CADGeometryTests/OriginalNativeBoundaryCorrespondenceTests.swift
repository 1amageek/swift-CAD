import CADCore
import Foundation
import Testing
import Synchronization
@testable import CADGeometry

@Suite("Original native boundary correspondence")
struct OriginalNativeBoundaryCorrespondenceTests {
    private func stage(_ name: String) throws {
        let data = Data("NATIVE_CORRESPONDENCE_STAGE main=\(Thread.isMainThread) \(name)\n".utf8)
        FileHandle.standardError.write(data)
        if let path = ProcessInfo.processInfo.environment["G01_DIAGNOSTIC_STAGE_LOG"] {
            let output = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            do {
                _ = try output.seekToEnd()
                try output.write(contentsOf: data)
            } catch {
                try output.close()
                throw error
            }
            try output.close()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeArchBottomIsoUsesActualBoundedCorrespondence() throws {
        try stage("setup.begin")
        let tolerance = ModelingTolerance.standard
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumTransportDepth: 16,
                maximumSubdivisionDepth: 32, maximumSpans: 64))
        // The original stored binary controls author exactly z = (u - 1/2)^2.
        let native = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [.init(x: 0, y: 0, z: 0.25), .init(x: 0.5, y: 0, z: -0.25), .init(x: 1, y: 0, z: 0.25)],
                [.init(x: 0, y: 1, z: 0.25), .init(x: 0.5, y: 1, z: -0.25), .init(x: 1, y: 1, z: 0.25)]
            ])
        let bottom = try native.uIsoparametricCurve(atV: 0, tolerance: tolerance, using: &execution)
        #expect(bottom.degree == native.uDegree)
        #expect(bottom.knots == native.uKnots)
        #expect(bottom.controlPoints == native.controlPoints[0])
        #expect(bottom.weights == native.weights[0])
        #expect(bottom.isPeriodic == native.isUPeriodic)
        #expect(bottom.periodicOrigin == native.uPeriodicOrigin)
        #expect(bottom.domain == .closed(0, 1))
        let prepared = budget.snapshot
        try stage("setup.end work=\(prepared.work) bytes=\(prepared.storageBytes)")
        try stage("bound.begin")
        do {
            let deviation = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(
                curve: .bSpline(bottom), from: 0, to: 1, surface: .bSpline(native),
                parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1),
                options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 1_048_576,
                    maximumDeviation: tolerance.distance * 8),
                tolerance: tolerance, maximumSpanCount: 1_048_576, maximumSubdivisionDepth: 32,
                remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
            let complete = budget.snapshot
            try stage("bound.end deviation=\(deviation) work=\(complete.work) bytes=\(complete.storageBytes)")
            #expect(deviation == 0)
        } catch {
            let failed = budget.snapshot
            try stage("bound.failure error=\(error) work=\(failed.work) bytes=\(failed.storageBytes)")
            throw error
        }
    }

    private func nativeArch() -> BSplineSurface3D {
        .init(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [.init(x: 0, y: 0, z: 0.25), .init(x: 0.5, y: 0, z: -0.25), .init(x: 1, y: 0, z: 0.25)],
                [.init(x: 0, y: 1, z: 0.25), .init(x: 0.5, y: 1, z: -0.25), .init(x: 1, y: 1, z: 0.25)]
            ])
    }

    private func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: sourceDepth, maximumTransportDepth: 16,
            maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

    private func boundary(_ index: Int, on surface: BSplineSurface3D,
        using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        if index < 2 {
            return try surface.uIsoparametricCurve(atV: Double(index), tolerance: .standard, using: &execution)
        }
        return try surface.vIsoparametricCurve(atU: Double(index - 2), tolerance: .standard, using: &execution)
    }

    private func chart(_ index: Int, from start: Double, to end: Double) -> SurfaceParameterCurve {
        if index < 2 { return .constantV(v: Double(index), uStart: start, uEnd: end) }
        return .constantU(u: Double(index - 2), vStart: start, vEnd: end)
    }

    private func bound(_ curve: BSplineCurve3D, on surface: BSplineSurface3D,
        from start: Double = 0, to end: Double = 1, chart: SurfaceParameterCurve,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(
            curve: .bSpline(curve), from: start, to: end, surface: .bSpline(surface), parameterCurve: chart,
            options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 1_048_576,
                maximumDeviation: ModelingTolerance.standard.distance * 8),
            tolerance: .standard, maximumSpanCount: 1_048_576, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
    }

    private func isWork(_ error: any Error) -> Bool {
        guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
              case .resourceLimit(.work) = scalar else { return false }
        return true
    }

    @Test(.timeLimit(.minutes(1)), arguments: [1, 2])
    func allFourBoundariesAndBothStoredAndTraversalDirectionsAreExactlyZero(_ degree: Int) throws {
        var native = nativeArch()
        if degree == 1 {
            native = .bilinearPatch(bottomLeft: .origin, bottomRight: .init(x: 1, y: 0, z: 0),
                topRight: .init(x: 1, y: 1, z: 0), topLeft: .init(x: 0, y: 1, z: 0))
        }
        var preparing = try execution(OriginalQueryBudget())
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
                    #expect(value == 0)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: Array(0..<8))
    func nearPayloadAndForeignDirectedMapsCannotMintTheZeroProof(_ variant: Int) throws {
        var preparing = try execution(OriginalQueryBudget())
        var native = nativeArch()
        var source = try boundary(0, on: native, using: &preparing)
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        let exact = try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &measuring)
        #expect(exact == 0)
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
        geometryTestExpectFailure(isWork) {
            try bound(source, on: native, from: start, to: end, chart: parameter, using: &query)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactCallerWorkAndBytesAndRetainedInputLifetimeRemainObservable() throws {
        var preparing = try execution(OriginalQueryBudget())
        var callerSurface = nativeArch()
        var callerCurve = try boundary(0, on: callerSurface, using: &preparing)
        let surface = callerSurface, curve = callerCurve
        callerSurface.controlPoints[0][1].z = 99
        callerCurve.weights[0] = 2
        #expect(surface != callerSurface && curve != callerCurve)
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        let measuredValue = try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &measuring)
        #expect(measuredValue == 0)
        let complete = measured.snapshot
        #expect(complete.work > 0 && complete.storageBytes > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes)
        var exact = try execution(exactBudget, sourceDepth: 0)
        let exactValue = try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &exact)
        #expect(exactValue == 0)
        #expect(exactBudget.snapshot.work == complete.work)
        #expect(exactBudget.snapshot.storageBytes == complete.storageBytes)
        geometryTestExpectFailure(isWork) {
            try bound(curve, on: surface, chart: chart(0, from: 0, to: 1), using: &exact)
        }
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? complete.work - 1 : nil,
                storageByteLimit: resource == .storage ? complete.storageBytes - 1 : nil)
            var query = try execution(budget)
            geometryTestExpectFailure({ error in
                guard let scalar = geometryTestOriginalFailure(error) as? ExactScalarFailure,
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
        #expect(repeatedValue == 0)
        #expect(measured.snapshot.work == previous.work + complete.work)
        #expect(measured.snapshot.storageBytes == previous.storageBytes)
        let mappedBudget = try OriginalQueryBudget()
        var mapped = try execution(mappedBudget, sourceDepth: 0)
        geometryTestExpectFailure({ error in geometryTestQueryFailure(error)?.context.resource?.axis == .sourceDepth }) {
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

    @Test(.timeLimit(.minutes(1)))
    func entryAndTerminalCancellationCannotPublishZero() throws {
        let native = nativeArch()
        var preparing = try execution(OriginalQueryBudget())
        let source = try boundary(0, on: native, using: &preparing)
        let checkpoints = Checkpoints()
        let measured = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
        var measuring = try execution(measured)
        let measuredValue = try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &measuring)
        #expect(measuredValue == 0)
        let complete = measured.snapshot
        #expect(checkpoints.count > 1)
        for stop in [1, checkpoints.count] {
            let cancellation = Checkpoints(cancelAt: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() })
            var query = try execution(budget)
            geometryTestExpectFailure(geometryTestIsCancelled) {
                try bound(source, on: native, chart: chart(0, from: 0, to: 1), using: &query)
            }
            #expect(budget.snapshot.work == (stop == 1 ? 0 : complete.work))
            #expect(budget.snapshot.storageBytes == (stop == 1 ? 0 : complete.storageBytes))
        }
    }
}
