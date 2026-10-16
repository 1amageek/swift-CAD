import CADCore
@testable import CADGeometry
import Testing

@Suite("Intersection foundation compilation boundaries")
struct IntersectionFoundationBoundaryTests {
    private struct Admission: ~Copyable, GeometryScalarTestAdmission {
        var proofScopes = ExactScalarProofScopes()
        var work = 0
        var storage = 0
        var storageLimit = 100_000
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try checkpoint()
            try proofScopes.checkWork(count)
            do {
            try Task.checkCancellation()
            guard count >= 0, count <= 100_000 - work else { throw exhausted() }
            work += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            proofScopes.recordWork(count)
            try checkpoint()
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint()
            let count = try geometryTestStorageWords(bytes)
            do {
            guard count >= 0, count <= storageLimit - storage else { throw exhausted() }
            storage += count
        
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
        
        
        private func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                  message: "Foundation boundary admission exhausted.")
        }
            mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try admitDepth(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            let mapped = try proofScopes.mapped(value: axis == .value ? depth : 0, coefficient: axis == .coefficient ? depth : 0)
            do {
                switch (axis == .coefficient || proofScopes.exactDepthResource == .coefficientDepth) ? ExactScalarRootAxis.coefficient : .value {
                case .value:
                    let depth = mapped.value
 throw exhausted() 
                case .coefficient:
                    let depth = mapped.coefficient
 throw exhausted() 
                }
            } catch let error as ExactScalarFailure { throw error }
            catch { throw .admissionRejected(error) }
            try checkpoint()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func byteCallbacksRetainTheSameSynchronizedOwnerAndBudget() throws {
        let usage = try SurfaceSilhouetteContext(maximumWork: 1_000, maximumCells: 10,
            maximumStorage: 1_000, maximumDepth: 4)
        let copy = usage
        var execution = try usage.execution()
        let work = usage.work, storage = usage.storage
        try usage.withExecution(using: &execution) { execution in try execution.retainStorage(bytes: 5) }
        #expect(copy.sharesAccountingOwner(with: usage))
        #expect(usage.storage == storage + 2)
        #expect(copy.storage == usage.storage)
        #expect(usage.work == work + 2)
        geometryTestExpectFailure({ OriginalQueryFailure.classification(of: $0)?.code == .resourceLimitExceeded }) {
            try copy.withExecution(using: &execution) { execution in try execution.retainStorage(bytes: 4_000) }
        }
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
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is KernelError }) {
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
        geometryTestExpectFailure({ geometryTestOriginalFailure($0) is GeometryConversionError }) {
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
        let observer = try SurfaceSilhouetteContext(maximumWork: 1_000_000, maximumCells: 1_000,
            maximumStorage: 1_000_000, maximumDepth: 8)
        var usage = try observer.execution()
        let authority = try SurfaceSilhouetteSourcePreparation(original: surface,
            tolerance: .standard, usage: &usage)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
            tolerance: .standard, using: &usage)
        let native = try geometryTestRequire(prepared.originalNativeSpans(over: box, tolerance: .standard,
            maximumSpanCount: 4, using: &usage).first)
        let field = try OriginalSurfaceSilhouetteField(surface: surface, domain: box,
            view: .unitZ, tolerance: .standard, sourceAuthority: authority,
            native: native, usage: &usage)
        let before = observer.storage
        let value = try field.evaluate(over: box, usage: &usage)
        #expect(value.scalar.value.lower <= 1 && value.scalar.value.upper >= 1)
        #expect(observer.storage > before)
        let active = try geometryTestRequire(usage.activeContributionHandle)
        #expect(active.budget === observer.budget)
        #expect(observer.work == active.snapshot.work)
        #expect(observer.contribution.snapshot.storageBytes == active.snapshot.storageBytes)
    }
}
