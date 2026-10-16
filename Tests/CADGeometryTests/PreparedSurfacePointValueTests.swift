import CADCore
@testable import CADGeometry
import Testing

@Suite("Original prepared surface point values")
struct PreparedSurfacePointValueTests {
    private let tolerance = ModelingTolerance.standard

    private func expectSame(_ value: IntervalVector3DBounds, _ full: SurfaceIntervalVectorJet,
                            containing literal: Point3D) {
        for (actual,original,expected) in [(value.x,full.x.value,literal.x),
            (value.y,full.y.value,literal.y),(value.z,full.z.value,literal.z)] {
            #expect(actual.lower.bitPattern == original.lower.bitPattern)
            #expect(actual.upper.bitPattern == original.upper.bitPattern)
            #expect(actual.contains(expected))
        }
    }

    private func patch(_ surface: BSplineSurface3D) -> RationalBezierSurfacePatch3D {
        RationalBezierSurfacePatch3D(controlPoints:surface.controlPoints,weights:surface.weights,
            uLower:surface.uKnots[surface.uDegree],uUpper:surface.uKnots[surface.uControlPointCount],
            vLower:surface.vKnots[surface.vDegree],vUpper:surface.vKnots[surface.vControlPointCount])
    }

    @Test(.timeLimit(.minutes(1)), arguments:[1.0,2.0])
    func polynomialNativePointValuesKeepLiteralTranslationAndFullBits(_ commonWeight: Double) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let squared = [0.0,0,1.0/3,1]
        let surface = BSplineSurface3D(uDegree:3,vDegree:1,
            uKnots:[2,2,2,2,5,5,5,5],vKnots:[7,7,9,9],
            controlPoints:(0..<2).map { j in (0..<4).map { i in
                Point3D(x:4+0.04*Double(i)/3,y:-3+0.02*Double(j),
                    z:2+(i == 3 ? 0.008 : 0)+0.006*squared[i]*Double(j))
            } },weights:Array(repeating:Array(repeating:commonWeight,count:4),count:2))
        let primitive = RationalBezierSurfaceJetEncloser()
        let preparedPatch = try primitive.prepare(patch(surface),tolerance:tolerance, using: &execution)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &execution)
        let delegate = try PreparedSurfaceDifferentialEncloser(surface:.bSpline(surface),tolerance:tolerance, using: &execution)
        for (u,v) in [(2.0,7.0),(5.0,9.0),(5.0.nextDown,9.0.nextDown),(3.35,8.0)] {
            let t = (u-2)/3, s = (v-7)/2
            let literal = Point3D(x:4+0.04*t,y:-3+0.02*s,z:2+0.008*t*t*t+0.006*t*t*s)
            let full = try prepared.pointJet(u:u,v:v,tolerance:tolerance, using: &execution)
            expectSame(try primitive.pointValueEnclosure(of:preparedPatch,u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
            expectSame(try prepared.pointValue(u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
            expectSame(try delegate.pointValue(u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func genuinelyRationalPointValuesRetainUnequalWeightQuotientAndFullBits() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[2,2,2,5,5,5],vKnots:[7,7,9,9],
            controlPoints:[-1.0/64,1.0/64].map { z in
                [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)]
            },weights:[[4,2,1],[4,2,1]])
        let primitive = RationalBezierSurfaceJetEncloser()
        let preparedPatch = try primitive.prepare(patch(surface),tolerance:tolerance, using: &execution)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &execution)
        let delegate = try PreparedSurfaceDifferentialEncloser(surface:.bSpline(surface),tolerance:tolerance, using: &execution)
        for (u,v) in [(2.0,7.0),(5.0,9.0),(3.35,8.0),(3.875,7.75),(5.0.nextDown,9.0.nextDown)] {
            let s = (u-2)/3, r = (v-7)/2, t = s/(2-s)
            let literal = Point3D(x:t*t/32,y:t/64,z:(2*r-1)/64)
            let full = try prepared.pointJet(u:u,v:v,tolerance:tolerance, using: &execution)
            expectSame(try primitive.pointValueEnclosure(of:preparedPatch,u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
            expectSame(try prepared.pointValue(u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
            expectSame(try delegate.pointValue(u:u,v:v,tolerance:tolerance, using: &execution),full,containing:literal)
            let uBox = try ScalarInterval(lower:u == 5 ? u-1e-8 : u,upper:u == 5 ? u : min(5,u+1e-8))
            let vBox = try ScalarInterval(lower:7.25,upper:8.75)
            let range = try primitive.enclosure(of:preparedPatch,u:uBox,v:vBox,tolerance:tolerance, using: &execution)
            let value = try primitive.valueEnclosure(of:preparedPatch,u:uBox,v:vBox,tolerance:tolerance, using: &execution)
            for (a,b) in [(value.x,range.x.value),(value.y,range.y.value),(value.z,range.z.value)] {
                #expect(a.lower.bitPattern == b.lower.bitPattern && a.upper.bitPattern == b.upper.bitPattern)
            }
        }
    }

    private func knotSurface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
            controlPoints:(0...2).map { j in (0...2).map { i in
                Point3D(x:Double(i)/2,y:Double(j)/2,z:Double(i*j)/4)
            } })
    }

    @Test(.timeLimit(.minutes(1)))
    func originalKnotCornerValuesUnionAllClosedOwnersAndRejectForeignTokens() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let source = knotSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance, using: &execution)
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0.5,upper:0.5),v:try ScalarInterval(lower:0.5,upper:0.5))
        let owners = try prepared.originalNativeSpans(over:box,tolerance:tolerance, using: &execution)
        #expect(owners.count == 4)
        let literal = Point3D(x:0.5,y:0.5,z:0.25)
        var union: IntervalVector3DBounds?
        for owner in owners {
            let value = try owner.pointValue(u:0.5,v:0.5,on:source,tolerance:tolerance, using: &execution)
            expectSame(value,try owner.pointJet(u:0.5,v:0.5,on:source,tolerance:tolerance, using: &execution),containing:literal)
            if let old = union { union = IntervalVector3DBounds(x:old.x.union(value.x),y:old.y.union(value.y),z:old.z.union(value.z)) }
            else { union = value }
        }
        let result = try prepared.pointValue(u:0.5,v:0.5,tolerance:tolerance, using: &execution)
        let allSides = try #require(union)
        for (a,b) in [(result.x,allSides.x),(result.y,allSides.y),(result.z,allSides.z)] {
            #expect(a.lower.bitPattern == b.lower.bitPattern && a.upper.bitPattern == b.upper.bitPattern)
        }
        expectSame(result,try prepared.pointJet(u:0.5,v:0.5,tolerance:tolerance, using: &execution),containing:literal)
        let owner = try #require(owners.first { $0.uSpanIndex == 1 && $0.vSpanIndex == 1 })
        var foreign = source
        foreign.controlPoints[0][0].z = 100
        let otherTolerance = ModelingTolerance(distance:2*tolerance.distance,angle:tolerance.angle,relative:tolerance.relative)
        for (surface,tol,u) in [(foreign,tolerance,0.5),(source,otherTolerance,0.5),
                              (source,tolerance,0.5.nextUp),(source,tolerance,Double.infinity)] {
            do {
                _ = try owner.pointValue(u:u,v:0.5,on:surface,tolerance:tol, using: &execution)
                Issue.record("Original point values must reject foreign native token authority.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        // Caller mutation cannot change the immutable original prepared source.
        expectSame(try owner.pointValue(u:0.5,v:0.5,on:owner.surface,tolerance:tolerance, using: &execution),
            try owner.pointJet(u:0.5,v:0.5,on:owner.surface,tolerance:tolerance, using: &execution),containing:literal)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[true,false])
    func periodicPointLiftValuesKeepOriginalRangeCoversAndFullBits(_ uPeriodic: Bool) throws {
        let circle = [(0.02,0.0),(0.0,0.02),(-0.02,0.0),(0.0,-0.02)]
        for weights in [[2.0,2,2,2],[1.0,2,3,4]] {
            let controls = uPeriodic ? [0.0,0.03].map { z in circle.map { Point3D(x:$0.0,y:$0.1,z:z) } }
                : circle.map { point in [0.0,0.03].map { x in Point3D(x:x,y:point.0,z:point.1) } }
            let tensorWeights = uPeriodic ? [weights,weights] : weights.map { [$0,$0] }
            let surface = try BSplineSurface3D.periodic(uDegree:uPeriodic ? 3 : 1,vDegree:uPeriodic ? 1 : 3,
                uKnots:uPeriodic ? [0,1,2,3,4] : [0,0,1,1],vKnots:uPeriodic ? [0,0,1,1] : [0,1,2,3,4],
                controlPoints:controls,weights:tensorWeights,isUPeriodic:uPeriodic,isVPeriodic:!uPeriodic,tolerance:tolerance)
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
            let delegate = try PreparedSurfaceDifferentialEncloser(surface:.bSpline(surface),tolerance:tolerance)
            for at in [-4.0,0,4,8] {
                let u = uPeriodic ? at : 0.5, v = uPeriodic ? 0.5 : at
                let first = weights[0] == 2 ? 0 : -0.02/6
                let literal = uPeriodic ? Point3D(x:first,y:0.02*2/3,z:0.015)
                    : Point3D(x:0.015,y:first,z:0.02*2/3)
                let full = try prepared.pointJet(u:u,v:v,tolerance:tolerance)
                expectSame(try prepared.pointValue(u:u,v:v,tolerance:tolerance),full,containing:literal)
                expectSame(try delegate.pointValue(u:u,v:v,tolerance:tolerance),full,containing:literal)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedPointValuesRejectInvalidDomainsToleranceAndUnsupportedRepresentations() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let surface = knotSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &execution)
        let otherTolerance = ModelingTolerance(distance:2*tolerance.distance,angle:tolerance.angle,relative:tolerance.relative)
        for (u,v,tol) in [(-Double.ulpOfOne,0.5,tolerance),(1.0.nextUp,0.5,tolerance),
                          (0.5,Double.infinity,tolerance),(Double.nan,0.5,tolerance),(0.5,0.5,otherTolerance)] {
            do {
                _ = try prepared.pointValue(u:u,v:v,tolerance:tol, using: &execution)
                Issue.record("Prepared point values must retain strict original domain/tolerance authority.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        let plane = try PreparedSurfaceDifferentialEncloser(surface:.plane(Plane3D(origin:.origin,normal:.unitZ)),tolerance:tolerance, using: &execution)
        do {
            _ = try plane.pointValue(u:0,v:0,tolerance:tolerance, using: &execution)
            Issue.record("This closed-point value route must not admit another representation.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        let smallest = Double.leastNonzeroMagnitude
        let primitive = RationalBezierSurfaceJetEncloser()
        let owned = try primitive.prepare(RationalBezierSurfacePatch3D(
            controlPoints:[[.origin,Point3D(x:0.02,y:0,z:0)],
                           [Point3D(x:0,y:0.02,z:0),Point3D(x:0.02,y:0.02,z:0)]],
            weights:[[smallest,2*smallest],[smallest,2*smallest]],uLower:0,uUpper:1,vLower:0,vUpper:1),tolerance:tolerance, using: &execution)
        do {
            _ = try primitive.pointValueEnclosure(of:owned,u:0.5,v:0.5,tolerance:tolerance, using: &execution)
            Issue.record("An unresolved finite reciprocal cannot certify Cartesian point values.")
        } catch let error as KernelError { #expect(error.code == .singularSystem) }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPreparedPointValueOperationsRetainCancellation() async throws {
        let budget = try OriginalQueryBudget()
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32)
        var execution = OriginalQueryExecution(budget: budget, limits: limits)
        let surface = knotSurface()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &execution)
        let delegate = try PreparedSurfaceDifferentialEncloser(surface:.bSpline(surface),tolerance:tolerance, using: &execution)
        let primitive = RationalBezierSurfaceJetEncloser()
        let owned = try primitive.prepare(RationalBezierSurfacePatch3D(
            controlPoints:[[.origin,Point3D(x:1,y:0,z:0)],[Point3D(x:0,y:1,z:0),Point3D(x:1,y:1,z:0)]],
            weights:[[1,1],[1,1]],uLower:0,uUpper:1,vLower:0,vUpper:1),tolerance:tolerance, using: &execution)
        for operation in 0...2 {
            let (stream,continuation) = AsyncStream<Void>.makeStream()
            let task = Task {
                var execution = OriginalQueryExecution(budget: budget, limits: limits)
                for await _ in stream { break }
                switch operation {
                case 0: _ = try primitive.pointValueEnclosure(of:owned,u:0.5,v:0.5,tolerance:tolerance, using: &execution)
                case 1: _ = try prepared.pointValue(u:0.5,v:0.5,tolerance:tolerance, using: &execution)
                default: _ = try delegate.pointValue(u:0.5,v:0.5,tolerance:tolerance, using: &execution)
                }
            }
            task.cancel()
            continuation.yield()
            continuation.finish()
            await geometryTestExpectFailure(geometryTestIsCancelled) { _ = try await task.value }
        }
    }
}
