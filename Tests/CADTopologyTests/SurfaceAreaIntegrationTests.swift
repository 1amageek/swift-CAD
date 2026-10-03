import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Certified free-surface area")
struct SurfaceAreaIntegrationTests {
    private let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-6)

    private func rectangle(_ u0: Double = 0, _ u1: Double = 1,
                           _ v0: Double = 0, _ v1: Double = 1) -> [SurfaceParameterCurve] {
        [.constantV(v: v0, uStart: u0, uEnd: u1),
         .constantU(u: u1, vStart: v0, vEnd: v1),
         .constantV(v: v1, uStart: u1, uEnd: u0),
         .constantU(u: u0, vStart: v1, vEnd: v0)]
    }

    private func fixture(_ surface: Surface3D, outer: [SurfaceParameterCurve]? = nil,
                         holes: [[SurfaceParameterCurve]] = [], reversed: Bool = false) throws -> (FaceID, BRepModel) {
        let surfaceID = SurfaceID(), faceID = FaceID()
        var loops: [LoopID: Loop] = [:]
        var ids: [LoopID] = []
        for (index, original) in ([outer ?? rectangle()] + holes).enumerated() {
            let curves = reversed ? try original.reversed().map { try $0.reversed(tolerance: tolerance) } : original
            let id = LoopID()
            ids.append(id)
            loops[id] = Loop(id: id, role: index == 0 ? .outer : .inner,
                coedges: curves.map { Coedge(edgeID: EdgeID(), surfaceParameterCurve: $0) })
        }
        return (faceID, BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: ids,
                                orientation: reversed ? .reversed : .forward)], loops: loops))
    }

    private func graph() -> Surface3D {
        // Exact S(u,v)=(0.02u,0.03v,10(0.02u)^2), with no fitted samples.
        .bSpline(BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0,0,0,1,1,1], vKnots: [0,0,1,1],
            controlPoints: [0.0,0.03].map { y in [
                Point3D(x: 0, y: y, z: 0), Point3D(x: 0.01, y: y, z: 0),
                Point3D(x: 0.02, y: y, z: 0.004)] }))
    }

    @Test(.timeLimit(.minutes(1)))
    func parabolaExtrusionHasAnalyticAreaAndMoments() throws {
        let (id, model) = try fixture(graph())
        let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
        let a = 0.02, k = 10.0, t = 2*k*a
        let length = (t * sqrt(1+t*t) + asinh(t)) / (4*k)
        let momentX = (pow(1+t*t,1.5)-1) / (12*k*k)
        let momentZ = (t*sqrt(1+t*t)*(2*t*t+1)-asinh(t)) / (64*k*k)
        #expect(abs(result.area - length*0.03) <= 1e-9)
        #expect(abs(result.centroid.x - momentX/length) <= tolerance.distance)
        #expect(abs(result.centroid.y - 0.015) <= tolerance.distance)
        #expect(abs(result.centroid.z - momentZ/length) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func holesAndReversalSubtractTheSameExactDomain() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin, Point3D(x: 0.04,y:0,z:0)],
                            [Point3D(x:0,y:0.02,z:0),Point3D(x:0.04,y:0.02,z:0)]]))
        for reversed in [false,true] {
            // Deliberately use the same traversal on the inner and outer loops.
            let (id, model) = try fixture(surface, holes: [rectangle(0.25,0.5,0.25,0.75)], reversed: reversed)
            let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
            #expect(abs(result.area - 0.0007) < 1e-12)
            #expect(abs(result.centroid.x - (0.0008*0.02-0.0001*0.015)/0.0007) < 1e-6)
            #expect(abs(result.centroid.y - 0.01) < 1e-6)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func ruledAndExactOffsetSupportsMeasureTheirGeometry() throws {
        func rail(_ y: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree: 1, knots: [0,0,1,1],
                controlPoints: [Point3D(x:0,y:y,z:0),Point3D(x:0.02,y:y,z:0.01)]))
        }
        let ruled = Surface3D.procedural(.ruled(RuledSurface3D(startBoundary: rail(0),endBoundary:rail(0.03))))
        for surface in [ruled, .procedural(.offset(OffsetSurface3D(source: ruled, distance: 0.002)))] {
            let (id, model) = try fixture(surface)
            let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
            #expect(abs(result.area - sqrt(0.02*0.02+0.01*0.01)*0.03) < 1e-9)
            #expect(abs(result.centroid.y - 0.015) < 1e-6)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rollingBallMeasuresQuarterCylinderWithoutAConvertedMesh() throws {
        let radius = 0.01
        let (id, model) = try fixture(quarterCylinderBlend())
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let area = .pi/2*radius*0.02
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-Point3D(x:0.01,y:2*radius / .pi,z:2*radius / .pi)).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func translatedDiagonalRollingSpineRetainsNativeSectionAndCentroid() throws {
        let origin = Point3D(x:1.0/32,y:1.0/64,z:0)
        let delta = Vector3D(x:1.0/64,y:1.0/64,z:0)
        let radius = sqrt(2.0)/256
        let a = Vector3D(x:-1.0/256,y:1.0/256,z:0)
        let b = Vector3D(x:0,y:0,z:radius)
        func rail(_ offset: Vector3D) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:1,knots:[0,0,1,1],
                controlPoints:[origin+offset,origin+offset+delta]))
        }
        let blend = RollingBallBlendSurface3D(centerSpine:rail(.zero),firstContact:rail(a),
            secondContact:rail(b),radius:radius,tolerance:tolerance)
        let prepared = try #require(try SurfaceAreaTranslatedRollingBallJet(blend))
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:1),
            v:try ScalarInterval(lower:0,upper:1))
        let jet = try prepared.intervalJet(over:box,tolerance:tolerance)
        // Independent quotient differentiation of the native circular section.
        // A comparison in angular coordinates would not detect a changed V chart.
        for t in [0.0,0.125,0.5,0.875,1.0] {
            let w = sqrt(0.5), q = 1-sqrt(2.0)
            let d = 1+2*(w-1)*t+2*(1-w)*t*t
            let d1 = 2*(w-1)+4*(1-w)*t, d2 = 4*(1-w)
            func quotient(_ n: Double, _ n1: Double, _ n2: Double) -> [Double] {
                let f = n/d, first = (n1-d1*f)/d
                let second = (n2-d2*f-2*d1*first)/d
                return [f,first,second,(-3*d2*first-3*d1*second)/d]
            }
            let x = quotient(1+(sqrt(2.0)-2)*t+q*t*t,sqrt(2.0)-2+2*q*t,2*q)
            let y = quotient(sqrt(2.0)*t+q*t*t,sqrt(2.0)+2*q*t,2*q)
            let derivatives = (0..<4).map { a*x[$0]+b*y[$0] }
            let point = origin+delta*0.5+derivatives[0]
            for (field,coordinate,index) in [(jet.x,point.x,0),(jet.y,point.y,1),(jet.z,point.z,2)] {
                func component(_ vector: Vector3D) -> Double {
                    index == 0 ? vector.x : (index == 1 ? vector.y : vector.z)
                }
                #expect(field.value.contains(coordinate))
                #expect(field.derivativeU.contains(component(delta)))
                #expect(field.derivativeV.contains(component(derivatives[1])))
                #expect(field.secondDerivativeVV.contains(component(derivatives[2])))
                #expect(field.thirdDerivativeVVV.contains(component(derivatives[3])))
                #expect(field.secondDerivativeUU.lower == 0 && field.secondDerivativeUU.upper == 0)
                #expect(field.secondDerivativeUV.lower == 0 && field.secondDerivativeUV.upper == 0)
            }
        }
        let (id,model) = try fixture(.procedural(.rollingBall(blend)))
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let area = delta.length*radius * .pi/2
        let centroid = origin+delta*0.5+(a+b)*(2 / .pi)
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-centroid).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func unequalRollingRailMotionUsesTheGeneralPreparedPath() throws {
        func rail(_ y: Double, _ z: Double, _ dx: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:1,knots:[0,0,1,1],
                controlPoints:[Point3D(x:0,y:y,z:z),Point3D(x:dx,y:y,z:z)]))
        }
        let blend = RollingBallBlendSurface3D(centerSpine:rail(0,0,0.02),
            firstContact:rail(0.01,0,0.020001),secondContact:rail(0,0.01,0.02),
            radius:0.01,tolerance:tolerance)
        #expect(try SurfaceAreaTranslatedRollingBallJet(blend) == nil)
        let surface = Surface3D.procedural(.rollingBall(blend))
        let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance)
        #expect(prepared.translationDirection == nil)
        let fraction = try ScalarInterval(lower:0.5,upper:0.50001)
        let fields = try prepared.bounds(curve:.constantU(u:0.5,vStart:0,vEnd:1),
            anchor:SurfaceParameter(u:0.25,v:0.25),reference:.origin,
            boundaryFraction:fraction,radialFraction:fraction,tolerance:tolerance)
        #expect(fields.count == 4 && fields.allSatisfy { $0.value.isFinite })
        let point = try surface.point(u:0.4,v:0.6,tolerance:tolerance)
        let direct = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance)
            .enclosure(over:SurfaceParameterBox(u:ScalarInterval(lower:0.4,upper:0.40001),
                v:ScalarInterval(lower:0.6,upper:0.60001)),tolerance:tolerance).position
        #expect(direct.x.lower <= point.x && point.x <= direct.x.upper)
        #expect(direct.y.lower <= point.y && point.y <= direct.y.upper)
        #expect(direct.z.lower <= point.z && point.z <= direct.z.upper)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [512, 2048])
    func minimumRollingFixtureHasBoundedWork(_ budget: Int) throws {
        let started = ContinuousClock.now
        let (id, model) = try fixture(quarterCylinderBlend())
        do {
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:budget))
            let area = .pi/2*0.01*0.02
            let centroid = Point3D(x:0.01,y:0.02 / .pi,z:0.02 / .pi)
            #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
            #expect((result.centroid-centroid).length <= tolerance.distance)
            print("AREA_PROFILE fixture=rolling budget=\(budget) outcome=success residual=none elapsed=\(started.duration(to: .now))")
        } catch let error as KernelError {
            print("AREA_PROFILE fixture=rolling budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == Double(budget+1))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rollingTranslationCertificateReportsBoundedDyadicErrorProbe() throws {
        let prepared = try PreparedSurfaceAreaIntegrand(surface:quarterCylinderBlend(),tolerance:tolerance)
        #expect(prepared.translationDirection == .u)
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:1),
            v:try ScalarInterval(lower:0,upper:1))
        let estimatedArea = 0.02*0.01*sqrt(2.0)
        let areaGoal = (tolerance.distance*tolerance.distance+tolerance.relative*estimatedArea)*0.125/4
        let momentGoal = tolerance.distance*estimatedArea/sqrt(3.0)*0.0625/4
        let goals = [areaGoal,momentGoal,momentGoal,momentGoal]
        // Fixed 39 boxes distinguish unresolved normals from integral errors;
        // no adaptive traversal, larger budget, or success fallback is involved.
        for depth in 0...12 {
            let width = pow(0.5,Double(depth))
            for station in [0.0,0.5,1.0] {
                let lower = max(0,min(1-width,station-width*0.5))
                let upper = lower+width
                let fraction = try ScalarInterval(lower:lower,upper:upper)
                do {
                    let fields = try prepared.rectangularTranslationBounds(rectangle:box,
                        fraction:fraction,reference:Point3D(x:0,y:0.01,z:0),tolerance:tolerance)
                    let center = try prepared.rectangularTranslationBounds(rectangle:box,
                        fraction:ScalarInterval(lower:fraction.midpoint,upper:fraction.midpoint),
                        reference:Point3D(x:0,y:0.01,z:0),tolerance:tolerance)
                    for i in fields.indices {
                        let hessian = try #require(fields[i].secondUU)
                        let midpointError = center[i].value.width*0.5
                        let hessianError = hessian.width*width*width/48
                        print("AREA_ERROR_PROBE fixture=rolling depth=\(depth) station=\(station) field=\(i) midpointError=\(midpointError) hessianError=\(hessianError) goal=\(goals[i]) ratio=\((midpointError+hessianError)/goals[i])")
                    }
                } catch let error as KernelError {
                    print("AREA_ERROR_PROBE fixture=rolling depth=\(depth) station=\(station) outcome=\(error.code.rawValue) residual=\(String(describing:error.residual))")
                    #expect(error.code == .singularSystem || error.code == .singularGeometry)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedTrimAreaUsesItsExactBoundary() throws {
        let disk = SurfaceParameterCurve.harmonic(center:Point2D(x:0.5,y:0.5),
            cosine:Point2D(x:0.25,y:0),sine:Point2D(x:0,y:0.25), startParameter:0,endParameter:2 * .pi)
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:[
                [.origin,Point3D(x:0.04,y:0,z:0)],
                [Point3D(x:0,y:0.02,z:0),Point3D(x:0.04,y:0.02,z:0)]]))
        let (id,model) = try fixture(surface,outer:[disk])
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area - .pi*0.25*0.25*0.0008) < 1e-9)
        #expect((result.centroid-Point3D(x:0.02,y:0.01,z:0)).length < 1e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedOffsetHasKnownAreaAndIndependentCentroidIntegral() throws {
        let distance = 0.001, a = 0.02, b = 0.03, k = 10.0
        let support = Surface3D.procedural(.offset(OffsetSurface3D(source: graph(), distance: distance)))
        let (id, model) = try fixture(support)
        let offsetTolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-4)
        let result = try model.faceAreaMeasurement(of: id, tolerance: offsetTolerance)
        let t = 2*k*a
        let length = (t*sqrt(1+t*t)+asinh(t))/(4*k)
        let expectedArea = b*(length-distance*atan(t))
        // An independent physical-X Simpson integral, using the analytic normal
        // and curvature rather than source UV derivatives or the fan integrator.
        let samples = 1024
        var area = 0.0, momentX = 0.0, momentZ = 0.0
        for i in 0...samples {
            let x = a*Double(i)/Double(samples)
            let slope = 2*k*x, norm = sqrt(1+slope*slope)
            let curvature = 2*k/(norm*norm*norm)
            let density = (1-distance*curvature)*norm
            let px = x-distance*slope/norm
            let pz = k*x*x+distance/norm
            let weight = i == 0 || i == samples ? 1.0 : (i % 2 == 0 ? 2.0 : 4.0)
            area += weight*density
            momentX += weight*px*density
            momentZ += weight*pz*density
        }
        #expect(abs(result.area-expectedArea) <= offsetTolerance.distance*offsetTolerance.distance
            + offsetTolerance.relative*expectedArea)
        #expect(abs(result.centroid.x-momentX/area) <= offsetTolerance.distance)
        #expect(abs(result.centroid.z-momentZ/area) <= offsetTolerance.distance)
        #expect(abs(result.centroid.y-0.015) <= offsetTolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func polynomialOffsetBoundsContainAnalyticDensityDerivatives() throws {
        let a = 0.02, b = 0.03, k = 10.0, distance = 0.001
        let support = Surface3D.procedural(.offset(OffsetSurface3D(source: graph(), distance: distance)))
        let prepared = try PreparedSurfaceAreaIntegrand(surface: support, tolerance: tolerance)
        let unit = try ScalarInterval(lower: 0, upper: 1)
        let rectangle = SurfaceParameterBox(u: unit, v: unit)
        // Differentiate the independent analytic physical-X offset area element.
        // This exercises the actual source-jet -> offset-normal -> density path,
        // including Hessians enabled only by the exact fourth-source-zero proof.
        let c2 = pow(2*k*a, 2), d = 2*k*distance
        for (lower, upper) in [(0.0,0.01),(0.49,0.51),(0.99,1.0)] {
            let bounds = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                fraction: ScalarInterval(lower: lower, upper: upper), reference: .origin,
                tolerance: tolerance)[0]
            let second = try #require(bounds.secondUU)
            for u in [lower, (lower+upper)*0.5, upper] {
                let r = 1+c2*u*u
                let density = a*b*(sqrt(r)-d/r)
                let first = a*b*(c2*u/sqrt(r)+2*d*c2*u/(r*r))
                let hessian = a*b*(c2/pow(r,1.5)+2*d*c2/(r*r)-8*d*c2*c2*u*u/(r*r*r))
                #expect(bounds.value.lower <= density && density <= bounds.value.upper)
                let derivative = try #require(bounds.derivativeU)
                #expect(derivative.lower <= first && first <= derivative.upper)
                #expect(second.lower <= hessian && hessian <= second.upper)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func translatedPiecewiseC1SupportRetainsItsAnalyticIntegral() throws {
        // Exact quadratic knot insertion at U=1/2 preserves the same parabola.
        // The C1 join requires gradient-only admission; domain endpoints remain included.
        let a = 0.02, k = 10.0, t = 2*k*a
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[0,0,0,0.5,1,1,1],vKnots:[0,0,1,1],controlPoints:[0.0,0.03].map { y in
                [Point3D(x:0,y:y,z:0),Point3D(x:0.005,y:y,z:0),
                 Point3D(x:0.015,y:y,z:0.002),Point3D(x:0.02,y:y,z:0.004)] }))
        let (id,model) = try fixture(surface)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let length = (t*sqrt(1+t*t)+asinh(t))/(4*k)
        let momentX = (pow(1+t*t,1.5)-1)/(12*k*k)
        #expect(abs(result.area-0.03*length) <= tolerance.distance*tolerance.distance
            + tolerance.relative*0.03*length)
        #expect(abs(result.centroid.x-momentX/length) <= tolerance.distance)
        #expect(abs(result.centroid.y-0.015) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func translationReductionPreservesTheFullSupportDomain() throws {
        let prepared = try PreparedSurfaceAreaIntegrand(surface: graph(), tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower:0,upper:1),
                                      v: try ScalarInterval(lower:-0.1,upper:1.1))
        do {
            _ = try prepared.rectangularTranslationBounds(rectangle:box,
                fraction:ScalarInterval(lower:0.4,upper:0.6),reference:.origin,tolerance:tolerance)
            Issue.record("Eliminating a band must not admit its out-of-domain endpoints.")
        } catch SurfaceAreaEnclosureRefinementRequired.parameterDomain {}
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicStripBoundsContainIndependentSeamAndShiftDerivatives() throws {
        let height = 0.03
        for uPeriodic in [true,false] {
            let surface = try periodicStrip(uPeriodic:uPeriodic)
            let prepared = try PreparedSurfaceAreaIntegrand(surface:.bSpline(surface),tolerance:tolerance)
            for (lower,upper) in [(-0.3,-0.1),(-4.25,-3.75),(-0.25,0.25),(7.75,8.25)] {
                let cycle = try ScalarInterval(lower:lower,upper:upper)
                let open = try ScalarInterval(lower:0,upper:1)
                let box = SurfaceParameterBox(u:uPeriodic ? cycle : open,v:uPeriodic ? open : cycle)
                let fields = try prepared.rectangularTranslationBounds(rectangle:box,
                    fraction:ScalarInterval(lower:0,upper:1),reference:.origin,tolerance:tolerance)
                let width = upper-lower, scale = width*height
                // Independent uniform cubic section formulas, including their
                // rotated derivatives, do not call the production spline evaluator.
                for fraction in [0.0,0.2,0.5,0.8,1.0] {
                    let section = independentPeriodicSection(lower+width*fraction)
                    let p = section.point, d = section.first, dd = section.second
                    let speed = d.length
                    let slope = d.dot(dd)/speed
                    let hessian = (dd.dot(dd)+d.dot(section.third))/speed
                        - pow(d.dot(dd),2)/pow(speed,3)
                    let positions = [p.x,p.y,height*0.5]
                    let first = [d.x,d.y,0.0], second = [dd.x,dd.y,0.0]
                    var values = [scale*speed]
                    var derivatives = [scale*width*slope]
                    var hessians = [scale*width*width*hessian]
                    for i in 0..<3 {
                        values.append(scale*positions[i]*speed)
                        derivatives.append(scale*width*(first[i]*speed+positions[i]*slope))
                        hessians.append(scale*width*width*(second[i]*speed+2*first[i]*slope+positions[i]*hessian))
                    }
                    for i in fields.indices {
                        let bound = fields[i]
                        let h = try #require(bound.secondUU)
                        #expect(bound.value.lower <= values[i] && values[i] <= bound.value.upper)
                        let derivative = try #require(bound.derivativeU)
                        #expect(derivative.lower <= derivatives[i] && derivatives[i] <= derivative.upper)
                        #expect(h.lower <= hessians[i] && hessians[i] <= h.upper)
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicStripAreaAndMomentsUseTheEntireRequestedPeriodPiece() throws {
        let samples = 1024, lower = -0.25, upper = 0.25, height = 0.03
        var length = 0.0, momentX = 0.0, momentY = 0.0
        for index in 0...samples {
            let u = lower+(upper-lower)*Double(index)/Double(samples)
            let section = independentPeriodicSection(u)
            let weight = index == 0 || index == samples ? 1.0 : (index % 2 == 0 ? 2.0 : 4.0)
            let density = weight*section.first.length
            length += density
            momentX += section.point.x*density
            momentY += section.point.y*density
        }
        let area = length*(upper-lower)/Double(3*samples)*height
        let expected = Point3D(x:momentX/length,y:momentY/length,z:height*0.5)
        for uPeriodic in [true,false] {
            let surface = Surface3D.bSpline(try periodicStrip(uPeriodic:uPeriodic))
            for shift in [-4.0,0.0,8.0] {
                let boundary = uPeriodic ? rectangle(lower+shift,upper+shift,0,1)
                    : rectangle(0,1,lower+shift,upper+shift)
                let (id,model) = try fixture(surface,outer:boundary)
                let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
                #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
                #expect((result.centroid-expected).length <= tolerance.distance)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalTrimQuarterCirclesRetainTheirExactArea() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:[
                [.origin,Point3D(x:0.04,y:0,z:0)],
                [Point3D(x:0,y:0.02,z:0),Point3D(x:0.04,y:0.02,z:0)]]))
        let center = Point2D(x:0.5,y:0.5), radius = 0.25
        let directions = [(1.0,0.0),(0.0,1.0),(-1.0,0.0),(0.0,-1.0)]
        var curves: [SurfaceParameterCurve] = []
        for i in 0..<4 {
            let p = directions[i], q = directions[(i+1)%4]
            curves.append(.bSpline(BSplineCurve2D(degree:2,knots:[0,0,0,1,1,1],controlPoints:[
                Point2D(x:center.x+radius*p.0,y:center.y+radius*p.1),
                Point2D(x:center.x+radius*(p.0+q.0),y:center.y+radius*(p.1+q.1)),
                Point2D(x:center.x+radius*q.0,y:center.y+radius*q.1)],weights:[1,sqrt(0.5),1])))
        }
        let (id,model) = try fixture(surface,outer:curves)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area - .pi*radius*radius*0.0008) < 1e-9)
        #expect((result.centroid-Point3D(x:0.02,y:0.01,z:0)).length < 1e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedSplineDimensionsFailBeforePreparationAllocation() throws {
        let limits = FaceAreaIntegrationOptions(maximumControlPointCount: 8)
        let points = [Point2D(x:0,y:0),Point2D(x:1,y:0),Point2D(x:0,y:0)]
        for (knots,code) in [(Array(repeating:0.0,count:1024),KernelErrorCode.resourceLimitExceeded),
                             ([0.0,0.0,1.0],.invalidInput)] {
            let curve = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree:1,knots:knots,controlPoints:points))
            let (id,model) = try fixture(graph(),outer:[curve])
            do { _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:limits)
                Issue.record("Malformed spline dimensions must fail before allocation.")
            } catch let error as KernelError { #expect(error.code == code) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resourceAndInvalidOptionsProduceTypedFailures() throws {
        let (id,model) = try fixture(graph())
        for (options, code) in [(FaceAreaIntegrationOptions(maximumCellCount:1),KernelErrorCode.resourceLimitExceeded),
                               (FaceAreaIntegrationOptions(maximumCellCount:0),.invalidInput),
                               (FaceAreaIntegrationOptions(maximumControlPointCount:1),.resourceLimitExceeded)] {
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
                Issue.record("An uncertified resource-limited area must not succeed.")
            } catch let error as KernelError { #expect(error.code == code) }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [512, 2048])
    func minimumAffineFixtureHasBoundedWork(_ budget: Int) throws {
        let started = ContinuousClock.now
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[0,0,1,1],vKnots:[0,0,1,1],controlPoints:[
                [.origin,Point3D(x:0.04,y:0,z:0)],
                [Point3D(x:0,y:0.02,z:0),Point3D(x:0.04,y:0.02,z:0)]]))
        let (id,model) = try fixture(surface)
        let options = FaceAreaIntegrationOptions(maximumCellCount:budget)
        do {
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
            #expect(abs(result.area-0.0008) <= 1e-9)
            #expect((result.centroid-Point3D(x:0.02,y:0.01,z:0)).length <= tolerance.distance)
            print("AREA_PROFILE fixture=affine budget=\(budget) outcome=success residual=none elapsed=\(started.duration(to: .now))")
        } catch let error as KernelError {
            print("AREA_PROFILE fixture=affine budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == Double(budget+1))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [512, 2048])
    func minimumCurvedFixtureHasBoundedWork(_ budget: Int) throws {
        let started = ContinuousClock.now
        let (id,model) = try fixture(graph())
        let options = FaceAreaIntegrationOptions(maximumCellCount:budget)
        do {
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
            let a = 0.02, k = 10.0, t = 2*k*a
            let length = (t*sqrt(1+t*t)+asinh(t))/(4*k)
            let momentX = (pow(1+t*t,1.5)-1)/(12*k*k)
            #expect(abs(result.area-0.03*length) <= tolerance.distance*tolerance.distance
                + tolerance.relative*0.03*length)
            #expect(abs(result.centroid.x-momentX/length) <= tolerance.distance)
            #expect(abs(result.centroid.y-0.015) <= tolerance.distance)
            print("AREA_PROFILE fixture=curved budget=\(budget) outcome=success residual=none elapsed=\(started.duration(to: .now))")
        } catch let error as KernelError {
            print("AREA_PROFILE fixture=curved budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == Double(budget+1))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationIsExplicit() async throws {
        let (id,model) = try fixture(graph())
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled integration succeeded.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[0.5,0.37])
    func c0FoldedRectangleHasAnalyticAreaAndAllCentroidComponents(_ knot: Double) throws {
        let (id,model) = try fixture(foldedSupport(knot:knot))
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let middleX = 0.02*knot
        let firstLength = middleX, secondLength = hypot(0.02-middleX,0.02)
        let area = 0.03*(firstLength+secondLength)
        let centroid = Point3D(x:(firstLength*middleX/2+secondLength*(middleX+0.02)/2)/(firstLength+secondLength),
            y:0.015,z:secondLength*0.01/(firstLength+secondLength))
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-centroid).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[0.5,0.37])
    func c0FoldCrossingTriangleUsesEveryOriginalFanPiece(_ knot: Double) throws {
        let curves: [SurfaceParameterCurve] = [.constantV(v:0,uStart:0,uEnd:1),
            .constantU(u:1,vStart:0,vEnd:1),
            .affine(origin:Point2D(x:1,y:1),direction:Point2D(x:-1,y:-1),startParameter:0,endParameter:1)]
        let (id,model) = try fixture(foldedSupport(knot:knot),outer:curves)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let x = 0.02*knot, firstDensity = 0.03*x/knot
        let secondDensity = 0.03*hypot(0.02-x,0.02)/(1-knot)
        let firstArea = firstDensity*knot*knot/2
        let secondArea = secondDensity*(1-knot*knot)/2
        let firstU = 2*knot/3
        let secondU = 2*(1-knot*knot*knot)/(3*(1-knot*knot))
        let firstPoint = Point3D(x:x*firstU/knot,y:0.03*firstU/2,z:0)
        let secondPoint = Point3D(x:x+(0.02-x)*(secondU-knot)/(1-knot),
            y:0.03*secondU/2,z:0.02*(secondU-knot)/(1-knot))
        let area = firstArea+secondArea
        let centroid = Point3D(x:(firstArea*firstPoint.x+secondArea*secondPoint.x)/area,
            y:(firstArea*firstPoint.y+secondArea*secondPoint.y)/area,
            z:secondArea*secondPoint.z/area)
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-centroid).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func c0CrossingHoleAndReversalRetainAllWeightedMoments(_ reversed: Bool) throws {
        let knot = 0.37, x = 0.02*knot
        let firstLength = x, secondLength = hypot(0.02-x,0.02)
        let hole = rectangle(knot/2,(1+knot)/2,0.25,0.75)
        let (id,model) = try fixture(foldedSupport(knot:knot),holes:[hole],reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let firstArea = 0.03*firstLength, secondArea = 0.03*secondLength
        let removedFirst = firstArea/4, removedSecond = secondArea/4
        let area = 0.75*(firstArea+secondArea)
        let centroid = Point3D(x:(firstArea*x/2+secondArea*(x+0.02)/2
            - removedFirst*0.75*x-removedSecond*(0.75*x+0.25*0.02))/area,
            y:0.015,z:(secondArea*0.01-removedSecond*0.005)/area)
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-centroid).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func c0OneSidedNativeAuthorityAndCrossSpanValueProofRemainDistinct() throws {
        let prepared = try PreparedSurfaceAreaIntegrand(surface:foldedSupport(knot:0.5),tolerance:tolerance)
        let unit = try ScalarInterval(lower:0,upper:1)
        let box = SurfaceParameterBox(u:unit,v:unit)
        let domains = try #require(try prepared.nativeRectangleDomains(over:box,maximumCount:16,tolerance:tolerance))
        #expect(domains.count == 2)
        for domain in domains {
            let fields = try prepared.rectangularTranslationBounds(rectangle:domain.rectangle,
                fraction:unit,reference:.origin,tolerance:tolerance,domain:domain)
            #expect(fields.allSatisfy { $0.derivativeU != nil && $0.derivativeV != nil && $0.secondUU != nil })
        }
        let crossing = try prepared.rectangularTranslationBounds(rectangle:box,
            fraction:ScalarInterval(lower:0.25,upper:0.75),reference:.origin,tolerance:tolerance)
        #expect(crossing.allSatisfy { $0.derivativeU == nil && $0.derivativeV == nil && $0.secondUU == nil && $0.secondUV == nil && $0.secondVV == nil })
        let densities = [0.0006,0.03*hypot(0.02,0.04)]
        for (u,density) in [(0.25,densities[0]),(0.75,densities[1])] {
            let z = u < 0.5 ? 0 : 0.04*u-0.02
            let values = [density,0.02*u*density,0.015*density,z*density]
            for i in crossing.indices { #expect(crossing[i].value.contains(values[i])) }
        }
        let fan = try prepared.bounds(curve:.constantU(u:1,vStart:0,vEnd:1),
            anchor:SurfaceParameter(u:0,v:0),reference:.origin,boundaryFraction:unit,
            radialFraction:ScalarInterval(lower:0.25,upper:0.75),tolerance:tolerance)
        #expect(fan.allSatisfy { $0.derivativeU == nil && $0.secondUU == nil })
        for (r,density) in [(0.25,densities[0]),(0.75,densities[1])] {
            let values = [density*r,0.02*r*density*r,0.03*r*0.5*density*r,
                (r < 0.5 ? 0 : 0.04*r-0.02)*density*r]
            for i in fan.indices { #expect(fan[i].value.contains(values[i])) }
        }
        let other = try PreparedSurfaceAreaIntegrand(surface:foldedSupport(knot:0.37),tolerance:tolerance)
        do {
            _ = try other.rectangularTranslationBounds(rectangle:domains[0].rectangle,
                fraction:unit,reference:.origin,tolerance:tolerance,domain:domains[0])
            Issue.record("Foreign prepared-span identity must not select a one-sided derivative.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
        do {
            _ = try prepared.nativeRectangleDomains(over:SurfaceParameterBox(
                u:ScalarInterval(lower:-0.1,upper:1),v:unit),maximumCount:16,tolerance:tolerance)
            Issue.record("Span intersection must not discard part of the original domain.")
        } catch let error as KernelError { #expect(error.code == .classificationFailure) }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePiecesShareOneAggregateErrorAndResourceBudget() throws {
        let unit = try ScalarInterval(lower:0,upper:1)
        let cell = SurfaceAreaAdaptiveIntegral.Cell(t:unit,r:unit,depth:1,rectangle:nil,domain:nil)
        var work = 0
        do {
            _ = try SurfaceAreaAdaptiveIntegral().integrate(cells:[cell,cell],goals:[1,1,1,1],
                options:FaceAreaIntegrationOptions(maximumCellCount:6),work:&work,tolerance:tolerance) { cell in
                    let measure = cell.t.width*cell.r.width
                    return .init(contribution:Array(repeating:OutwardScalarInterval(lower:-0.75*measure,upper:0.75*measure),count:4),splitT:true)
                }
            Issue.record("Two pieces each below the target cannot spend that target twice.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
            #expect(work == 7 && error.residual == 7)
        }
        let knot = 0.37
        let (id,model) = try fixture(foldedSupport(knot:knot),holes:[rectangle(knot/2,(1+knot)/2,0.25,0.75)])
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:3))
            Issue.record("Native pieces in another loop must share the original work counter.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func c0UnprovedCrossSpanCutsFailWithinTheBudgetAndCancellationRemainsTyped() async throws {
        let curves: [SurfaceParameterCurve] = [.constantV(v:0,uStart:0,uEnd:1),
            .affine(origin:Point2D(x:1,y:0),direction:Point2D(x:-1,y:1),startParameter:0,endParameter:1),
            .constantU(u:0,vStart:1,vEnd:0)]
        let (id,model) = try fixture(foldedSupport(knot:0.37),outer:curves)
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:8))
            Issue.record("Unproved fan cuts cannot manufacture a smooth cross-knot success.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("C0 cancellation must remain observable.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    private func foldedSupport(knot: Double) -> Surface3D {
        .bSpline(BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,knot,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,0.03].map { y in [.init(x:0,y:y,z:0),
                .init(x:0.02*knot,y:y,z:0),.init(x:0.02,y:y,z:0.02)] }))
    }

    private func periodicStrip(uPeriodic: Bool) throws -> BSplineSurface3D {
        let circle = [(0.02,0.0),(0.0,0.02),(-0.02,0.0),(0.0,-0.02)]
        let points = uPeriodic ? [0.0,0.03].map { z in
            circle.map { Point3D(x:$0.0,y:$0.1,z:z) }
        } : circle.map { entry in
            [0.0,0.03].map { Point3D(x:entry.0,y:entry.1,z:$0) }
        }
        return try BSplineSurface3D.periodic(uDegree:uPeriodic ? 3 : 1,vDegree:uPeriodic ? 1 : 3,
            uKnots:uPeriodic ? [0,1,2,3,4] : [0,0,1,1],
            vKnots:uPeriodic ? [0,0,1,1] : [0,1,2,3,4],controlPoints:points,
            isUPeriodic:uPeriodic,isVPeriodic:!uPeriodic,tolerance:tolerance)
    }

    private func quarterCylinderBlend() -> Surface3D {
        func rail(_ y: Double, _ z: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:1,knots:[0,0,1,1],
                controlPoints:[Point3D(x:0,y:y,z:z),Point3D(x:0.02,y:y,z:z)]))
        }
        return .procedural(.rollingBall(RollingBallBlendSurface3D(centerSpine:rail(0,0),
            firstContact:rail(0.01,0),secondContact:rail(0,0.01),radius:0.01,tolerance:tolerance)))
    }

    private func independentPeriodicSection(_ parameter: Double)
        -> (point: Point3D, first: Vector3D, second: Vector3D, third: Vector3D) {
        let remainder = parameter.truncatingRemainder(dividingBy:4)
        let u = remainder < 0 ? remainder+4 : remainder
        let span = Int(floor(u)), t = u-Double(span), radius = 0.02
        func rotate(_ x: Double, _ y: Double) -> (Double,Double) {
            switch span {
            case 0: return (x,y)
            case 1: return (-y,x)
            case 2: return (-x,-y)
            default: return (y,-x)
            }
        }
        let p = rotate(radius*(t*t*t/3-t),radius*(t*t*t/3-t*t+2.0/3))
        let d = rotate(radius*(t*t-1),radius*(t*t-2*t))
        let dd = rotate(2*radius*t,2*radius*(t-1))
        let ddd = rotate(2*radius,2*radius)
        return (Point3D(x:p.0,y:p.1,z:0),Vector3D(x:d.0,y:d.1,z:0),
                Vector3D(x:dd.0,y:dd.1,z:0),Vector3D(x:ddd.0,y:ddd.1,z:0))
    }
}
