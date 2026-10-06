import CADCore
@testable import CADGeometry
import Testing

@Suite("Intersection foundation compilation boundaries")
struct IntersectionFoundationBoundaryTests {
    private struct Admission: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        var storageLimit = 100_000
        mutating func consumeExactWork(_ count: Int) throws {
            try Task.checkCancellation()
            guard count >= 0, count <= 100_000 - work else { throw exhausted() }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0, count <= storageLimit - storage else { throw exhausted() }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws { throw exhausted() }
        mutating func visitCoefficientCell(depth: Int) throws { throw exhausted() }
        private func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "Foundation boundary admission exhausted.")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func byteCallbacksRetainTheSameSynchronizedOwnerAndBudget() throws {
        let usage = try SurfaceSilhouetteUsage(maximumWork: 1_000, maximumCells: 10,
            maximumStorage: 1_000, maximumDepth: 4)
        let copy = usage
        let work = usage.work, storage = usage.storage
        let callback = usage.preparationStorageCallback
        try callback(5)
        #expect(copy.sharesAccountingOwner(with: usage))
        #expect(usage.storage == storage + 2)
        #expect(copy.storage == usage.storage)
        #expect(usage.work == work + 2)
        #expect(throws: KernelError.self) { try callback(4_000) }
        #expect(usage.storage == storage + 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func genericTaylorBorrowProducesActualCoefficientsAndRejectsUnpaidAllocation() throws {
        var usage = Admission()
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let box = SurfaceParameterBox(u: try .init(lower: 2, upper: 4),
                                      v: try .init(lower: 5, upper: 9))
        let vector = try OriginalPolynomialSurfaceTaylor.vector(
            polynomials: [.zero, .zero, one], over: box, throughOrder: 3,
            tolerance: .standard, usage: &usage)
        let normal = try OriginalPolynomialSurfaceTaylor.normalized(vector, usage: &usage)
        let z = try normal.z.coefficient(0, 0)
        #expect(z.lower <= 1 && z.upper >= 1)
        for u in 0...3 { for v in 0...(3 - u) where u + v > 0 {
            let derivative = try normal.z.coefficient(u, v)
            #expect(derivative.lower <= 0 && derivative.upper >= 0)
        } }
        #expect(usage.storage > 0)
        usage.storageLimit = usage.storage
        #expect(throws: KernelError.self) {
            _ = try OriginalPolynomialSurfaceTaylor.normalized(vector, usage: &usage)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedToleranceCannotBeReplacedByAQuery() throws {
        let surface = Surface3D.plane(.init(origin: .origin, normal: .unitZ))
        let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        try prepared.validatePreparationTolerance(.standard)
        let changed = ModelingTolerance(distance: ModelingTolerance.standard.distance * 2,
            angle: ModelingTolerance.standard.angle, relative: ModelingTolerance.standard.relative)
        #expect(throws: GeometryConversionError.self) {
            try prepared.validatePreparationTolerance(changed)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeFieldTaylorEvaluationUsesTheLiveInvocationOwner() throws {
        let source = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .init(x: 1, y: 0, z: 0)],
                            [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let surface = Surface3D.bSpline(source)
        let box = SurfaceParameterBox(u: try .init(lower: 0, upper: 1),
                                      v: try .init(lower: 0, upper: 1))
        var usage = try SurfaceSilhouetteUsage(maximumWork: 1_000_000, maximumCells: 1_000,
            maximumStorage: 1_000_000, maximumDepth: 8)
        let observer = usage
        let authority = try SurfaceSilhouetteSourcePreparation(original: surface,
            tolerance: .standard, usage: &usage)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: .standard, consumeWork: usage.preparationWorkCallback,
            consumeStorage: usage.preparationStorageCallback)
        let native = try #require(prepared.originalNativeSpans(over: box, tolerance: .standard,
            maximumSpanCount: 4, consumeWork: usage.preparationWorkCallback,
            consumeStorage: usage.preparationStorageCallback).first)
        let field = try OriginalSurfaceSilhouetteField(surface: surface, domain: box,
            view: .unitZ, tolerance: .standard, sourceAuthority: authority,
            native: native, usage: &usage)
        let before = observer.storage
        let value = try field.evaluate(over: box, usage: &usage)
        #expect(value.scalar.value.lower <= 1 && value.scalar.value.upper >= 1)
        #expect(observer.storage > before)
        #expect(observer.work == usage.work && observer.storage == usage.storage)
    }
}
