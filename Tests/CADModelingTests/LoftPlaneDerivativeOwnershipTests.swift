import CADCore
import CADGeometry
import Testing
@testable import CADModeling

@Suite("Loft retained plane derivative publication")
struct LoftPlaneDerivativeOwnershipTests {
    private let tolerance = ModelingTolerance.standard

    private func allowance(storage: Int = 268_435_456, work: Int = 80_000_000)
        throws -> NativeRationalSourceAllowance {
        try .init(maximumWork: work, maximumCells: 80_000_000,
            maximumStorage: storage, maximumDepth: 64, operationCheck: {})
    }

    private func plane() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
    }

    private func payload() throws -> OriginalPlaneDerivativeSurface3D {
        var usage = try allowance()
        func boundary(_ a: Point3D, _ b: Point3D) throws -> OriginalCurveRootSpan3D {
            try .init(source: .bSpline(.init(degree: 1, knots: [0,0,1,1], controlPoints: [a,b])),
                start: .authored(0), end: .authored(1), maximumParameterWidth: tolerance.relative,
                maximumSubdivisionDepth: 0, tolerance: tolerance,
                storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 32)
        }
        let boundaries = try OriginalCoonsSurface3D(
            vMinimumBoundary: boundary(.origin, .init(x: 1,y: 0,z: 0)),
            vMaximumBoundary: boundary(.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)),
            uMinimumBoundary: boundary(.origin, .init(x: 0,y: 1,z: 0)),
            uMaximumBoundary: boundary(.init(x: 1,y: 0,z: 0), .init(x: 1,y: 1,z: 0)),
            tolerance: tolerance, usage: &usage)
        let construction = try OriginalBoundaryCorrectedSurface3D(construction: plane(), boundaries: boundaries,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, tolerance: tolerance, usage: &usage)
        return try .init(construction: construction, boundaries: boundaries, startConstraints: [],
            endConstraints: [], remainingSourceDepth: 32, tolerance: tolerance, usage: &usage)
    }

    private func certify(_ surface: Surface3D, allowance: NativeRationalSourceAllowance)
        throws -> GeometryConversionGuarantee {
        let admission = try GeometryConversionAdmission(maximumSpanCount: 1, maximumSubdivisionDepth: 8,
            remainingSourceDepth: 32, consumeWork: { try allowance.consumeExactWork($0) },
            consumeStorage: { bytes in
                let rounded = bytes.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
                guard bytes >= 0, !rounded.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Loft ownership proof byte count overflowed.")
                }
                try allowance.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
            }, maximumAlgebraicDepth: 32)
        return try CertifiedGeometryConverter().certifySurface(
            source: NativeSurfaceConversionSource(surface, tolerance: tolerance, admission: admission),
            candidate: plane(), over: .init(u: .init(lower: 0,upper: 1), v: .init(lower: 0,upper: 1)),
            requirements: .init(maximumPositionError: tolerance.distance,
                maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance,
                maximumDegree: 3, maximumCertificationBoxes: 256),
            tolerance: tolerance, admission: admission)
    }

    @Test(.timeLimit(.minutes(1)))
    func admittedFactoryRetainsRepeatedSurfaceAfterLocalRelease() throws {
        let retained: LoftSideSurfaceSource
        let originalHash: Int
        let admitted = try allowance()
        do {
            let original = try payload()
            originalHash = original.hashValue
            var usage = admitted
            retained = try .admittingOriginalPlaneDerivative(original, usage: &usage) {
                try certify($0, allowance: admitted)
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
        #expect(try admitted.snapshot().storage > 0)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func eachNewCapacityRefusesBeforeCertification(secondReservation: Bool) throws {
        let original = try payload()
        let word = MemoryLayout<UInt32>.stride
        let payloadWords = (MemoryLayout<OriginalPlaneDerivativeSurface3D>.stride + word - 1) / word
        let fieldWords = (MemoryLayout<ProceduralSurface3D>.stride + word - 1) / word
        let admitted = try allowance(storage: payloadWords + (secondReservation ? fieldWords : 0) - 1)
        var usage = admitted
        var invoked = false
        do {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) { surface in
                invoked = true
                return try certify(surface, allowance: admitted)
            }
            Issue.record("Exhausted retained capacity unexpectedly published a side source.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        #expect(!invoked)
        #expect(try usage.snapshot().storage == (secondReservation ? payloadWords : 0))
    }

    @Test(.timeLimit(.minutes(1)))
    func actualConverterFailurePreventsSidePublication() throws {
        let original = try payload()
        let admitted = try allowance(work: 0)
        var usage = admitted
        #expect(throws: KernelError.self) {
            _ = try LoftSideSurfaceSource.admittingOriginalPlaneDerivative(original, usage: &usage) {
                try certify($0, allowance: admitted)
            }
        }
        #expect(try admitted.snapshot().work == 0)
    }
}
