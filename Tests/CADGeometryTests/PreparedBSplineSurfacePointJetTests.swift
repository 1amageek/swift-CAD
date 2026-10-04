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
    func originalGrevilleTensorJetsContainLiteralValuesAndMixedDerivatives() throws {
        // Original Greville controls reproduce S=(u,v,u*v) on every native span.
        let greville = [0.0, 0.125, 0.3125, 0.6875, 1.0]
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 0.25, 0.375, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [greville.map { Point3D(x: $0, y: 0, z: 0) },
                            greville.map { Point3D(x: $0, y: 1, z: $0) }])
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let axis = try ScalarInterval(lower: 0.3103448275862068, upper: 0.3103448275862069)
        let box = SurfaceParameterBox(u: axis, v: axis)
        let interval = try prepared.intervalJet(over: box, tolerance: tolerance)
        func verify(_ jet: SurfaceIntervalVectorJet, u: Double, v: Double) {
            let expected: [[Double]] = [
                [u, 1, 0, 0, 0, 0, 0, 0, 0, 0],
                [v, 0, 1, 0, 0, 0, 0, 0, 0, 0],
                [u * v, v, u, 0, 1, 0, 0, 0, 0, 0]
            ]
            for (coordinate, values) in zip([jet.x, jet.y, jet.z], expected) {
                for (field, value) in zip(fields(coordinate), values) {
                    #expect(field.contains(value))
                }
            }
        }
        for u in [axis.lower, axis.midpoint, axis.upper] {
            for v in [axis.lower, axis.upper] { verify(interval, u: u, v: v) }
        }
        // Point evaluation and both owning native-knot sides use the same original oracle.
        for u in [axis.midpoint, 0.25, 0.375] {
            let point = try prepared.pointJet(u: u, v: axis.midpoint, tolerance: tolerance)
            verify(point, u: u, v: axis.midpoint)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalRationalNativeSpansContainLiteralQuotientJets() throws {
        // Each original half has a different positive rational denominator.
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0.5), Point3D(x: 1, y: 1, z: 1)]],
            weights: [[1, 2, 4], [1, 2, 4]])
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        func verify(_ jet: SurfaceIntervalVectorJet, u: Double, v: Double, left: Bool) {
            let t = left ? 2*u : 2*u-1, w = 1+t
            let x = left ? t/w : (1+3*t)/(2*w)
            let d = 2/(w*w), dd = -8/(w*w*w), ddd = 48/(w*w*w*w)
            let expected = [[x, d, 0, dd, 0, 0, ddd, 0, 0, 0],
                            [v, 0, 1, 0, 0, 0, 0, 0, 0, 0],
                            [x*v, d*v, x, dd*v, d, 0, ddd*v, dd, 0, 0]]
            for (actual, values) in zip([jet.x, jet.y, jet.z], expected) {
                for (field, value) in zip(fields(actual), values) { #expect(field.contains(value)) }
            }
        }
        for (u,left) in [(0.0,true),(0.25,true),(0.75,false),(1.0,false)] {
            verify(try prepared.pointJet(u: u, v: 0.375, tolerance: tolerance), u: u, v: 0.375, left: left)
        }
        let whole = try prepared.intervalJet(over: SurfaceParameterBox(
            u: ScalarInterval(lower: 0.2, upper: 0.8), v: ScalarInterval(lower: 0.25, upper: 0.75)), tolerance: tolerance)
        for (u,left) in [(0.2,true),(0.5,true),(0.5,false),(0.8,false)] {
            for v in [0.25,0.75] { verify(whole, u: u, v: v, left: left) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalNativeTokensRetainEveryKnotCornerAndRejectForeignAuthority() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 0.5, 1, 1],
            controlPoints: (0...2).map { j in (0...2).map { i in
                Point3D(x: Double(i)/2, y: Double(j)/2, z: Double(i*j)/4)
            } })
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let axis = try ScalarInterval(lower: 0.5, upper: 0.5)
        let box = SurfaceParameterBox(u: axis, v: axis)
        let owners = try prepared.originalNativeSpans(over: box, tolerance: tolerance)
        #expect(owners.count == 4)
        #expect(Set(owners.map { $0.uSpanIndex }) == Set([1,2]))
        #expect(Set(owners.map { $0.vSpanIndex }) == Set([1,2]))
        for owner in owners {
            #expect(owner.uBounds.width == 0.5 && owner.vBounds.width == 0.5)
            let jet = try owner.pointJet(u: 0.5, v: 0.5, on: surface, tolerance: tolerance)
            #expect(jet.x.value.contains(0.5) && jet.y.value.contains(0.5) && jet.z.value.contains(0.25))
            #expect(jet.x.derivativeU.contains(1) && jet.x.derivativeV.contains(0))
            #expect(jet.y.derivativeU.contains(0) && jet.y.derivativeV.contains(1))
            #expect(jet.z.derivativeU.contains(0.5) && jet.z.derivativeV.contains(0.5))
            #expect(jet.z.secondDerivativeUV.contains(1))
        }
        let owner = try #require(owners.first { $0.uSpanIndex == 1 && $0.vSpanIndex == 1 })
        var foreign = surface
        foreign.controlPoints[0][0].z = 1
        var otherTolerance = tolerance
        otherTolerance.distance *= 2
        for (source, tol, u) in [(foreign,tolerance,0.5),(surface,otherTolerance,0.5),
                                (surface,tolerance,0.5.nextUp),(surface,tolerance,Double.infinity)] {
            do {
                _ = try owner.pointJet(u: u, v: 0.5, on: source, tolerance: tol)
                Issue.record("A native token must reject foreign source, tolerance, or support.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        // Mutation of the caller's value does not alter the retained original owner.
        let retained = try owner.pointJet(u: 0.5, v: 0.5, on: owner.surface, tolerance: tolerance)
        #expect(retained.z.value.contains(0.25))
        let circle = [(0.02,0.0),(0.0,0.02),(-0.02,0.0),(0.0,-0.02)]
        let periodic = try BSplineSurface3D.periodic(uDegree: 3, vDegree: 1,
            uKnots: [0,1,2,3,4], vKnots: [0,0,1,1],
            controlPoints: [0.0,0.03].map { z in circle.map { Point3D(x: $0.0, y: $0.1, z: z) } },
            isUPeriodic: true, isVPeriodic: false, tolerance: tolerance)
        let periodicPrepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: periodic, tolerance: tolerance)
        do {
            _ = try periodicPrepared.originalNativeSpans(over: box, tolerance: tolerance)
            Issue.record("Periodic representatives must not mint original nonperiodic tokens.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectedOriginalScalarBasisKeepsActualClosedEndpointSide() throws {
        let knots = [0.0,0,0.37,1,1]
        for span in [1,2] {
            let scalar = try BSplineBasis.nonzeroDerivativeValues(parameter: 0.37, degree: 1,
                throughDerivativeOrder: 1, knots: knots, count: 3, owningSpan: span, tolerance: tolerance)
            let enclosed = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: 0.37, degree: 1,
                throughDerivativeOrder: 1, knots: knots, count: 3, owningSpan: span, tolerance: tolerance)
            #expect(scalar[0].startIndex == span-1 && enclosed[0].startIndex == span-1)
            #expect(scalar[0].values == (span == 1 ? [0,1] : [1,0]))
            let width = span == 1 ? 0.37 : 1-0.37
            #expect(enclosed[1].values[0].contains(-1/width))
            #expect(enclosed[1].values[1].contains(1/width))
            for (row, bounds) in zip(scalar,enclosed) {
                for (value, interval) in zip(row.values,bounds.values) { #expect(interval.contains(value)) }
            }
        }
        do {
            _ = try BSplineBasis.nonzeroDerivativeValues(parameter: 0.37.nextUp, degree: 1,
                throughDerivativeOrder: 1, knots: knots, count: 3, owningSpan: 1, tolerance: tolerance)
            Issue.record("Selected basis admission must not move a parameter across its native knot.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
        let ordinary = BSplineBasis.nonzeroDerivativeValues(parameter: 0.37, degree: 1,
            throughDerivativeOrder: 1, knots: knots, count: 3)
        #expect(ordinary[0].startIndex == 1 && ordinary[0].values == [1,0])
    }

    @Test(.timeLimit(.minutes(1)))
    func originalSpanPreparationSelectionAndBasisRespectCancellation() async throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,0.5,1,1], vKnots: [0,0,1,1],
            controlPoints: [[Point3D(x: 0,y: 0,z: 0),Point3D(x: 0.5,y: 0,z: 0),Point3D(x: 1,y: 0,z: 0)],
                            [Point3D(x: 0,y: 1,z: 0),Point3D(x: 0.5,y: 1,z: 0),Point3D(x: 1,y: 1,z: 0)]])
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let box = try SurfaceParameterBox(u: ScalarInterval(lower: 0.25,upper: 0.25),
                                          v: ScalarInterval(lower: 0.5,upper: 0.5))
        let owner = try #require(prepared.originalNativeSpans(over: box, tolerance: tolerance).first)
        for operation in 0...2 {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let task = Task {
                for await _ in stream { break }
                switch operation {
                case 0:
                    _ = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
                case 1:
                    _ = try owner.intervalJet(overClosedBox: box, on: surface, tolerance: tolerance)
                default:
                    _ = try BSplineBasis.nonzeroDerivativeValues(parameter: 0.25, degree: 1,
                        throughDerivativeOrder: 1, knots: surface.uKnots, count: 3, owningSpan: 1, tolerance: tolerance)
                }
            }
            task.cancel()
            continuation.yield()
            continuation.finish()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
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
