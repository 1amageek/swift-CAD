import CADCore
@testable import CADGeometry
import Testing

@Suite("Prepared B-spline surface closed and point jets")
struct PreparedBSplineSurfacePointJetTests {
    private let tolerance = ModelingTolerance.standard

    private func polynomial() -> BSplineSurface3D {
        let squared = [0.0,0,1.0/3,1]
        return BSplineSurface3D(uDegree:3,vDegree:1,
            uKnots:[2,2,2,2,5,5,5,5],vKnots:[7,7,9,9],
            controlPoints:(0..<2).map { j in (0..<4).map { i in
                Point3D(x:0.04*Double(i)/3,y:0.02*Double(j),
                    z:(i == 3 ? 0.008 : 0)+0.006*squared[i]*Double(j))
            } })
    }

    private func fields(_ jet: SurfaceIntervalJet) -> [OutwardScalarInterval] {
        [jet.value,jet.derivativeU,jet.derivativeV,jet.secondDerivativeUU,
         jet.secondDerivativeUV,jet.secondDerivativeVV,jet.thirdDerivativeUUU,
         jet.thirdDerivativeUUV,jet.thirdDerivativeUVV,jet.thirdDerivativeVVV]
    }

    private func verifyPolynomial(_ jet: SurfaceIntervalVectorJet, u: Double, v: Double) {
        let t = (u-2)/3, s = (v-7)/2
        let expected: [[Double]] = [
            [0.04*t,0.04/3,0,0,0,0,0,0,0,0],
            [0.02*s,0,0.01,0,0,0,0,0,0,0],
            [0.008*t*t*t+0.006*t*t*s,0.008*t*t+0.004*t*s,0.003*t*t,
             (0.048*t+0.012*s)/9,0.002*t,0,0.048/27,0.012/18,0,0]
        ]
        for (actual,values) in zip([jet.x,jet.y,jet.z],expected) {
            for (field,value) in zip(fields(actual),values) {
                #expect(field.contains(value))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPointAndNarrowClosedBoxesContainOriginalDerivativeNets() throws {
        let surface = polynomial()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
        let patch = RationalBezierSurfacePatch3D(controlPoints:surface.controlPoints,weights:surface.weights,
            uLower:2,uUpper:5,vLower:7,vUpper:9)
        let encloser = RationalBezierSurfaceJetEncloser()
        let owned = try encloser.prepare(patch,tolerance:tolerance)
        for (u,v) in [(2.0,7.0),(5.0,9.0),(5.0.nextDown,9.0.nextDown),(3.35,8.0)] {
            let actual = try prepared.pointJet(u:u,v:v,tolerance:tolerance)
            let direct = try encloser.pointEnclosure(of:owned,u:u,v:v,tolerance:tolerance)
            verifyPolynomial(actual,u:u,v:v)
            for (a,b) in zip([actual.x,actual.y,actual.z],[direct.x,direct.y,direct.z]) {
                for (x,y) in zip(fields(a),fields(b)) {
                    #expect(x.lower == y.lower && x.upper == y.upper)
                }
            }
            #expect(actual.y.value.upper-actual.y.value.lower < 5.68e-14)
        }
        var previousWidth = Double.infinity
        for width in [1e-4,1e-7,1e-10] {
            let box = try SurfaceParameterBox(u:ScalarInterval(lower:3.35-width,upper:3.35+width),
                v:ScalarInterval(lower:8,upper:8))
            let actual = try prepared.intervalJet(overClosedBox:box,tolerance:tolerance)
            for u in [box.u.lower,box.u.midpoint,box.u.upper] { verifyPolynomial(actual,u:u,v:8) }
            let currentWidth = actual.x.value.upper-actual.x.value.lower
            #expect(currentWidth < previousWidth)
            previousWidth = currentWidth
        }
        #expect(previousWidth < 1e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalPointJetsContainIndependentQuotientDerivatives() throws {
        let surface = BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[2,2,2,5,5,5],vKnots:[7,7,9,9],
            controlPoints:[0.0,0.02].map { y in [Point3D(x:0,y:y,z:0),
                Point3D(x:0.04,y:y,z:0),Point3D(x:0.04,y:y,z:0.008)] },
            weights:[[1,0.5,1],[1,0.5,1]])
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
        for u in [2.0,3.35,5.0.nextDown,5] {
            let t = (u-2)/3, w = 1-t+t*t, dw = 2*t-1
            func quotient(_ numerator: Double, first: Double, second: Double) -> [Double] {
                let value = numerator/w
                let d = (first-dw*value)/w
                let dd = (second-2*dw*d-2*value)/w
                let ddd = (-3*dw*dd-6*d)/w
                return [value,d/3,0,dd/9,0,0,ddd/27,0,0,0]
            }
            let jet = try prepared.pointJet(u:u,v:8,tolerance:tolerance)
            for (actual,expected) in [(jet.x,quotient(0.04*t,first:0.04,second:0)),
                (jet.z,quotient(0.008*t*t,first:0.016*t,second:0.016))] {
                for (field,value) in zip(fields(actual),expected) { #expect(field.contains(value)) }
            }
            #expect(jet.y.value.contains(0.01) && jet.y.derivativeV.contains(0.01))
            #expect(jet.y.value.upper-jet.y.value.lower < 5.68e-14)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func knotPointUnionsBothOneSidedDerivativeAuthorities() throws {
        let knot = 0.37
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[0,0,knot,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,0.02].map { y in
                [Point3D(x:0,y:y,z:0),Point3D(x:0.04*knot,y:y,z:0),
                 Point3D(x:0.04,y:y,z:0.01)]
            })
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
        let actual = try prepared.pointJet(u:knot,v:0.5,tolerance:tolerance)
        #expect(actual.x.value.contains(0.04*knot))
        #expect(actual.z.derivativeU.contains(0))
        #expect(actual.z.derivativeU.contains(0.01/(1-knot)))
        #expect(actual.x.derivativeU.contains(0.04))
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicPointAndSeamBoxRetainAllRepresentatives() throws {
        let circle = [(0.02,0.0),(0.0,0.02),(-0.02,0.0),(0.0,-0.02)]
        let surface = try BSplineSurface3D.periodic(uDegree:3,vDegree:1,
            uKnots:[0,1,2,3,4],vKnots:[0,0,1,1],
            controlPoints:[0.0,0.03].map { z in circle.map { Point3D(x:$0.0,y:$0.1,z:z) } },
            isUPeriodic:true,isVPeriodic:false,tolerance:tolerance)
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
        for u in [-4.0,0,4,8] {
            let jet = try prepared.pointJet(u:u,v:0.5,tolerance:tolerance)
            #expect(jet.x.value.contains(0) && jet.y.value.contains(0.02*2/3))
            #expect(jet.x.derivativeU.contains(-0.02) && jet.y.derivativeU.contains(0))
            #expect(jet.x.secondDerivativeUU.contains(0) && jet.y.secondDerivativeUU.contains(-0.04))
            #expect(jet.x.thirdDerivativeUUU.contains(0.04) && jet.y.thirdDerivativeUUU.contains(0.04))
        }
        let jet = try prepared.intervalJet(overClosedBox:SurfaceParameterBox(
            u:ScalarInterval(lower:-0.01,upper:0.01),v:ScalarInterval(lower:0.5,upper:0.5)),
            tolerance:tolerance)
        for t in [0.0,0.005,0.01] {
            let x = 0.02*(t*t*t/3-t), y = 0.02*(t*t*t/3-t*t+2.0/3)
            #expect(jet.x.value.contains(x) && jet.x.value.contains(-x))
            #expect(jet.y.value.contains(y))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidClosedDomainsAndPublicDegenerateBoxesRemainTypedFailures() throws {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:polynomial(),tolerance:tolerance)
        for (u,v) in [(2.0.nextDown,8.0),(5.0.nextUp,8.0),(3.0,7.0.nextDown),(.infinity,8.0)] {
            do {
                _ = try prepared.pointJet(u:u,v:v,tolerance:tolerance)
                Issue.record("A point jet must retain strict native-domain admission.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        do {
            _ = try prepared.intervalJet(over:SurfaceParameterBox(
                u:ScalarInterval(lower:3,upper:3),v:ScalarInterval(lower:8,upper:8)),tolerance:tolerance)
            Issue.record("The public positive-width contract must remain unchanged.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
        let box = try SurfaceParameterBox(u:ScalarInterval(lower:3.35-1e-10,upper:3.35+1e-10),
            v:ScalarInterval(lower:8-1e-10,upper:8+1e-10))
        let direct = try DefaultSurfaceDifferentialEncloser().intervalJet(of:.bSpline(polynomial()),
            over:box,tolerance:tolerance)
        let owned = try prepared.intervalJet(over:box,tolerance:tolerance)
        for (a,b) in zip([direct.x,direct.y,direct.z],[owned.x,owned.y,owned.z]) {
            for (x,y) in zip(fields(a),fields(b)) {
                #expect(x.lower == y.lower && x.upper == y.upper)
            }
        }
    }
}
