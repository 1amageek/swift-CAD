import Testing
import CADCore
@testable import CADGeometry

@Suite("Source-bound rational world silhouette authority")
struct SurfaceSilhouetteRationalWordAuthorityTests {
    enum Image: CaseIterable, Sendable { case identity, affine, nested }
    private func native() -> BSplineSurface3D {
        .init(uDegree: 2,vDegree: 1,uKnots: [0,0,0,1,1,1],vKnots: [0,0,1,1],
            controlPoints: [
                [.init(x: 0,y: 0,z: 0.25),.init(x: 0.5,y: 0,z: -0.25),.init(x: 1,y: 0,z: 0.25)],
                [.init(x: 0,y: 1,z: 0.25),.init(x: 0.5,y: 1,z: -0.25),.init(x: 1,y: 1,z: 0.25)]])
    }
    private func execution(_ budget: OriginalQueryBudget, coefficientDepth: Int = 32) throws -> OriginalQueryExecution {
        .init(budget: budget,limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: coefficientDepth,remainingSourceDepth: 16,
            maximumTransportDepth: 16,maximumSubdivisionDepth: 32,maximumSpans: 64))
    }
    private func field(_ image: Image, offset: Bool = false,
        using usage: inout OriginalQueryExecution) throws -> OriginalSurfaceSilhouetteField {
        let transform: AffineTransform3D
        if image == .identity {
            transform = try .init(basisX: .unitX,basisY: .unitY,basisZ: .unitZ,translation: .zero)
        } else {
            transform = try .init(basisX: .init(x: 2,y: 0,z: 1),basisY: .init(x: 0,y: 3,z: 1),
                basisZ: .init(x: 1,y: 0,z: 4),translation: .init(x: 3,y: -2,z: 5))
        }
        var surface = Surface3D.bSpline(native())
        let word = try OriginalAffineOperationWord(factors: [.forward(transform)],
            tolerance: .standard,maximumDepth: 32,usage: &usage)
        surface = .procedural(.originalAffineWord(try .init(source: surface,operationWord: word,
            tolerance: .standard,remainingSourceDepth: 16,maximumSubdivisionDepth: 32,
            maximumAlgebraicDepth: 32,usage: &usage)))
        if image == .nested {
            let outer = try AffineTransform3D(basisX: .unitX,basisY: .unitY,basisZ: .unitZ,
                translation: .init(x: 1,y: 2,z: 3))
            let outerWord = try OriginalAffineOperationWord(factors: [.forward(outer)],
                tolerance: .standard,maximumDepth: 32,usage: &usage)
            surface = .procedural(.originalAffineWord(try .init(source: surface,operationWord: outerWord,
                tolerance: .standard,remainingSourceDepth: 16,maximumSubdivisionDepth: 32,
                maximumAlgebraicDepth: 32,usage: &usage)))
        }
        if offset { surface = .procedural(.offset(.init(source: surface,distance: 0))) }
        try surface.validateOriginalSource(tolerance: .standard,remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32,maximumAlgebraicDepth: 32,using: &usage)
        let source = try SurfaceSilhouetteSourcePreparation(original: surface,tolerance: .standard,usage: &usage)
        let nativeSource = try #require(source.nativeSource)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: nativeSource,
            tolerance: source.nativeTolerance,using: &usage)
        let domain = SurfaceParameterBox(u: try .init(lower: 0,upper: 1),v: try .init(lower: 0,upper: 1))
        let spans = try prepared.originalNativeSpans(over: domain,tolerance: source.nativeTolerance,
            maximumSpanCount: 4,using: &usage)
        let span = try #require(spans.first)
        #expect(spans.count == 1)
        return try .init(surface: surface,domain: domain,view: .unitX,tolerance: .standard,
            sourceAuthority: source,native: span,usage: &usage)
    }
    private func value(_ polynomial: ExactBivariatePolynomial, u: Double, v: Double,
        using usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        try polynomial.evaluated(atU: .originalDouble(u,usage: &usage),
            v: .originalDouble(v,usage: &usage),usage: &usage)
    }
    @Test(arguments: Image.allCases)
    func worldCoefficientsRetainTheFullOriginalWordAndNativeBasis(_ image: Image) throws {
        var usage = try execution(OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456))
        let original = try field(image,using: &usage)
        let selected = try original.retainingCommonOriginalFieldAuthority(usage: &usage)
        let capability = try #require(selected.projectedRationalAuthority)
        let base = try #require(selected.exactSourcePolynomial)
        #expect(capability.polynomial.source == native())
        #expect(base.source == native())
        #expect(capability.polynomial.domain == base.domain)
        #expect(capability.polynomial.uSpanIndex == base.uSpanIndex)
        #expect(capability.polynomial.vSpanIndex == base.vSpanIndex)
        #expect(selected.fieldZeroSetAuthority == nil)
        #expect(selected.surface == original.surface)
        let expected: [Double]
        let normal: [Double]
        let station: Double
        switch image {
        case .identity: expected = [0.25,0.75,0.0625]; normal = [0.5,0,1]; station = 0.5
        case .affine: expected = [57.0/16,0.25,25.0/4]; normal = [3,-1.5,4.5]; station = 0.375
        case .nested: expected = [73.0/16,2.25,37.0/4]; normal = [3,-1.5,4.5]; station = 0.375
        }
        for axis in 0..<3 {
            let actual = try value(capability.polynomial.homogeneous[axis],u: 0.25,v: 0.75,using: &usage)
            let target = try ExactRationalCoefficient.originalDouble(expected[axis],usage: &usage)
            #expect(actual == target)
            let actualNormal = try value(capability.polynomial.normalNumerators[axis],u: 0.25,v: 0.75,using: &usage)
            #expect(actualNormal == (try .originalDouble(normal[axis],usage: &usage)))
        }
        #expect(try value(base.homogeneous[0],u: 0.25,v: 0.75,using: &usage) == .originalDouble(0.25,usage: &usage))
        #expect(try value(base.homogeneous[2],u: 0.25,v: 0.75,using: &usage) == .originalDouble(0.0625,usage: &usage))
        #expect(try value(capability.zeroLaw,u: station,v: 0.75,using: &usage).isZero)
        if image != .identity { #expect(!(try value(capability.zeroLaw,u: 0.5,v: 0.75,using: &usage)).isZero) }
        let box = SurfaceParameterBox(u: try .init(lower: 0.25,upper: 0.25),v: try .init(lower: 0.75,upper: 0.75))
        let jet = try selected.evaluate(over: box,usage: &usage)
        for (axis,bounds) in [jet.spatial.x.value,jet.spatial.y.value,jet.spatial.z.value].enumerated() {
            #expect(bounds.lower <= expected[axis] && bounds.upper >= expected[axis])
        }
        let expectedU: [Double] = image == .identity ? [1,0,-0.5] : [1.5,0,-1]
        let expectedV: [Double] = image == .identity ? [0,1,0] : [0,3,1]
        let expectedUU: [Double] = image == .identity ? [0,0,2] : [2,0,8]
        for (axis,coordinate) in [jet.spatial.x,jet.spatial.y,jet.spatial.z].enumerated() {
            let partials = [coordinate.derivativeU,coordinate.derivativeV,
                coordinate.secondDerivativeUU,coordinate.secondDerivativeUV,coordinate.secondDerivativeVV,
                coordinate.thirdDerivativeUUU,coordinate.thirdDerivativeUUV,
                coordinate.thirdDerivativeUVV,coordinate.thirdDerivativeVVV]
            let values = [expectedU[axis],expectedV[axis],expectedUU[axis],0,0,0,0,0,0]
            for (bounds,value) in zip(partials,values) {
                #expect(bounds.lower <= value && bounds.upper >= value)
            }
        }
    }
    @Test
    func worldPreparationUsesTheCallerWorkAndRejectsCancellation() throws {
        let measured = try OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456)
        var baseline = try execution(measured)
        let baselineField = try field(.affine,using: &baseline)
        let work = measured.snapshot.work
        #expect(work > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: work,storageByteLimit: 268_435_456)
        var exact = try execution(exactBudget)
        #expect(try field(.affine,using: &exact).projectedRationalAuthority != nil)
        #expect(exactBudget.snapshot.work == work)
        var oneLess = try execution(OriginalQueryBudget(workLimit: work - 1,storageByteLimit: 268_435_456))
        geometryTestExpectFailure({ error in
            if case .resourceLimit(.work)? = geometryTestOriginalFailure(error) as? ExactScalarFailure { true } else { false }
        }) { _ = try field(.affine,using: &oneLess) }
        let cancelled = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var stopped = try execution(cancelled)
        geometryTestExpectFailure(geometryTestIsCancelled) { _ = try field(.affine,using: &stopped) }
        #expect(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0)
        var shallow = try execution(OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456),coefficientDepth: 0)
        let zeroDepthField = try field(.affine,using: &shallow)
        let baselineAuthority = try #require(baselineField.projectedRationalAuthority)
        let zeroDepthAuthority = try #require(zeroDepthField.projectedRationalAuthority)
        #expect(shallow.valueDepth == 0 && shallow.coefficientDepth == 0)
        #expect(shallow.budget.snapshot.work == work)
        #expect(zeroDepthAuthority.polynomial.homogeneous == baselineAuthority.polynomial.homogeneous)
        #expect(zeroDepthAuthority.polynomial.normalNumerators == baselineAuthority.polynomial.normalNumerators)
        #expect(zeroDepthAuthority.zeroLaw == baselineAuthority.zeroLaw)
        #expect(zeroDepthAuthority.polynomial.source == baselineAuthority.polynomial.source)
        #expect(zeroDepthAuthority.polynomial.domain == baselineAuthority.polynomial.domain)
    }
    @Test
    func anOffsetWrapperCannotPublishTheRationalWorldCapability() throws {
        var usage = try execution(OriginalQueryBudget(workLimit: 8_388_608,storageByteLimit: 268_435_456))
        let original = try field(.identity,offset: true,using: &usage)
        #expect(original.projectedRationalAuthority == nil)
    }
}
