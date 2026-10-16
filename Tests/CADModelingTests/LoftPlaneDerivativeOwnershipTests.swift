import CADCore
import CADGeometry
import Testing
@testable import CADModeling

@Suite("Loft retained plane derivative publication")
struct LoftPlaneDerivativeOwnershipTests {
    private let tolerance = ModelingTolerance.standard

    private func allowance(storage: Int = 268_435_456, work: Int = 80_000_000)
        throws -> OriginalQueryBudget {
        try .init(workLimit: work, storageByteLimit: exactScalarPayloadBytes(count: storage, of: UInt32.self),
            cellLimit: 80_000_000, cellVisitWorkUnits: 0)
    }
    private func execution(_ budget: OriginalQueryBudget? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try budget ?? allowance(),
            limits: try .init(maximumValueDepth: 64, maximumCoefficientDepth: 64,
                remainingSourceDepth: 32, maximumSubdivisionDepth: 8, maximumSpans: 1))
    }
    private func isResourceFailure(_ error: any Error) -> Bool {
        OriginalQueryFailure.classification(of: OriginalQueryFailure.published(error,
            context: .unspecified, tolerance: tolerance))?.code == .resourceLimitExceeded
    }
    private func plane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
    }

    private func payload() throws -> OriginalPlaneDerivativeSurface3D {
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

    private func certify(_ surface: Surface3D, using admission: inout OriginalQueryExecution)
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

    @Test(.timeLimit(.minutes(1)))
    func admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease() throws {
        let retained: LoftSideSurfaceSource
        let originalHash: Int
        let admitted = try allowance()
        do {
            let original = try payload()
            originalHash = original.hashValue
            var usage = try execution(admitted)
            retained = try .admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                try certify(surface, using: &execution)
            }
        }
        let first = retained.surface, second = retained.surface
        guard case .procedural(.originalPlaneDerivative(let published)) = first else {
            Issue.record("Publication replaced the original plane-derivative source law.")
            return
        }
        #expect(published.hashValue == originalHash)
        #expect(first == second)
        let point = try first.point(u: 0.5, v: 0.5, tolerance: tolerance)
        #expect(point.isApproximatelyEqual(to: .init(x: 0.5,y: 0.5,z: 0), tolerance: tolerance.distance))
        #expect(try second.point(u: 0.5, v: 0.5, tolerance: tolerance) == point)
        #expect(admitted.snapshot.storageBytes > 0)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func eachNewCapacityRefusesBeforeCertification(secondReservation: Bool) throws {
        let original = try payload()
        let word = MemoryLayout<UInt32>.stride
        let payloadWords = (MemoryLayout<OriginalPlaneDerivativeSurface3D>.stride + word - 1) / word
        let fieldWords = (MemoryLayout<ProceduralSurface3D>.stride + word - 1) / word
        let admitted = try allowance(storage: payloadWords + (secondReservation ? fieldWords : 0) - 1)
        var usage = try execution(admitted)
        var invoked = false
        do {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                invoked = true
                return try certify(surface, using: &execution)
            }
            Issue.record("Exhausted retained capacity unexpectedly published a side source.")
        } catch { #expect(isResourceFailure(error)) }
        #expect(!invoked)
        #expect(admitted.snapshot.storageBytes / word == (secondReservation ? payloadWords : 0))
    }

    @Test(.timeLimit(.minutes(1)))
    func actualConverterFailurePreventsSidePublication() throws {
        let original = try payload()
        let admitted = try allowance(work: 0)
        var usage = try execution(admitted)
        #expect {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface, execution in
                try certify(surface, using: &execution)
            }
        } throws: { isResourceFailure($0) }
        #expect(admitted.snapshot.work == 0)
    }
}
