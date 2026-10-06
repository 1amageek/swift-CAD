import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Original surface higher-order interval Taylor coefficients", .timeLimit(.minutes(1)))
struct SurfaceAreaHigherCoefficientTaylorTests {
    private let tolerance = ModelingTolerance.standard

    @Test(arguments:[0.0,0.4,1.0])
    func originalRationalFourthAndFifthDerivativesRemainNonzeroAtClosedStations(_ u: Double) throws {
        let source = rationalPlane()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance)
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:1),v:try ScalarInterval(lower:0,upper:1))
        let owner = try #require(try prepared.originalNativeSpans(over:box,tolerance:tolerance).first)
        var work = 0
        let receipt = try owner.originalCoefficientReceipt(overClosedBox:box,on:source,
            tolerance:tolerance,consumeWork:{ work += 1 })
        let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,consumeWork:{ work += 1 })
        let point = SurfaceParameterBox(u:try ScalarInterval(lower:u,upper:u),v:try ScalarInterval(lower:0.3,upper:0.3))
        let query = try owner.originalCoefficientReceipt(overClosedBox:point,on:source,
            tolerance:tolerance,consumeWork:{ work += 1 })
        let jet = try higher.intervalTaylorJet(using:query,consumeWork:{ work += 1 })
        let d = 2-u
        contains(try jet.x.coefficient(0,0),0.02*u/d)
        for order in 1...5 { contains(try jet.x.coefficient(order,0),0.04/pow(d,Double(order+1))) }
        #expect(try jet.x.coefficient(4,0).lower > 0)
        #expect(try jet.x.coefficient(5,0).lower > 0)
        contains(try jet.y.coefficient(0,0),0.009)
        contains(try jet.y.coefficient(0,1),0.03)
        contains(try jet.z.coefficient(0,0),0)
        #expect(work > 0)
        if u == 0.4 {
            let whole = SurfaceParameterBox(u:try ScalarInterval(lower:0.2,upper:0.7),
                v:try ScalarInterval(lower:0.1,upper:0.8))
            let cover = try owner.originalCoefficientReceipt(overClosedBox:whole,on:source,
                tolerance:tolerance,consumeWork:{ work += 1 })
            let interval = try higher.intervalTaylorJet(using:cover,consumeWork:{ work += 1 })
            // Both extrema belong to the complete non-singleton original query.
            for endpoint in [0.2,0.7] {
                contains(try interval.x.coefficient(4,0),0.04/pow(2-endpoint,5))
                contains(try interval.x.coefficient(5,0),0.04/pow(2-endpoint,6))
            }
            contains(try interval.y.coefficient(0,0),0.003)
            contains(try interval.y.coefficient(0,0),0.024)
        }
    }

    @Test
    func intervalTaylorNormalizationRetainsFourthDerivativesOfAnActualCurvedOffsetNormal() throws {
        var tangent = try SurfaceAreaIntervalTaylorScalarJet(order:4,tolerance:tolerance,consumeWork:{})
        try tangent.set(.exact(0.4),0,0)
        try tangent.set(.exact(2),1,0)
        let zero = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(0),order:4,tolerance:tolerance,consumeWork:{})
        let one = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(1),order:4,tolerance:tolerance,consumeWork:{})
        let normal = try SurfaceAreaIntervalTaylorVectorJet(x:tangent.scaled(by:.exact(-1),consumeWork:{}),y:zero,z:one).normalized(consumeWork:{})
        // n_z=(1+(0.4+2h)^2)^(-1/2); the fourth Taylor coefficient is literal.
        let t = 0.4, d = 1+t*t
        let fourth = 16*(3-24*t*t+8*pow(t,4))/(8*pow(d,4.5))
        contains(try normal.z.coefficient(4,0),fourth)
        #expect(try !normal.z.coefficient(4,0).contains(0))
    }

    @Test
    func foreignNativeCoefficientAuthorityAndUnavailableOrdersFailExplicitly() throws {
        let source = rationalPlane(), foreign = rationalPlane(scale:2)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance)
        let other = try PreparedBSplineSurfaceDifferentialEncloser(surface:foreign,tolerance:tolerance)
        let unit = try ScalarInterval(lower:0,upper:1), box = SurfaceParameterBox(u:unit,v:unit)
        let owners = try prepared.originalNativeSpans(over:box,tolerance:tolerance)
        let foreignOwners = try other.originalNativeSpans(over:box,tolerance:tolerance)
        let owner = try #require(owners.first), foreignOwner = try #require(foreignOwners.first)
        let receipt = try owner.originalCoefficientReceipt(overClosedBox:box,on:source,tolerance:tolerance,consumeWork:{})
        let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:4,consumeWork:{})
        let query = try foreignOwner.originalCoefficientReceipt(overClosedBox:box,on:foreign,tolerance:tolerance,consumeWork:{})
        do { _ = try higher.intervalTaylorJet(using:query,consumeWork:{}); Issue.record("Foreign original coefficients must fail.") }
        catch let error as KernelError { #expect(error.code == .invalidInput) }
        let scalar = try SurfaceAreaIntervalTaylorScalarJet(order:3,tolerance:tolerance,consumeWork:{})
        #expect(throws:KernelError.self) { try scalar.coefficient(4,0) }
        #expect(throws:KernelError.self) { try scalar.reciprocal(consumeWork:{}) }
    }

    @Test
    func requestedOrderPayloadIsChargedBeforeAllocationAndCancellationPropagates() async throws {
        let source = rationalPlane()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance)
        let unit = try ScalarInterval(lower:0,upper:1), box = SurfaceParameterBox(u:unit,v:unit)
        let owners = try prepared.originalNativeSpans(over:box,tolerance:tolerance), owner = try #require(owners.first)
        let receipt = try owner.originalCoefficientReceipt(overClosedBox:box,on:source,tolerance:tolerance,consumeWork:{})
        var work = 0
        do {
            _ = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,consumeWork:{
                work += 1
                if work > 3 { throw KernelError(phase:.topology,code:.resourceLimitExceeded,residual:Double(work),
                    tolerance:tolerance,message:"The original caller exhausted requested-order payload work.") }
            })
            Issue.record("Requested-order matrix storage must be paid before allocation.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); #expect(work == 4) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,consumeWork:{})
        }
        do { _ = try await task.value; Issue.record("Cancelled preparation must fail.") }
        catch is CancellationError { }
    }

    @Test
    func periodicLiftRetainsTheSameOriginalCoefficientOwnerAndClosedSide() throws {
        let corners = [Point3D(x:0,y:0,z:0),Point3D(x:0.02,y:0,z:0),
            Point3D(x:0.02,y:0.02,z:0),Point3D(x:0,y:0.02,z:0)]
        let source = try BSplineSurface3D.periodic(uDegree:1,vDegree:1,
            uKnots:[0,1,2,3,4],vKnots:[0,0,1,1],
            controlPoints:[corners,corners.map { Point3D(x:$0.x,y:$0.y,z:0.03) }],
            isUPeriodic:true,isVPeriodic:false,tolerance:tolerance)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance)
        let v = try ScalarInterval(lower:0.4,upper:0.4)
        let baseBox = SurfaceParameterBox(u:try ScalarInterval(lower:0.25,upper:0.25),v:v)
        let liftBox = SurfaceParameterBox(u:try ScalarInterval(lower:4.25,upper:4.25),v:v)
        let baseOwners = try prepared.originalNativeSpans(over:baseBox,tolerance:tolerance)
        let liftOwners = try prepared.originalNativeSpans(over:liftBox,tolerance:tolerance)
        let baseOwner = try #require(baseOwners.first), liftOwner = try #require(liftOwners.first)
        let receipt = try baseOwner.originalCoefficientReceipt(overClosedBox:baseBox,on:source,
            tolerance:tolerance,consumeWork:{})
        let query = try liftOwner.originalCoefficientReceipt(overClosedBox:liftBox,on:source,
            tolerance:tolerance,consumeWork:{})
        let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,consumeWork:{})
        let base = try higher.intervalTaylorJet(using:receipt,consumeWork:{})
        let lifted = try higher.intervalTaylorJet(using:query,consumeWork:{})
        for total in 0...5 { for u in 0...total {
            let v = total-u
            let baseX = try base.x.coefficient(u,v), liftedX = try lifted.x.coefficient(u,v)
            #expect(baseX.lower.bitPattern == liftedX.lower.bitPattern)
            #expect(baseX.upper.bitPattern == liftedX.upper.bitPattern)
            let baseY = try base.y.coefficient(u,v), liftedY = try lifted.y.coefficient(u,v)
            #expect(baseY.lower.bitPattern == liftedY.lower.bitPattern)
            #expect(baseY.upper.bitPattern == liftedY.upper.bitPattern)
            let baseZ = try base.z.coefficient(u,v), liftedZ = try lifted.z.coefficient(u,v)
            #expect(baseZ.lower.bitPattern == liftedZ.lower.bitPattern)
            #expect(baseZ.upper.bitPattern == liftedZ.upper.bitPattern)
        } }
        let closed = SurfaceParameterBox(u:try ScalarInterval(lower:baseOwner.uBounds.upper,
            upper:baseOwner.uBounds.upper),v:v)
        let endpoint = try baseOwner.originalCoefficientReceipt(overClosedBox:closed,on:source,
            tolerance:tolerance,consumeWork:{})
        let endpointJet = try higher.intervalTaylorJet(using:endpoint,consumeWork:{})
        #expect(try endpointJet.x.coefficient(5,0).contains(0))
        #expect(try endpointJet.y.coefficient(5,0).contains(0))
    }

    @Test
    func actualNestedOffsetThirdDerivativesConsumeTheInnerFourthNormalOrder() throws {
        let source = Surface3D.bSpline(BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],controlPoints:[0.0,0.03].map { y in
                [Point3D(x:0,y:y,z:0),Point3D(x:0.01,y:y,z:0),Point3D(x:0.02,y:y,z:0.004)]
            }))
        let inner = Surface3D.procedural(.offset(OffsetSurface3D(source:source,distance:0.001)))
        let support = Surface3D.procedural(.offset(OffsetSurface3D(source:inner,distance:0.0005)))
        var work = 0
        let partition = try SurfaceAreaNativeOffsetTaylorPartition(surface:support,tolerance:tolerance,consumeWork:{ work += 1 })
        let prepared = try #require(partition)
        let station = 0.4, a = 0.4, t = a*station, d = 1+t*t, distance = 0.0015
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:station,upper:station),
            v:try ScalarInterval(lower:0.3,upper:0.3))
        var found = false
        try prepared.forEachJet(over:box,domain:nil,tolerance:tolerance,consumeWork:{ work += 1 }) { jet,order in
            #expect(order == 3)
            contains(jet.x.value,0.02*station-distance*t/sqrt(d))
            contains(jet.z.value,0.004*station*station+distance/sqrt(d))
            let thirdX = distance*pow(a,3)*(3/pow(d,2.5)-15*t*t/pow(d,3.5))
            let thirdZ = distance*pow(a,3)*(9*t/pow(d,2.5)-15*pow(t,3)/pow(d,3.5))
            contains(jet.x.thirdDerivativeUUU,thirdX)
            contains(jet.z.thirdDerivativeUUU,thirdZ)
            #expect(!jet.z.thirdDerivativeUUU.contains(0))
            found = true
        }
        #expect(found)
        #expect(work > 0)
    }

    @Test
    func exactNonclampedTranslationRetainsRationalOrdersAndRejectsForeignAuthority() throws {
        let source = BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[0,0,0,1,1,1],vKnots:[-1,0,1,2],
            controlPoints:[0.0,0.03].map { y in
                [0.0,0.01,0.02].map { Point3D(x:$0,y:y,z:0) }
            },weights:[[4,2,1],[4,2,1]])
        var work = 0
        let authority = try #require(try SurfaceAreaOffsetTranslationAuthority(source:source,
            tolerance:tolerance,consumeWork:{ work += 1 }))
        #expect(authority.direction == .v)
        #expect(authority.constantNormal != nil)
        let lower = try PreparedBSplineSurfaceDifferentialEncloser(surface:source,tolerance:tolerance)
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:1),
            v:try ScalarInterval(lower:0,upper:1))
        let owner = try #require(try lower.originalNativeSpans(over:box,tolerance:tolerance).first)
        let receipt = try owner.originalCoefficientReceipt(overClosedBox:box,on:source,
            tolerance:tolerance,consumeWork:{ work += 1 })
        let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,
            translation:authority,consumeWork:{ work += 1 })
        let station = 0.4
        let point = SurfaceParameterBox(u:try ScalarInterval(lower:station,upper:station),
            v:try ScalarInterval(lower:0.7,upper:0.7))
        let query = try owner.originalCoefficientReceipt(overClosedBox:point,on:source,
            tolerance:tolerance,consumeWork:{ work += 1 })
        let rail = try higher.intervalTaylorJet(using:query,consumeWork:{ work += 1 })
        // The unary field is the original rail at v=0. The full original
        // translation term is restored only after the genuine offset chain.
        for order in 1...5 {
            contains(try rail.x.coefficient(order,0),0.04/pow(2-station,Double(order+1)))
        }
        #expect(try rail.x.coefficient(5,0).lower > 0)
        #expect(try rail.x.coefficient(1,1).lower == 0)
        #expect(try rail.x.coefficient(1,1).upper == 0)
        let original = Surface3D.bSpline(source)
        let inner = Surface3D.procedural(.offset(OffsetSurface3D(source:original,distance:0.001)))
        let support = Surface3D.procedural(.offset(OffsetSurface3D(source:inner,distance:0.002)))
        let partition = try #require(try SurfaceAreaNativeOffsetTaylorPartition(surface:support,
            tolerance:tolerance,consumeWork:{ work += 1 }))
        try partition.forEachJet(over:point,domain:nil,tolerance:tolerance,consumeWork:{ work += 1 }) { jet,order in
            #expect(order == 3)
            contains(jet.x.value,0.02*station/(2-station))
            contains(jet.y.value,0.021)
            contains(jet.z.value,0.003)
            contains(jet.y.derivativeV,0.03)
            #expect(jet.x.thirdDerivativeUUV.lower == 0)
            #expect(jet.x.thirdDerivativeUUV.upper == 0)
        }
        let foreign = try #require(try SurfaceAreaOffsetTranslationAuthority(source:rationalPlane(scale:2),
            tolerance:tolerance,consumeWork:{ work += 1 }))
        do {
            _ = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,order:5,
                translation:foreign,consumeWork:{ work += 1 })
            Issue.record("A translated rail requires its exact original source authority.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
        var unary = try SurfaceAreaIntervalTaylorScalarJet(order:3,axis:.u,
            tolerance:tolerance,consumeWork:{ work += 1 })
        #expect(throws:KernelError.self) { try unary.set(.exact(1),1,1) }
        #expect(work > 0)
    }

    private func rationalPlane(scale: Double = 1) -> BSplineSurface3D {
        BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,0.03].map { y in [0.0,0.01,0.02].map { Point3D(x:$0*scale,y:y,z:0) } },
            weights:[[4,2,1],[4,2,1]])
    }

    private func contains(_ interval: OutwardScalarInterval,_ literal: Double) {
        #expect(interval.isFinite)
        #expect(interval.contains(literal))
    }
}
