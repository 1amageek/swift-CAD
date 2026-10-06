import CADCore
import Testing
import Synchronization
@testable import CADGeometry

@Suite("Original boundary correction identity")
struct OriginalBoundaryCorrectionIdentityTests {
    private let tolerance = ModelingTolerance.standard

    private func allowance(storage: Int = 268_435_456) throws -> NativeRationalSourceAllowance {
        try .init(maximumWork: 80_000_000, maximumCells: 80_000_000,
            maximumStorage: storage, maximumDepth: 64, operationCheck: {})
    }

    private func plane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
    }

    private func boundaries(nonzero: Bool = false) throws -> OriginalCoonsSurface3D {
        var usage = try allowance()
        func span(_ points: [Point3D], degree: Int = 1) throws -> OriginalCurveRootSpan3D {
            let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
            return try .init(source: .bSpline(.init(degree: degree, knots: knots, controlPoints: points)),
                start: .authored(0), end: .authored(1), maximumParameterWidth: tolerance.relative,
                maximumSubdivisionDepth: 0, tolerance: tolerance,
                storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 32)
        }
        let bottom = nonzero
            ? try span([.origin, .init(x: 0.5,y: 0,z: 0.25), .init(x: 1,y: 0,z: 0)], degree: 2)
            : try span([.origin, .init(x: 1,y: 0,z: 0)])
        return try .init(vMinimumBoundary: bottom,
            vMaximumBoundary: span([.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]),
            uMinimumBoundary: span([.origin, .init(x: 0,y: 1,z: 0)]),
            uMaximumBoundary: span([.init(x: 1,y: 0,z: 0), .init(x: 1,y: 1,z: 0)]),
            tolerance: tolerance, usage: &usage)
    }

    private func corrected(_ boundaries: OriginalCoonsSurface3D,
        usage: inout NativeRationalSourceAllowance) throws -> OriginalBoundaryCorrectedSurface3D {
        try .init(construction: plane(), boundaries: boundaries, maximumSpanCount: 1,
            maximumSubdivisionDepth: 0, tolerance: tolerance, usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func completeIdentityUsesOriginalNativeWholeSquareDerivatives() throws {
        let boundary = try boundaries()
        var usage = try allowance()
        let source = try corrected(boundary, usage: &usage)
        let admitted = usage
        let jet = try source.intervalTaylorJet(over: .init(u: .init(lower: 0,upper: 1),
                v: .init(lower: 0,upper: 1)), throughOrder: 2, tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { try admitted.consumeExactWork(1) },
            consumeStorage: { try admitted.retainExactStorage(($0 + 3) / 4) })
        let du = try jet.x.coefficient(1, 0), dv = try jet.y.coefficient(0, 1)
        #expect(du.lower <= 1 && du.upper >= 1 && du.upper - du.lower < tolerance.distance)
        #expect(dv.lower <= 1 && dv.upper >= 1 && dv.upper - dv.lower < tolerance.distance)
        let mixed = try jet.x.coefficient(1, 1)
        #expect(mixed.lower <= 0 && mixed.upper >= 0 && mixed.upper - mixed.lower < tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func finalWitnessCapacityRefusesBeforePublication() throws {
        let boundary = try boundaries()
        var admitted = try allowance()
        _ = try corrected(boundary, usage: &admitted)
        let total = try admitted.snapshot().storage
        var insufficient = try allowance(storage: total - 1)
        #expect(throws: KernelError.self) { _ = try corrected(boundary, usage: &insufficient) }
        #expect(try insufficient.snapshot().storage == total - 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func finalNativeQueryCallbackCancellationPreventsZeroCorrectionPublication() async throws {
        let boundary = try boundaries()
        var construction = try allowance()
        let source = try corrected(boundary, usage: &construction)
        func query(_ callback: () throws -> Void) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try withoutActuallyEscaping(callback) { callback in
                try source.intervalTaylorJet(over: .init(u: .init(lower: 0,upper: 1),
                    v: .init(lower: 0,upper: 1)), throughOrder: 2, tolerance: tolerance,
                    maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                    consumeWork: callback, consumeStorage: { _ in try callback() })
            }
        }
        let baseline = Mutex(0)
        _ = try query { baseline.withLock { $0 += 1 } }
        let lastOrdinal = baseline.withLock { $0 }
        #expect(lastOrdinal > 0)
        let count = Mutex(0)
        let operation = Task {
            try query {
                let isLast = count.withLock { count in count += 1; return count == lastOrdinal }
                if isLast { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await operation.value
            Issue.record("A final native query callback cancelled but published zero-correction bounds.")
        } catch is CancellationError {
            #expect(count.withLock { $0 } == lastOrdinal)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func differentOriginalBoundaryRetainsItsNonzeroCorrection() throws {
        let boundary = try boundaries(nonzero: true)
        var usage = try allowance()
        let source = try corrected(boundary, usage: &usage)
        #expect(source.boundaries == boundary)
        let atBoundary = try source.point(u: 0.5, v: 0, tolerance: tolerance)
        #expect(abs(atBoundary.z - 0.125) <= tolerance.distance)
        let atInterior = try source.point(u: 0.5, v: 0.5, tolerance: tolerance)
        #expect(abs(atInterior.z - 0.0625) <= tolerance.distance)
        #expect(atInterior.z > 0)
    }
}
