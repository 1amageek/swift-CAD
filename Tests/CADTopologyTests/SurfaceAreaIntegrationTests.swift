import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing
import Synchronization

@Suite("Certified free-surface area")
struct SurfaceAreaIntegrationTests {
    private func execution(_ budget: OriginalQueryBudget? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try budget ?? OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: Int.max, maximumCoefficientDepth: Int.max))
    }

    private func retainedKernelFailure(_ error: any Error) -> KernelError? {
        if let kernel = error as? KernelError { return kernel }
        if let query = error as? OriginalQueryFailure { return retainedKernelFailure(query.originalError) ?? query.kernelFailure }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retainedKernelFailure(cause)
        }
        return nil
    }

    private func retainedRefinementFailure(_ error: any Error) -> Bool {
        if error is SurfaceAreaEnclosureRefinementRequired { return true }
        if let query = error as? OriginalQueryFailure { return retainedRefinementFailure(query.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retainedRefinementFailure(cause)
        }
        return false
    }

    private func retainedQueryFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let query = error as? OriginalQueryFailure { return query }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retainedQueryFailure(cause)
        }
        return nil
    }

    private func retainedWorkLimit(_ error: any Error) -> Bool {
        if let scalar = error as? ExactScalarFailure {
            if case .resourceLimit(.work) = scalar { return true }
            if case .admissionRejected(let cause) = scalar { return retainedWorkLimit(cause) }
        }
        if let query = error as? OriginalQueryFailure { return retainedWorkLimit(query.originalError) }
        return false
    }

    private func exactWorkBoundary<State>(
        prepare: (inout OriginalQueryExecution) throws -> State,
        operation: (State, inout OriginalQueryExecution) throws -> Void,
        function: StaticString = #function
    ) throws {
        let measuredBudget = try OriginalQueryBudget()
        var measured = try execution(measuredBudget)
        let state = try prepare(&measured)
        let preparationWork = measuredBudget.snapshot.work
        try operation(state, &measured)
        let totalWork = measuredBudget.snapshot.work
        #expect(totalWork > preparationWork)
        print("CANONICAL_WORK_BOUNDARY function=\(function) preparation=\(preparationWork) total=\(totalWork)")
        for ceiling in [totalWork, totalWork - 1] {
            let budget = try OriginalQueryBudget(workLimit: ceiling)
            var bounded = try execution(budget)
            let prepared = try prepare(&bounded)
            #expect(budget.snapshot.work == preparationWork)
            do {
                try operation(prepared, &bounded)
                #expect(ceiling == totalWork)
                #expect(budget.snapshot.work == totalWork)
            } catch {
                #expect(ceiling == totalWork - 1)
                let failure = try #require(retainedQueryFailure(error))
                #expect(failure.kernelFailure.code == .resourceLimitExceeded)
                let resource = try #require(failure.context.resource)
                #expect(resource.axis == .work)
                #expect(resource.limit == .known(ceiling))
                #expect(retainedWorkLimit(failure.originalError))
                guard case .known(let used) = resource.used,
                      case .known(let requested) = resource.requested else {
                    Issue.record("The actual work owner lost its known debit observation.")
                    continue
                }
                let debit = used.addingReportingOverflow(requested)
                #expect(!debit.overflow && debit.partialValue > ceiling)
            }
        }
    }

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

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func parabolaExtrusionHasAnalyticAreaAndMoments(_ mapped: Bool) throws {
        let transform = try areaFixtureTransform()
        let source = graph()
        let support = mapped ? try transform.applying(to:source,tolerance:tolerance) : source
        let curves = mapped ? try rigidTrims(rectangle(),source:source,target:support,transform:transform) : rectangle()
        let (id, model) = try fixture(support,outer:curves)
        let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
        let a = 0.02, k = 10.0, t = 2*k*a
        let length = (t * sqrt(1+t*t) + asinh(t)) / (4*k)
        let momentX = (pow(1+t*t,1.5)-1) / (12*k*k)
        let momentZ = (t*sqrt(1+t*t)*(2*t*t+1)-asinh(t)) / (64*k*k)
        #expect(abs(result.area - length*0.03) <= tolerance.distance*tolerance.distance+tolerance.relative*length*0.03)
        let center = Point3D(x:momentX/length,y:0.015,z:momentZ/length)
        #expect((result.centroid - (mapped ? areaFixtureImage(of:center) : center)).length <= tolerance.distance)
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
        var admitted = try execution()
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
        let prepared = try #require(try SurfaceAreaTranslatedRollingBallJet(blend, using: &admitted))
        let box = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:1),
            v:try ScalarInterval(lower:0,upper:1))
        let jet = try prepared.intervalJet(over:box,tolerance:tolerance, using: &admitted)
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
        var admitted = try execution()
        func rail(_ y: Double, _ z: Double, _ dx: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:1,knots:[0,0,1,1],
                controlPoints:[Point3D(x:0,y:y,z:z),Point3D(x:dx,y:y,z:z)]))
        }
        let blend = RollingBallBlendSurface3D(centerSpine:rail(0,0,0.02),
            firstContact:rail(0.01,0,0.020001),secondContact:rail(0,0.01,0.02),
            radius:0.01,tolerance:tolerance)
        #expect(try SurfaceAreaTranslatedRollingBallJet(blend, using: &admitted) == nil)
        let surface = Surface3D.procedural(.rollingBall(blend))
        let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance, using: &admitted)
        #expect(prepared.translationDirection == nil)
        let fraction = try ScalarInterval(lower:0.5,upper:0.50001)
        let fields = try prepared.bounds(curve:.constantU(u:0.5,vStart:0,vEnd:1),
            anchor:SurfaceParameter(u:0.25,v:0.25),reference:.origin,
            boundaryFraction:fraction,radialFraction:fraction,tolerance:tolerance, using: &admitted)
        #expect(fields.count == 4 && fields.allSatisfy { $0.value.isFinite })
        let point = try surface.point(u:0.4,v:0.6,tolerance:tolerance)
        let direct = try PreparedSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &admitted)
            .enclosure(over:SurfaceParameterBox(u:ScalarInterval(lower:0.4,upper:0.40001),
                v:ScalarInterval(lower:0.6,upper:0.60001)),tolerance:tolerance, using: &admitted).position
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
        } catch let error as KernelError { print("AREA_PROFILE fixture=rolling budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == Double(budget+1))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rollingTranslationCertificateReportsBoundedDyadicErrorProbe() throws {
        var admitted = try execution()
        let prepared = try PreparedSurfaceAreaIntegrand(surface:quarterCylinderBlend(),tolerance:tolerance, using: &admitted)
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
                        fraction:fraction,reference:Point3D(x:0,y:0.01,z:0),tolerance:tolerance, using: &admitted)
                    let center = try prepared.rectangularTranslationBounds(rectangle:box,
                        fraction:ScalarInterval(lower:fraction.midpoint,upper:fraction.midpoint),
                        reference:Point3D(x:0,y:0.01,z:0),tolerance:tolerance, using: &admitted)
                    for i in fields.indices {
                        let hessian = try #require(fields[i].secondUU)
                        let midpointError = center[i].value.width*0.5
                        let hessianError = hessian.width*width*width/48
                        print("AREA_ERROR_PROBE fixture=rolling depth=\(depth) station=\(station) field=\(i) midpointError=\(midpointError) hessianError=\(hessianError) goal=\(goals[i]) ratio=\((midpointError+hessianError)/goals[i])")
                    }
                } catch {
                    let error = try #require(retainedKernelFailure(error))
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

    @Test(.timeLimit(.minutes(1)), arguments:[0,1,2])
    func curvedOffsetHasKnownAreaAndIndependentCentroidIntegral(_ mapping: Int) throws {
        let distance = 0.001, a = 0.02, b = 0.03, k = 10.0
        let offset = OffsetSurface3D(source: graph(), distance: distance)
        let originalSupport = Surface3D.procedural(.offset(offset))
        let transform = try areaFixtureTransform()
        let support = mapping == 2 ? try transform.applying(to:originalSupport,tolerance:tolerance) : originalSupport
        let sourceTrims = mapping > 0 ? try rectangle().map { .offsetSurfaceImage(try offset.parameterCurveImage(
            transporting:$0,tolerance:tolerance)) } : rectangle()
        let trims = mapping == 2 ? try rigidTrims(sourceTrims,source:originalSupport,target:support,transform:transform) : sourceTrims
        let (id, model) = try fixture(support,outer:trims)
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
        let center = Point3D(x:momentX/area,y:0.015,z:momentZ/area)
        #expect((result.centroid-(mapping == 2 ? areaFixtureImage(of:center) : center)).length <= offsetTolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func polynomialOffsetBoundsContainAnalyticDensityDerivatives() throws {
        var admitted = try execution()
        let a = 0.02, b = 0.03, k = 10.0, distance = 0.001
        let support = Surface3D.procedural(.offset(OffsetSurface3D(source: graph(), distance: distance)))
        let prepared = try PreparedSurfaceAreaIntegrand(surface: support, tolerance: tolerance, using: &admitted)
        let unit = try ScalarInterval(lower: 0, upper: 1)
        let rectangle = SurfaceParameterBox(u: unit, v: unit)
        // Differentiate the independent analytic physical-X offset area element.
        // This exercises the actual source-jet -> offset-normal -> density path,
        // including Hessians enabled only by the exact fourth-source-zero proof.
        let c2 = pow(2*k*a, 2), d = 2*k*distance
        for (lower, upper) in [(0.0,0.01),(0.49,0.51),(0.99,1.0)] {
            let bounds = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                fraction: ScalarInterval(lower: lower, upper: upper), reference: .origin,
                tolerance: tolerance, using: &admitted)[0]
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
        var admitted = try execution()
        let prepared = try PreparedSurfaceAreaIntegrand(surface: graph(), tolerance: tolerance, using: &admitted)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower:0,upper:1),
                                      v: try ScalarInterval(lower:-0.1,upper:1.1))
        do {
            _ = try prepared.rectangularTranslationBounds(rectangle:box,
                fraction:ScalarInterval(lower:0.4,upper:0.6),reference:.origin,tolerance:tolerance, using: &admitted)
            Issue.record("Eliminating a band must not admit its out-of-domain endpoints.")
        } catch SurfaceAreaEnclosureRefinementRequired.parameterDomain {}
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicStripBoundsContainIndependentSeamAndShiftDerivatives() throws {
        var admitted = try execution()
        let height = 0.03
        for uPeriodic in [true,false] {
            let surface = try periodicStrip(uPeriodic:uPeriodic)
            let prepared = try PreparedSurfaceAreaIntegrand(surface:.bSpline(surface),tolerance:tolerance, using: &admitted)
            for (lower,upper) in [(-0.3,-0.1),(-4.25,-3.75),(-0.25,0.25),(7.75,8.25)] {
                let cycle = try ScalarInterval(lower:lower,upper:upper)
                let open = try ScalarInterval(lower:0,upper:1)
                let box = SurfaceParameterBox(u:uPeriodic ? cycle : open,v:uPeriodic ? open : cycle)
                let fields = try prepared.rectangularTranslationBounds(rectangle:box,
                    fraction:ScalarInterval(lower:0,upper:1),reference:.origin,tolerance:tolerance, using: &admitted)
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
        } catch let error as KernelError { print("AREA_PROFILE fixture=affine budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
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
        } catch let error as KernelError { print("AREA_PROFILE fixture=curved budget=\(budget) outcome=\(error.code.rawValue) residual=\(String(describing: error.residual)) elapsed=\(started.duration(to: .now))")
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
        var admitted = try execution()
        let prepared = try PreparedSurfaceAreaIntegrand(surface:foldedSupport(knot:0.5),tolerance:tolerance, using: &admitted)
        let unit = try ScalarInterval(lower:0,upper:1)
        let box = SurfaceParameterBox(u:unit,v:unit)
        let domains = try #require(try prepared.nativeRectangleDomains(over:box,maximumCount:16,tolerance:tolerance, using: &admitted))
        #expect(domains.count == 2)
        for domain in domains {
            let fields = try prepared.rectangularTranslationBounds(rectangle:domain.rectangle,
                fraction:unit,reference:.origin,tolerance:tolerance,domain:domain, using: &admitted)
            #expect(fields.allSatisfy { $0.derivativeU != nil && $0.derivativeV != nil && $0.secondUU != nil })
        }
        let crossing = try prepared.rectangularTranslationBounds(rectangle:box,
            fraction:ScalarInterval(lower:0.25,upper:0.75),reference:.origin,tolerance:tolerance, using: &admitted)
        #expect(crossing.allSatisfy { $0.derivativeU == nil && $0.derivativeV == nil && $0.secondUU == nil && $0.secondUV == nil && $0.secondVV == nil })
        let densities = [0.0006,0.03*hypot(0.02,0.04)]
        for (u,density) in [(0.25,densities[0]),(0.75,densities[1])] {
            let z = u < 0.5 ? 0 : 0.04*u-0.02
            let values = [density,0.02*u*density,0.015*density,z*density]
            for i in crossing.indices { #expect(crossing[i].value.contains(values[i])) }
        }
        let fan = try prepared.bounds(curve:.constantU(u:1,vStart:0,vEnd:1),
            anchor:SurfaceParameter(u:0,v:0),reference:.origin,boundaryFraction:unit,
            radialFraction:ScalarInterval(lower:0.25,upper:0.75),tolerance:tolerance, using: &admitted)
        #expect(fan.allSatisfy { $0.derivativeU == nil && $0.secondUU == nil })
        for (r,density) in [(0.25,densities[0]),(0.75,densities[1])] {
            let values = [density*r,0.02*r*density*r,0.03*r*0.5*density*r,
                (r < 0.5 ? 0 : 0.04*r-0.02)*density*r]
            for i in fan.indices { #expect(fan[i].value.contains(values[i])) }
        }
        let other = try PreparedSurfaceAreaIntegrand(surface:foldedSupport(knot:0.37),tolerance:tolerance, using: &admitted)
        do {
            _ = try other.rectangularTranslationBounds(rectangle:domains[0].rectangle,
                fraction:unit,reference:.origin,tolerance:tolerance,domain:domains[0], using: &admitted)
            Issue.record("Foreign prepared-span identity must not select a one-sided derivative.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        do {
            _ = try prepared.nativeRectangleDomains(over:SurfaceParameterBox(
                u:ScalarInterval(lower:-0.1,upper:1),v:unit),maximumCount:16,tolerance:tolerance, using: &admitted)
            Issue.record("Span intersection must not discard part of the original domain.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .classificationFailure)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nativePiecesShareOneAggregateErrorAndResourceBudget() throws {
        var admitted = try execution()
        let unit = try ScalarInterval(lower:0,upper:1)
        let cell = SurfaceAreaAdaptiveIntegral.Cell(t:unit,r:unit,depth:1,rectangle:nil,domain:nil)
        var work = 0
        do {
            _ = try SurfaceAreaAdaptiveIntegral().integrate(cells:[cell,cell],goals:[1,1,1,1],
                options:FaceAreaIntegrationOptions(maximumCellCount:6),work:&work,tolerance:tolerance, using: &admitted) { cell, _, _ in
                    let measure = cell.t.width*cell.r.width
                    return .init(contribution:Array(repeating:OutwardScalarInterval(lower:-0.75*measure,upper:0.75*measure),count:4),splitT:true)
                }
            Issue.record("Two pieces each below the target cannot spend that target twice.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
            #expect(work == 7 && error.residual == 7)
        }
        let knot = 0.37
        let (id,model) = try fixture(foldedSupport(knot:knot),holes:[rectangle(knot/2,(1+knot)/2,0.25,0.75)])
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:3))
            Issue.record("Native pieces in another loop must share the original work counter.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
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

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func mappedRigidRectangleAndHoleHaveIndependentAreaAndAllCentroidComponents(_ reversed: Bool) throws {
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let outer = try rigidTrims(rectangle(),source:source,target:target,transform:transform)
        let hole = try rigidTrims(rectangle(0.25,0.5,0.25,0.75),source:source,target:target,transform:transform)
        let (id,model) = try fixture(target,outer:outer,holes:[hole],reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expectedArea = 0.0007
        let original = Point3D(x:(0.0008*0.02-0.0001*0.015)/expectedArea,y:0.01,z:0)
        #expect(abs(result.area-expectedArea) <= tolerance.distance*tolerance.distance+tolerance.relative*expectedArea)
        #expect((result.centroid-areaFixtureImage(of:original)).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func mappedRigidC0HoleRetainsOriginalNativePartitionsAndSharedWorkCounter(_ reversed: Bool) throws {
        let knot = 0.37, x = 0.02*knot, firstArea = 0.03*x
        let secondArea = 0.03*hypot(0.02-x,0.02)
        let source = foldedSupport(knot:knot), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let outer = try rigidTrims(rectangle(),source:source,target:target,transform:transform)
        let hole = try rigidTrims(rectangle(knot/2,(1+knot)/2,0.25,0.75),source:source,target:target,transform:transform)
        let (id,model) = try fixture(target,outer:outer,holes:[hole],reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let area = 0.75*(firstArea+secondArea)
        let center = Point3D(x:(firstArea*x/2+secondArea*(x+0.02)/2-firstArea/4*0.75*x
            - secondArea/4*(0.75*x+0.25*0.02))/area,y:0.015,
            z:(secondArea*0.01-secondArea/4*0.005)/area)
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-areaFixtureImage(of:center)).length <= tolerance.distance)
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:3))
            Issue.record("Mapped native spans and loops must share the original query work counter.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedRigidFractionJetsContainIndependentHarmonicAndRationalDerivatives() throws {
        var admitted = try execution()
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let charts: [SurfaceParameterCurve] = [.harmonic(center:Point2D(x:0.5,y:0.5),
            cosine:Point2D(x:0.125,y:0),sine:Point2D(x:0,y:0.125),startParameter:-.pi/2,endParameter:.pi/2),
            .bSpline(BSplineCurve2D(degree:2,knots:[2,2,2,5,5,5],
                controlPoints:[Point2D(x:0.75,y:0.5),Point2D(x:0.75,y:0.75),Point2D(x:0.5,y:0.75)],
                weights:[1,sqrt(0.5),1]))]
        for (kind,base) in charts.enumerated() {
            let curve = SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
                source:SurfaceLiftCurve3D(surface:source,parameterCurve:base),targetSurface:target,
                transform:transform,startFraction:0.875,endFraction:0.125,tolerance:tolerance))
            let prepared = try SurfaceAreaParameterChartEncloser(curve:curve,on:target,tolerance:tolerance, using: &admitted)
            for index in 0..<8 {
                let lower = Double(index)/8, upper = Double(index+1)/8
                let jet = try prepared.intervalJet(over:ScalarInterval(lower:lower,upper:upper),tolerance:tolerance, using: &admitted)
                for fraction in [lower,(lower+upper)/2,upper] {
                    let q = 0.875-0.75*fraction, scale = -0.75
                    let u: [Double], v: [Double]
                    if kind == 0 {
                        let theta = -.pi/2 + .pi*q, rate = .pi*scale
                        u = [0.5+0.125*cos(theta),-0.125*sin(theta)*rate,
                             -0.125*cos(theta)*rate*rate,0.125*sin(theta)*rate*rate*rate]
                        v = [0.5+0.125*sin(theta),0.125*cos(theta)*rate,
                             -0.125*sin(theta)*rate*rate,-0.125*cos(theta)*rate*rate*rate]
                    } else {
                        let w = sqrt(0.5), denominator = 1+2*(w-1)*q+2*(1-w)*q*q
                        let d1 = 2*(w-1)+4*(1-w)*q, d2 = 4*(1-w)
                        func quotient(_ n: Double,_ n1: Double,_ n2: Double) -> [Double] {
                            let value = n/denominator, first = (n1-d1*value)/denominator
                            let second = (n2-d2*value-2*d1*first)/denominator
                            let third = (-3*d2*first-3*d1*second)/denominator
                            return [value,first*scale,second*scale*scale,third*scale*scale*scale]
                        }
                        u = quotient(0.75+1.5*(w-1)*q+(1.25-1.5*w)*q*q,
                            1.5*(w-1)+2*(1.25-1.5*w)*q,2*(1.25-1.5*w))
                        v = quotient(0.5+(1.5*w-1)*q+(1.25-1.5*w)*q*q,
                            1.5*w-1+2*(1.25-1.5*w)*q,2*(1.25-1.5*w))
                    }
                    for (field,expected) in [(jet.u,u),(jet.v,v)] {
                        #expect(field.value.contains(expected[0]))
                        #expect(field.derivativeU.contains(expected[1]))
                        #expect(field.secondDerivativeUU.contains(expected[2]))
                        #expect(field.thirdDerivativeUUU.contains(expected[3]))
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func mappedRigidPartialFractionsRetainTheOriginalRectangleAndReversal(_ reversed: Bool) throws {
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let originals: [SurfaceParameterCurve] = [.constantV(v:0.25,uStart:0,uEnd:1),
            .constantU(u:0.75,vStart:0,vEnd:1),.constantV(v:0.75,uStart:1,uEnd:0),
            .constantU(u:0.25,vStart:1,vEnd:0)]
        let curves = try originals.map { SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
            source:SurfaceLiftCurve3D(surface:source,parameterCurve:$0),targetSurface:target,transform:transform,
            startFraction:0.25,endFraction:0.75,tolerance:tolerance)) }
        let (id,model) = try fixture(target,outer:curves,reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let area = 0.0002
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        #expect((result.centroid-areaFixtureImage(of:Point3D(x:0.02,y:0.01,z:0))).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedNonIdentityAffineUVUsesTheOriginalFractionChain() throws {
        var admitted = try execution()
        let source = Surface3D.plane(Plane3D(origin:.origin,normal:.unitZ))
        let transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let curve = SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
            source:SurfaceLiftCurve3D(surface:source,parameterCurve:.affine(origin:Point2D(x:0.2,y:0.3),
                direction:Point2D(x:0.1,y:0.2),startParameter:0,endParameter:1)),
            targetSurface:target,transform:transform,startFraction:0.875,endFraction:0.125,tolerance:tolerance))
        let prepared = try SurfaceAreaParameterChartEncloser(curve:curve,on:target,tolerance:tolerance, using: &admitted)
        let jet = try prepared.intervalJet(over:ScalarInterval(lower:0.25,upper:0.75),tolerance:tolerance, using: &admitted)
        // With identical +Z plane bases, an exact 90-degree rotation maps (u,v) to (-v,u).
        for fraction in [0.25,0.5,0.75] {
            let q = 0.875-0.75*fraction
            #expect(jet.u.value.contains(-(0.3+0.2*q)))
            #expect(jet.v.value.contains(0.2+0.1*q))
            #expect(jet.u.derivativeU.contains(0.15))
            #expect(jet.v.derivativeU.contains(-0.075))
            #expect(jet.u.secondDerivativeUU.contains(0) && jet.v.secondDerivativeUU.contains(0))
            #expect(jet.u.thirdDerivativeUUU.contains(0) && jet.v.thirdDerivativeUUU.contains(0))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedChartCancellationRemainsAQueryFailure() async throws {
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let curves = try rigidTrims(rectangle(),source:source,target:target,transform:transform)
        let (id,model) = try fixture(target,outer:curves)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Mapped chart preparation cannot hide query cancellation.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedChartForeignTargetsOutsideFractionsAndNonAffineMapsFailExplicitly() throws {
        var admitted = try execution()
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let image = try RigidImageSurfaceParameterCurve(source:SurfaceLiftCurve3D(surface:source,
            parameterCurve:rectangle()[0]),targetSurface:target,transform:transform,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.rigidImage(image),on:source,tolerance:tolerance, using: &admitted)
            Issue.record("A mapped trim cannot authorize a different face support.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        let outside = try RigidImageSurfaceParameterCurve(source:image.source,targetSurface:target,
            transform:transform,startFraction:-tolerance.relative/2,endFraction:1,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.rigidImage(outside),on:target,tolerance:tolerance, using: &admitted)
            Issue.record("A tolerated source fraction outside the original chart cannot be clamped into an integral.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        let sphere = Surface3D.analytic(.sphere(center:.origin,radius:0.02))
        let rotation = try RigidTransform3D.rotated(around:.origin,direction:.unitX,angle:.pi/2,tolerance:tolerance)
        let sphericalTarget = try rotation.applying(to:sphere,tolerance:tolerance)
        let sphericalImage = try RigidImageSurfaceParameterCurve(source:SurfaceLiftCurve3D(surface:sphere,
            parameterCurve:.constantV(v:0,uStart:0.1,uEnd:0.3)),targetSurface:sphericalTarget,
            transform:rotation,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.rigidImage(sphericalImage),on:sphericalTarget,tolerance:tolerance, using: &admitted)
            Issue.record("Non-affine spherical charts still require their own whole-interval proof.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .unsupportedCapability)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bsplineSurfaceLiftRuledRectangleRetainsItsDefaultAreaAndMoments() throws {
        let source = flatAreaSupport()
        let support = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary:.surfaceLift(SurfaceLiftCurve3D(surface:source,
                parameterCurve:.constantV(v:0,uStart:0,uEnd:1))),
            endBoundary:.surfaceLift(SurfaceLiftCurve3D(surface:source,
                parameterCurve:.constantV(v:1,uStart:0,uEnd:1))))))
        let (id,model) = try fixture(support)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area-0.0008) <= tolerance.distance*tolerance.distance+tolerance.relative*0.0008)
        #expect((result.centroid-Point3D(x:0.02,y:0.01,z:0)).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func ruledSurfaceLiftAdmissionRetainsItsExactSupportAndEnclosingDepth() throws {
        var admitted = try execution()
        let source = Surface3D.plane(Plane3D(origin:.origin,normal:.unitZ))
        let startChart = SurfaceParameterCurve.constantV(v:0,uStart:0,uEnd:0.04)
        let endRail = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface:source,
            parameterCurve:.constantV(v:0.02,uStart:0,uEnd:0.04)))
        func support(_ chart: SurfaceParameterCurve) -> Surface3D {
            .procedural(.ruled(RuledSurface3D(startBoundary:.surfaceLift(SurfaceLiftCurve3D(
                surface:source,parameterCurve:chart)),endBoundary:endRail)))
        }
        let (id,model) = try fixture(support(startChart))
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area-0.0008) <= tolerance.distance*tolerance.distance+tolerance.relative*0.0008)
        #expect((result.centroid-Point3D(x:0.02,y:0.01,z:0)).length <= tolerance.distance)

        var nested = startChart
        for _ in 0..<15 { nested = .periodicTranslation(base:nested,uShift:0,vShift:0) }
        // The chart is within the standalone limit; two enclosing ruled/lift
        // levels put the same native source beyond the one admission depth limit.
        try SurfaceAreaParameterChartEncloser.validateAdmission(curve:nested,on:source,
            maximumControlPointCount:65_536,maximumBoundaryCurveCount:4_096,tolerance:tolerance, using: &admitted)
        let (nestedID,nestedModel) = try fixture(support(nested))
        do {
            _ = try nestedModel.faceAreaMeasurement(of:nestedID,tolerance:tolerance)
            Issue.record("Surface-lift trim admission cannot restart its enclosing source depth at zero.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func mappedNestedSourceDimensionsAndDepthFailBeforeRecursiveValidation() throws {
        var admitted = try execution()
        let source = flatAreaSupport(), transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let good = try RigidImageSurfaceParameterCurve(source:SurfaceLiftCurve3D(surface:source,
            parameterCurve:rectangle()[0]),targetSurface:target,transform:transform,tolerance:tolerance)
        var encoded = try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(good)) as? [String:Any])
        var lift = try #require(encoded["source"] as? [String:Any])
        let bad = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree:2,knots:Array(repeating:0,count:30),
            controlPoints:[Point2D(x:0,y:0),Point2D(x:0.5,y:0),Point2D(x:1,y:0)]))
        lift["parameterCurve"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(bad))
        encoded["source"] = lift
        let malformed = try JSONDecoder().decode(RigidImageSurfaceParameterCurve.self,
            from:JSONSerialization.data(withJSONObject:encoded))
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.rigidImage(malformed),on:target,
                maximumControlPointCount:8,tolerance:tolerance, using: &admitted)
            Issue.record("Oversized nested knot arrays must fail before recursive image validation.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        var nested = SurfaceParameterCurve.rigidImage(good)
        for _ in 0..<17 { nested = .periodicTranslation(base:nested,uShift:0,vShift:0) }
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:nested,on:target,tolerance:tolerance, using: &admitted)
            Issue.record("Mapped chart nesting cannot grant another preparation depth budget.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func affineImplicitPartialTrimHasIndependentTiltedAreaAndCentroid(_ reversed: Bool) throws {
        let (source,intersection) = try affineImplicitAreaFixture()
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.75,endFraction:0.25,tolerance:tolerance)
        let trims = [SurfaceParameterCurve.constantV(v:7.5,uStart:2.75,uEnd:4.25),
            .constantU(u:4.25,vStart:7.5,vEnd:8.5),
            .constantV(v:8.5,uStart:4.25,uEnd:2.75),.certifiedImplicit(implicit)]
        let (id,model) = try fixture(.bSpline(source),outer:trims,reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expectedArea = 0.000152587890625
        #expect(abs(result.area-expectedArea) <= tolerance.distance*tolerance.distance+tolerance.relative*expectedArea)
        #expect((result.centroid-Point3D(x:0.140625,y:0.2578125,z:0.51171875)).length <= tolerance.distance)
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:1))
            Issue.record("Implicit chart preparation must not grant another adaptive work budget.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func affineImplicitJetsRetainNativeFractionsRolesAndCellDirection(_ backwards: Bool) throws {
        var admitted = try execution()
        let (source,intersection) = try affineImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let curve = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,
                startFraction:0.75,endFraction:0.25,tolerance:tolerance)
            let support = role == .first ? Surface3D.bSpline(source) : intersection.secondSurface
            let prepared = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(curve),on:support,tolerance:tolerance, using: &admitted)
            let fraction = try ScalarInterval(lower:0.2,upper:0.6)
            let actual = try prepared.intervalJet(over:fraction,tolerance:tolerance, using: &admitted)
            for t in [0.2,0.4,0.6] {
                let mapped = 0.75-0.5*t
                let s = backwards ? 1-mapped : mapped
                let expectedU = role == .first ? 2.75 : (1+s)/3
                let expectedV = role == .first ? 7+2*s : 5.0/12
                #expect(actual.u.value.contains(expectedU) && actual.v.value.contains(expectedV))
            }
            let slope = backwards ? 0.5 : -0.5
            #expect(actual.u.derivativeU.contains(role == .first ? 0 : slope/3))
            #expect(actual.v.derivativeU.contains(role == .first ? 2*slope : 0))
            for field in [actual.u,actual.v] {
                #expect(field.secondDerivativeUU.lower == 0 && field.secondDerivativeUU.upper == 0)
                #expect(field.thirdDerivativeUUU.lower == 0 && field.thirdDerivativeUUU.upper == 0)
            }
            // Original point evaluation uses cell native free UV, not arc length.
            let original = try curve.parameter(atNormalizedFraction:0.4,tolerance:tolerance)
            #expect(actual.u.value.contains(original.u) && actual.v.value.contains(original.v))
            let point = try prepared.intervalJet(over:ScalarInterval(lower:0.4,upper:0.4),tolerance:tolerance, using: &admitted)
            #expect(point.u.value.contains(original.u) && point.v.value.contains(original.v))
            #expect(point.u.value.upper-point.u.value.lower < 1e-10)
            #expect(point.v.value.upper-point.v.value.lower < 1e-10)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineImplicitAdmissionRejectsForeignFractionsAndNonAffineFamily() throws {
        var admitted = try execution()
        let (source,intersection) = try affineImplicitAreaFixture()
        let good = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.25,endFraction:0.75,tolerance:tolerance)
        var foreign = source
        foreign.controlPoints = foreign.controlPoints.map { row in row.map { Point3D(x:$0.x,y:$0.y,z:$0.z+0.125) } }
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(good),on:.bSpline(foreign),tolerance:tolerance, using: &admitted)
            Issue.record("Implicit trim authority cannot be transferred to a foreign face support.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        let invalid = CertifiedImplicitSurfaceParameterCurve(validatedIntersection:intersection,role:.first,
            startFraction:0,endFraction:1+tolerance.relative/2)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(invalid),on:.bSpline(source),tolerance:tolerance, using: &admitted)
            Issue.record("Area admission must not clamp stored implicit source fractions.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        var nested = SurfaceParameterCurve.certifiedImplicit(good)
        for _ in 0..<17 { nested = .periodicTranslation(base:nested,uShift:0,vShift:0) }
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:nested,on:.bSpline(source),tolerance:tolerance, using: &admitted)
            Issue.record("Implicit source preparation must retain the shared nesting limit.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(good),on:.bSpline(source),
                maximumControlPointCount:3,tolerance:tolerance, using: &admitted)
            Issue.record("Both implicit supports must be bounded before source validation.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        let rational = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.4765625,0.546875].map { z in [Point3D(x:0.1328125,y:0.25,z:z),
                Point3D(x:0.1328125,y:0.265625,z:z)] },weights:[[1,0.5],[1,0.5]])
        let graph = try #require(try ExactAffineBilinearIntersectionGraph.certified(first:source,second:rational,tolerance:tolerance, using: &admitted))
        let nonAffine = try graph.certifiedImplicitCurve(first:source,second:rational,tolerance:tolerance, using: &admitted)
        let nonAffineTrim = try CertifiedImplicitSurfaceParameterCurve(intersection:nonAffine,role:.first,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(nonAffineTrim),on:.bSpline(source),tolerance:tolerance, using: &admitted)
            Issue.record("A non-affine implicit source requires a caller budget instead of the constant-system proof.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineImplicitCancellationRemainsAQueryFailure() async throws {
        let (source,intersection) = try affineImplicitAreaFixture()
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.75,endFraction:0.25,tolerance:tolerance)
        let trims = [SurfaceParameterCurve.constantV(v:7.5,uStart:2.75,uEnd:4.25),
            .constantU(u:4.25,vStart:7.5,vEnd:8.5),
            .constantV(v:8.5,uStart:4.25,uEnd:2.75),.certifiedImplicit(implicit)]
        let (id,model) = try fixture(.bSpline(source),outer:trims)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Implicit chart preparation cannot hide cancellation.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func affineImplicitChainRetainsUnequalNativePiecesAndExactArea(_ reversed: Bool) throws {
        let (source,intersection) = try affineImplicitChainFixture()
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.875,endFraction:0.125,tolerance:tolerance)
        // Original three-cell fractions map to native V=8.8125 and 7.09375.
        // The tilted parallelogram's literal area and all moments are independent
        // of the original chart's unequal speeds and non-dyadic 1/3,2/3 joins.
        let rectangleCurves = rectangle(2.75,4.25,7.09375,8.8125)
        // Start at bottom-right so the implicit left edge has a nonzero signed fan.
        let curves = [rectangleCurves[1],rectangleCurves[2],.certifiedImplicit(implicit),rectangleCurves[0]]
        let center = Point3D(x:0.140625,y:0.2574462890625,z:0.51171875)
        let area = 0.00026226043701171875
        let transform = try areaFixtureTransform()
        for mapped in [false,true] {
            let original = Surface3D.bSpline(source)
            let support = mapped ? try transform.applying(to:original,tolerance:tolerance) : original
            let trims = mapped ? try rigidTrims(curves,source:original,target:support,transform:transform) : curves
            let (id,model) = try fixture(support,outer:trims,reversed:reversed)
            let measured = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
            #expect(abs(measured.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
            #expect((measured.centroid-(mapped ? areaFixtureImage(of:center) : center)).length <= tolerance.distance)
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                    integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:1))
                Issue.record("A native implicit piece cannot receive another query work budget.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                    integrationOptions:FaceAreaIntegrationOptions(maximumSubdivisionDepth:1))
                Issue.record("A native implicit join cannot reset query subdivision depth.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func affineImplicitChainProofDistinguishesOwningPiecesAndJoins(_ backwards: Bool) throws {
        var admitted = try execution()
        let (source,intersection) = try affineImplicitChainFixture(direction:backwards ? .reversed : .forward)
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,
                startFraction:0.875,endFraction:0.125,tolerance:tolerance)
            let curve = SurfaceParameterCurve.certifiedImplicit(implicit)
            let support = role == .first ? Surface3D.bSpline(source) : intersection.secondSurface
            let prepared = try SurfaceAreaParameterChartEncloser(curve:curve,on:support,tolerance:tolerance, using: &admitted)
            #expect(prepared.hasNativeJoins)
            for endpoint in [0.0,1.0] {
                let actual = try prepared.intervalJet(over:ScalarInterval(lower:endpoint,upper:endpoint),tolerance:tolerance, using: &admitted)
                let point = try implicit.parameter(atNormalizedFraction:endpoint,tolerance:tolerance)
                #expect(actual.u.value.contains(point.u) && actual.v.value.contains(point.v))
            }
            let smooth = try prepared.intervalJet(over:ScalarInterval(lower:0.05,upper:0.1),tolerance:tolerance, using: &admitted)
            let nativeSlope = backwards ? 0.5625 : -1.125
            #expect(smooth.u.derivativeU.contains(role == .first ? 0 : nativeSlope/6))
            #expect(smooth.v.derivativeU.contains(role == .first ? nativeSlope : 0))
            #expect(smooth.u.secondDerivativeUU.lower == 0 && smooth.u.secondDerivativeUU.upper == 0)
            #expect(smooth.v.thirdDerivativeUUU.lower == 0 && smooth.v.thirdDerivativeUUU.upper == 0)
            let interval = try ScalarInterval(lower:0.2,upper:0.4)
            let proof = try prepared.intervalProof(over:interval,tolerance:tolerance, using: &admitted)
            guard case .valueOnly(let u,let v,let du,let dv) = proof else {
                Issue.record("Unequal native speeds at a join cannot authorize a smooth jet."); return
            }
            for t in [0.2,0.25,0.3,0.35,0.4] {
                let q = 0.875-0.75*t,forward = backwards ? 1-q : q
                let nativeV: Double
                if forward <= 1.0/3 { nativeV = 7+0.75*forward }
                else if forward <= 2.0/3 { nativeV = 7.25+3.75*(forward-1.0/3) }
                else { nativeV = 8.5+1.5*(forward-2.0/3) }
                #expect(u.contains(role == .first ? 2.75 : (nativeV-5)/6))
                #expect(v.contains(role == .first ? nativeV : 5.0/12))
                let original = try implicit.parameter(atNormalizedFraction:t,tolerance:tolerance)
                #expect(u.contains(original.u) && v.contains(original.v))
            }
            let slopes = backwards ? [0.5625,2.8125] : [-1.125,-2.8125]
            for slope in slopes {
                #expect(du.contains(role == .first ? 0 : slope/6))
                #expect(dv.contains(role == .first ? slope : 0))
            }
            guard case .valueOnly = try prepared.intervalProof(
                over:ScalarInterval(lower:5.0/18,upper:5.0/18),tolerance:tolerance, using: &admitted) else {
                Issue.record("A shared native endpoint must retain both owning one-sided charts."); return
            }
            do {
                _ = try prepared.intervalJet(over:interval,tolerance:tolerance, using: &admitted)
                Issue.record("A value-only join must not masquerade as a third-order jet.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .unsupportedCapability)
            }
            let integrand = try PreparedSurfaceAreaIntegrand(surface:support,tolerance:tolerance, using: &admitted)
            let anchor = role == .first ? SurfaceParameter(u:4.25,v:7.09375) : SurfaceParameter(u:0.2,v:0.2)
            let fields = try integrand.bounds(curve:curve,anchor:anchor,reference:.origin,
                boundaryFraction:interval,radialFraction:ScalarInterval(lower:0.25,upper:0.75),
                tolerance:tolerance,parameterChart:prepared, using: &admitted)
            #expect(fields.count == 4 && fields.allSatisfy {
                $0.derivativeU == nil && $0.derivativeV == nil && $0.secondUU == nil && $0.secondUV == nil && $0.secondVV == nil
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineImplicitChainJoinAuthorityPropagatesThroughOriginalWrappers() throws {
        var admitted = try execution()
        let (source,intersection) = try affineImplicitChainFixture()
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.875,endFraction:0.125,tolerance:tolerance)
        let curve = SurfaceParameterCurve.certifiedImplicit(implicit),support = Surface3D.bSpline(source)
        let transform = try areaFixtureTransform(),target = try transform.applying(to:support,tolerance:tolerance)
        let image = SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
            source:SurfaceLiftCurve3D(surface:support,parameterCurve:curve),targetSurface:target,
            transform:transform,startFraction:1,endFraction:0,tolerance:tolerance))
        let offset = OffsetSurface3D(source:support,distance:0.002)
        let offsetCurve = SurfaceParameterCurve.offsetSurfaceImage(try offset.parameterCurveImage(transporting:curve,tolerance:tolerance))
        for (wrapped,face) in [(image,target),(offsetCurve,Surface3D.procedural(.offset(offset))),
                              (.periodicTranslation(base:curve,uShift:0,vShift:0),support)] {
            let prepared = try SurfaceAreaParameterChartEncloser(curve:wrapped,on:face,tolerance:tolerance, using: &admitted)
            #expect(prepared.hasNativeJoins)
            guard case .valueOnly(let u,let v,_,_) = try prepared.intervalProof(
                over:ScalarInterval(lower:0,upper:1),tolerance:tolerance, using: &admitted) else {
                Issue.record("A wrapper cannot erase original native join authority."); return
            }
            let point = try wrapped.parameter(atNormalizedFraction:0.3,tolerance:tolerance)
            #expect(u.contains(point.u) && v.contains(point.v))
        }
        let reversed = try SurfaceAreaParameterChartEncloser(curve:image,on:target,tolerance:tolerance, using: &admitted)
        let smooth = try reversed.intervalJet(over:ScalarInterval(lower:0.9,upper:0.95),tolerance:tolerance, using: &admitted)
        #expect(smooth.v.derivativeU.contains(1.125))
    }

    @Test(.timeLimit(.minutes(1)))
    func affineImplicitChainRejectsToleranceGapsMixedCoordinatesAndInvalidAffineClosure() throws {
        var admitted = try execution()
        for (gap,mixed) in [(1e-9,false),(0.0,true)] {
            // The original public certificate validates these real native cells.
            // Its modeling-tolerance connectivity cannot prove an exact trim join.
            let (source,intersection) = try affineImplicitChainFixture(gap:gap,mixedCoordinate:mixed)
            let curve = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,tolerance:tolerance)
            do {
                _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(curve),on:.bSpline(source),tolerance:tolerance, using: &admitted)
                Issue.record("Inexact or mixed-coordinate joins cannot inherit affine chain authority.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .unsupportedCapability)
            }
        }
        let (source,forward) = try affineImplicitAreaFixture()
        let (_,reverse) = try affineImplicitAreaFixture(direction:.reversed)
        // Two regular affine supports intersect on a straight line. Reversing that
        // line cannot construct a proper closed regular chart: the owning lower
        // certificate must reject the opposing connection tangents.
        do {
            _ = try CertifiedImplicitIntersectionCurve(firstSurface:forward.firstSurface,secondSurface:forward.secondSurface,
                cells:[forward.cells[0],reverse.cells[0]],isClosed:true,tolerance:tolerance)
            Issue.record("Opposing affine line tangents cannot form a certified closed intersection.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .intersectionFailure)
            #expect(error.message.contains("tangent orientation"))
        }
        let (_,chain) = try affineImplicitChainFixture()
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:chain,role:.first,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:.bSpline(source),
                maximumBoundaryCurveCount:2,tolerance:tolerance, using: &admitted)
            Issue.record("Native cell admission must be bounded before source validation.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineImplicitChainCancellationRetainsWholeQueryFailure() async throws {
        let (source,intersection) = try affineImplicitChainFixture()
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:0.875,endFraction:0.125,tolerance:tolerance)
        let rectangleCurves = rectangle(2.75,4.25,7.09375,8.8125)
        let curves = [rectangleCurves[1],rectangleCurves[2],.certifiedImplicit(implicit),rectangleCurves[0]]
        let (id,model) = try fixture(.bSpline(source),outer:curves)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Implicit chain preparation cannot hide cancellation.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    @Test(.timeLimit(.minutes(1)))
    func centeredRationalChartsRetainOriginalThirdOrderAuthority() throws {
        let tolerance = tolerance
        let (first, intersection) = try rationalImplicitAreaFixture(direction: .forward)
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Centered chart proofs exhausted their shared caller work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        let interval = try ScalarInterval(lower: 0.5,
            upper: 0.5 + Double(sign: .plus, exponent: -8, significand: 1))
        for role in [SurfaceIntersectionSurfaceRole.first, .second] {
            let trim = try CertifiedImplicitSurfaceParameterCurve(intersection: intersection, role: role,
                startFraction: 1, endFraction: 0, tolerance: tolerance)
            let chart = try SurfaceAreaParameterChartEncloser(curve: .certifiedImplicit(trim),
                on: role == .first ? first : intersection.secondSurface, tolerance: tolerance, using: &admitted)
            let original = try chart.intervalJet(over: interval, tolerance: tolerance, using: &admitted)
            let before = remaining
            let centered = try chart.centeredIntervalJets(over: interval, tolerance: tolerance, using: &admitted)
            #expect(remaining < before - 1)
            #expect(centered.range.u.secondDerivativeUU.upper - centered.range.u.secondDerivativeUU.lower
                < original.u.secondDerivativeUU.upper - original.u.secondDerivativeUU.lower)
            #expect(centered.range.u.thirdDerivativeUUU.lower == original.u.thirdDerivativeUUU.lower)
            #expect(centered.range.u.thirdDerivativeUUU.upper == original.u.thirdDerivativeUUU.upper)
            for fraction in [interval.lower, interval.midpoint, interval.upper] {
                let t = 5.0 / 8 - fraction / 4, h = -0.25, d = 1 + t
                let expected: [[Double]] = role == .first
                    ? [[t*t, 2*t*h, 2*h*h, 0], [t, h, 0, 0]]
                    : [[2*t/d, 2*h/pow(d,2), -4*h*h/pow(d,3), 12*h*h*h/pow(d,4)], [0.5,0,0,0]]
                for (field, values) in zip([centered.range.u, centered.range.v], expected) {
                    for (bound, value) in zip([field.value, field.derivativeU,
                        field.secondDerivativeUU, field.thirdDerivativeUUU], values) {
                        #expect(bound.contains(value))
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func rationalImplicitSingletonFractionsRetainLowerPointWorkAndAuthority(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first, intersection) = try rationalImplicitAreaFixture(direction: backwards ? .reversed : .forward)
        var admitted = try execution()

        let lower = try ImplicitCurveIntervalJetEncloser(intersection: intersection, tolerance: tolerance, using: &admitted)
        func originalProof(over interval: ScalarInterval) throws -> CertifiedImplicitParameterIntervalJet {

            var state = try lower.prepareParameterEnclosure(of: intersection, cellIndex: 0,
                overClosedInterval: interval, tolerance: tolerance, using: &admitted)
            while true {

                switch try lower.advanceParameterEnclosure(state, tolerance: tolerance, using: &admitted) {
                case .contracted(let next): state = next
                case .enclosed(let jet): return jet
                case .subdivisionRequired:
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "The original singleton fixture lost its retained root authority.")
                }
            }
        }
        let tiny = Double(sign: .plus, exponent: -60, significand: 1)
        // Match the public integral's normalized trim direction. Each argument
        // also keeps one fallback: an inexact reversal or a nonidentity trim.
        let exact: (Double, Double, Double, Bool) = backwards ? (0, 1, 0.625, true) : (1, 0, 0.625, true)
        let fallback: (Double, Double, Double, Bool) = backwards ? (0.25, 0.75, 0.625, false) : (1, 0, tiny, false)
        let mappings: [(start: Double, end: Double, fraction: Double, singleton: Bool)] = [exact, fallback]
        for role in [SurfaceIntersectionSurfaceRole.first, .second] {
            for mapping in mappings {
                let trim = try CertifiedImplicitSurfaceParameterCurve(intersection: intersection, role: role,
                    startFraction: mapping.start, endFraction: mapping.end, tolerance: tolerance)
                let chart = try SurfaceAreaParameterChartEncloser(curve: .certifiedImplicit(trim),
                    on: role == .first ? first : intersection.secondSurface, tolerance: tolerance, using: &admitted)
                let slope = OutwardScalarInterval.exact(mapping.end) - .exact(mapping.start)
                let source = OutwardScalarInterval.exact(mapping.start)
                    + slope * OutwardScalarInterval(lower: mapping.fraction, upper: mapping.fraction)
                let original: ScalarInterval
                if mapping.singleton {
                    let value = mapping.start == 0 ? mapping.fraction : 1 - mapping.fraction
                    original = try ScalarInterval(lower: value, upper: value)
                } else {
                    original = try ScalarInterval(lower: max(0, source.lower), upper: min(1, source.upper))
                    #expect(original.width > 0)
                }
                let direct = try originalProof(over: original)
                let jet = try chart.intervalJet(over: ScalarInterval(lower: mapping.fraction, upper: mapping.fraction),
                    tolerance: tolerance, using: &admitted)
                try exactWorkBoundary(prepare: { execution in
                    try SurfaceAreaParameterChartEncloser(curve: .certifiedImplicit(trim),
                        on: role == .first ? first : intersection.secondSurface,
                        tolerance: tolerance, using: &execution)
                }, operation: { chart, execution in
                    _ = try chart.intervalJet(over: ScalarInterval(lower: mapping.fraction, upper: mapping.fraction),
                        tolerance: tolerance, using: &execution)
                })
                let base = role == .first ? 0 : 2
                for (field, coordinate) in zip([jet.u, jet.v], direct.coordinates[base..<(base + 2)]) {
                    #expect(field.value.lower == coordinate.value.lower && field.value.upper == coordinate.value.upper)
                    let third = OutwardScalarInterval(lower: coordinate.thirdDerivative.lower,
                        upper: coordinate.thirdDerivative.upper) * slope * slope * slope
                    #expect(field.thirdDerivativeUUU.lower == third.lower && field.thirdDerivativeUUU.upper == third.upper)
                }
                let h = (backwards ? -0.25 : 0.25) * (mapping.end - mapping.start)
                for fraction in [original.lower, original.midpoint, original.upper] {
                    let t = backwards ? 5.0 / 8 - fraction / 4 : 3.0 / 8 + fraction / 4
                    let d = 1 + t
                    let expected: [[Double]] = role == .first
                        ? [[t*t, 2*t*h, 2*h*h, 0], [t, h, 0, 0]]
                        : [[2*t/d, 2*h/pow(d,2), -4*h*h/pow(d,3), 12*h*h*h/pow(d,4)], [0.5,0,0,0]]
                    for (field, values) in zip([jet.u, jet.v], expected) {
                        for (bound, value) in zip([field.value, field.derivativeU,
                            field.secondDerivativeUU, field.thirdDerivativeUUU], values) {
                            #expect(bound.contains(value))
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func affineGreenCorrectionsDoNotTelescopeAcrossRoundingSizedJoins() throws {
        var admitted = try execution()
        let support = Surface3D.analytic(.plane(origin: Point3D(x: 0, y: 0, z: 0),
            normal: Vector3D(x: 0, y: 0, z: 1)))
        let gap = Double.ulpOfOne * 48
        let curves: [SurfaceParameterCurve] = [
            .affine(origin: Point2D(x: 0, y: 0), direction: Point2D(x: 0.125, y: 0.125), startParameter: 0, endParameter: 1),
            .affine(origin: Point2D(x: 0.125 + gap, y: 0.125),
                direction: Point2D(x: -0.125 - gap, y: -0.125), startParameter: 0, endParameter: 1)]
        let charts = try curves.map { try SurfaceAreaParameterChartEncloser(curve: $0, on: support, tolerance: tolerance, using: &admitted) }
        let endpoints = try charts.map { try (start: $0.endpointBounds(atEnd: false, tolerance: tolerance, using: &admitted),
            end: $0.endpointBounds(atEnd: true, tolerance: tolerance, using: &admitted)) }
        let difference = OutwardScalarInterval(lower: endpoints[1].start.u.lower, upper: endpoints[1].start.u.upper)
            - OutwardScalarInterval(lower: endpoints[0].end.u.lower, upper: endpoints[0].end.u.upper)
        #expect(difference.absoluteUpperBound <= Double.ulpOfOne * 64)
        let prepared = try PreparedSurfaceAreaIntegrand(surface: support, tolerance: tolerance, using: &admitted)
        let anchor = SurfaceParameter(u: 0, v: 0), reference = Point3D(x: 0, y: 0, z: 0)
        let first = try prepared.affineBoundaryCorrection(start: endpoints[0].start, end: endpoints[0].end,
            anchor: anchor, reference: reference, tolerance: tolerance, using: &admitted)
        let second = try prepared.affineBoundaryCorrection(start: endpoints[1].start, end: endpoints[1].end,
            anchor: anchor, reference: reference, tolerance: tolerance, using: &admitted)
        let retained = first[0] + second[0]
        // Each edge's original signed fan is zero. Its Green flux cancels
        // its own endpoint primitive; dropping the internal join changes it.
        #expect(retained.contains(gap * 0.125 * 0.5))
        #expect(retained.lower > 0)
        let telescoped = try prepared.affineBoundaryCorrection(start: endpoints[0].start, end: endpoints[1].end,
            anchor: anchor, reference: reference, tolerance: tolerance, using: &admitted)
        #expect(telescoped[0].contains(0))
        #expect(retained.lower > telescoped[0].upper)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func rationalSingleCellOnAffineSupportHasIndependentAreaAndCentroid(_ backwards: Bool) throws {
        let (source,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:backwards ? 0 : 1,endFraction:backwards ? 1 : 0,tolerance:tolerance)
        // Anchor is the original rational implicit endpoint. The area oracle
        // integrates the literal physical region x<=t^2/32, t in [3/8,5/8].
        let originals: [SurfaceParameterCurve] = [.certifiedImplicit(trim),
            .constantV(v:3.0/8,uStart:9.0/64,uEnd:0),.constantU(u:0,vStart:3.0/8,vEnd:5.0/8),
            .constantV(v:5.0/8,uStart:0,uEnd:25.0/64)]
        for mapped in [false,true] {
            let support: Surface3D
            let curves: [SurfaceParameterCurve]
            if mapped {
                let transform = try areaFixtureTransform()
                support = try transform.applying(to:source,tolerance:tolerance)
                curves = try rigidTrims(originals,source:source,target:support,transform:transform)
            } else { support = source; curves = originals }
            let (id,model) = try fixture(support,outer:curves)
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
            let area = 49.0/1_572_864
            let centroid = mapped ? Point3D(x:733.0/6_272,y:255_203.0/1_003_520,z:0.5)
                : Point3D(x:4_323.0/1_003_520,y:51.0/6_272,z:0)
            #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
            #expect((result.centroid-centroid).length <= tolerance.distance)
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                    integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:1))
                Issue.record("Rational endpoint work cannot bypass the original query budget.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded && error.residual == 2)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func rationalImplicitPartialChartsRetainRolesDirectionAndRigidFractions(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,
                        message:"Rational chart proofs exhausted their shared query work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let source = role == .first ? first : intersection.secondSurface
            let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,
                startFraction:0.75,endFraction:0.25,tolerance:tolerance)
            let transform = try areaFixtureTransform()
            let target = try transform.applying(to:source,tolerance:tolerance)
            let curve = SurfaceParameterCurve.rigidImage(try RigidImageSurfaceParameterCurve(
                source:SurfaceLiftCurve3D(surface:source,parameterCurve:.certifiedImplicit(trim)),
                targetSurface:target,transform:transform,startFraction:1,endFraction:0,tolerance:tolerance))
            let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:target,
                tolerance:tolerance, using: &admitted)
            let interval = try ScalarInterval(lower:0.25,upper:0.75)
            let jet = try chart.intervalJet(over:interval,tolerance:tolerance, using: &admitted)
            for fraction in [interval.lower,interval.midpoint,interval.upper] {
                let original = 0.25+0.5*fraction
                let t = backwards ? 5.0/8-original/4 : 3.0/8+original/4
                let h = backwards ? -0.125 : 0.125
                let d = 1+t
                let expected = role == .first ? [t*t,2*t*h,2*h*h,0]
                    : [2*t/d,2*h/pow(d,2),-4*h*h/pow(d,3),12*h*h*h/pow(d,4)]
                for (field,value) in zip([jet.u.value,jet.u.derivativeU,jet.u.secondDerivativeUU,jet.u.thirdDerivativeUUU],expected) {
                    #expect(field.contains(value))
                }
                #expect(jet.v.value.contains(role == .first ? t : 0.5))
                #expect(jet.v.derivativeU.contains(role == .first ? h : 0))
                #expect(jet.v.secondDerivativeUU.contains(0) && jet.v.thirdDerivativeUUU.contains(0))
            }
            for atEnd in [false,true] {
                let bounds = try chart.endpointBounds(atEnd:atEnd,tolerance:tolerance, using: &admitted)
                let original = atEnd ? 0.75 : 0.25
                let t = backwards ? 5.0/8-original/4 : 3.0/8+original/4
                #expect(bounds.u.contains(role == .first ? t*t : 2*t/(1+t)))
                #expect(bounds.v.contains(role == .first ? t : 0.5))
                #expect(bounds.u.width <= Double.ulpOfOne*64 && bounds.v.width <= Double.ulpOfOne*64)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func centeredRationalCurvedFanPairContainsIndependentPhysicalFields(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (_,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let surface = intersection.secondSurface
        let curve = try rationalImplicitCurvedBand(intersection,backwards:backwards)[2]
        var admitted = try execution()
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,
            tolerance:tolerance, using: &admitted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance, using: &admitted)
        let t = try ScalarInterval(lower:0.5,upper:0.5+1.0/64)
        let r = try ScalarInterval(lower:0.25,upper:0.75)
        // The actual preparation and field operation share one cumulative admission owner.
        let pair = try prepared.centeredFanBounds(curve:curve,parameterChart:chart,
            anchor:SurfaceParameter(u:10.0/13,v:1),reference:.origin,
            boundaryFraction:t,radialFraction:r,tolerance:tolerance, using: &admitted)
        try exactWorkBoundary(prepare: { execution in
            let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
                tolerance: tolerance, using: &execution)
            let integrand = try PreparedSurfaceAreaIntegrand(surface: surface,
                tolerance: tolerance, using: &execution)
            return (chart: chart, integrand: integrand)
        }, operation: { state, execution in
            _ = try state.integrand.centeredFanBounds(curve: curve, parameterChart: state.chart,
                anchor: SurfaceParameter(u:10.0/13,v:1), reference: .origin, boundaryFraction: t,
                radialFraction: r, tolerance: tolerance, using: &execution)
        })
        for atT in [t.lower,t.midpoint,t.upper] {
            for atR in [r.lower,r.midpoint,r.upper] {
                for (bound,value) in zip(pair.range,rationalCurvedFanPhysicalFields(atT,atR)) {
                    #expect(bound.value.contains(value))
                    #expect(bound.derivativeU != nil && bound.derivativeV != nil)
                    #expect(bound.secondUU != nil && bound.secondUV != nil && bound.secondVV != nil)
                }
            }
        }
        for (bound,value) in zip(pair.midpoint,rationalCurvedFanPhysicalFields(t.midpoint,r.midpoint)) {
            #expect(bound.value.contains(value))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func sourceCenteredOriginalFanPairTightensSameInputHessians(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (_,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let original = intersection.secondSurface
        let originalCurve = try rationalImplicitCurvedBand(intersection,backwards:backwards)[2]
        let t = try ScalarInterval(lower:0.5,upper:0.5+1.0/64)
        let r = try ScalarInterval(lower:0.25,upper:0.75)
        for mapped in [false,true] {
            let surface: Surface3D, curve: SurfaceParameterCurve
            if mapped {
                let transform = try areaFixtureTransform()
                surface = try transform.applying(to:original,tolerance:tolerance)
                curve = try #require(rigidTrims([originalCurve],source:original,target:surface,transform:transform).first)
            } else { surface = original; curve = originalCurve }
            var admitted = try execution()
            let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,
                tolerance:tolerance, using: &admitted)
            let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance, using: &admitted)
            let chartPair = try chart.centeredIntervalJets(over:t,tolerance:tolerance, using: &admitted)
            let anchor = SurfaceParameter(u:10.0/13,v:1)
            func pullback(_ chart: (u: SurfaceIntervalJet,v: SurfaceIntervalJet),_ radial: ScalarInterval)
                throws -> (box: SurfaceParameterBox,u: SurfaceIntervalJet,v: SurfaceIntervalJet,measure: SurfaceIntervalJet) {
                let radius = SurfaceIntervalJet.parameterV(radial)
                let du = chart.u - .constant(anchor.u), dv = chart.v - .constant(anchor.v)
                let u = SurfaceIntervalJet.constant(anchor.u)+du*radius
                let v = SurfaceIntervalJet.constant(anchor.v)+dv*radius
                return (SurfaceParameterBox(u:try ScalarInterval(lower:u.value.lower,upper:u.value.upper),
                    v:try ScalarInterval(lower:v.value.lower,upper:v.value.upper)),u,v,
                    radius*(du*chart.v.differentiatedUThroughSecondOrder()-dv*chart.u.differentiatedUThroughSecondOrder()))
            }
            let whole = try pullback(chartPair.range,r)
            let point = try pullback(chartPair.midpoint,ScalarInterval(lower:r.midpoint,upper:r.midpoint))
            guard case .bSpline(let spline) = surface else { Issue.record("The original rational fixture lost its native surface."); continue }
            // Prepare the original stored controls once. Both field compositions
            // below consume these exact same two evaluated source proofs.
            let patch = try RationalBezierSurfaceJetEncloser().prepare(RationalBezierSurfacePatch3D(
                controlPoints:spline.controlPoints,weights:spline.weights,uLower:0,uUpper:1,vLower:0,vUpper:1),tolerance:tolerance, using: &admitted)
            let owner = RationalBezierSurfaceJetEncloser()
            let rangeJet = try owner.enclosure(of:patch,u:whole.box.u,v:whole.box.v,tolerance:tolerance, using: &admitted)
            let midpointJet = try owner.enclosure(of:patch,u:point.box.u,v:point.box.v,tolerance:tolerance, using: &admitted)
            let tightened = try PreparedSurfaceAreaIntegrand.centeredSourceRange(rangeJet,midpoint:midpointJet,
                over:whole.box,midpointBox:point.box,tolerance:tolerance)
            for (before,after) in zip([rangeJet.x,rangeJet.y,rangeJet.z],[tightened.x,tightened.y,tightened.z]) {
                #expect(after.thirdDerivativeUUU.lower == before.thirdDerivativeUUU.lower && after.thirdDerivativeUUU.upper == before.thirdDerivativeUUU.upper)
                #expect(after.thirdDerivativeUUV.lower == before.thirdDerivativeUUV.lower && after.thirdDerivativeUUV.upper == before.thirdDerivativeUUV.upper)
                #expect(after.thirdDerivativeUVV.lower == before.thirdDerivativeUVV.lower && after.thirdDerivativeUVV.upper == before.thirdDerivativeUVV.upper)
                #expect(after.thirdDerivativeVVV.lower == before.thirdDerivativeVVV.lower && after.thirdDerivativeVVV.upper == before.thirdDerivativeVVV.upper)
            }
            let before = try prepared.fields(from:rangeJet,order:3,u:whole.u,v:whole.v,
                measure:whole.measure,reference:.origin,tolerance:tolerance, using: &admitted)
            let after = try prepared.fields(from:tightened,order:3,u:whole.u,v:whole.v,
                measure:whole.measure,reference:.origin,tolerance:tolerance, using: &admitted)
            for index in before.indices {
                let old = try [#require(before[index].secondUU),#require(before[index].secondUV),#require(before[index].secondVV)]
                let new = try [#require(after[index].secondUU),#require(after[index].secondUV),#require(after[index].secondVV)]
                #expect(zip(old,new).allSatisfy { old,new in new.width <= old.width })
                #expect(new.reduce(0) { $0+$1.width } < old.reduce(0) { $0+$1.width })
            }
            for tau in [t.lower,t.midpoint,t.upper] {
                for radial in [r.lower,r.midpoint,r.upper] {
                    var literal = rationalCurvedFanLiteralHessians(tau,radial)
                    if mapped {
                        for column in 0..<3 {
                            let area = literal[0][column], x = literal[1][column], y = literal[2][column], z = literal[3][column]
                            literal[1][column] = 0.125*area-y
                            literal[2][column] = 0.25*area+x
                            literal[3][column] = 0.5*area+z
                        }
                    }
                    var literalValues = rationalCurvedFanPhysicalFields(tau,radial)
                    if mapped { literalValues = [literalValues[0],0.125*literalValues[0]-literalValues[2],
                        0.25*literalValues[0]+literalValues[1],0.5*literalValues[0]+literalValues[3]] }
                    for bounds in [before,after] {
                        for index in bounds.indices {
                            #expect(bounds[index].value.contains(literalValues[index]))
                            #expect(try #require(bounds[index].secondUU).contains(literal[index][0]))
                            #expect(try #require(bounds[index].secondUV).contains(literal[index][1]))
                            #expect(try #require(bounds[index].secondVV).contains(literal[index][2]))
                        }
                    }
                }
            }
            let actual = try prepared.centeredFanBounds(curve:curve,parameterChart:chart,anchor:anchor,
                reference:.origin,boundaryFraction:t,radialFraction:r,tolerance:tolerance, using: &admitted)
            try exactWorkBoundary(prepare: { execution in
                let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
                    tolerance: tolerance, using: &execution)
                let integrand = try PreparedSurfaceAreaIntegrand(surface: surface,
                    tolerance: tolerance, using: &execution)
                return (chart: chart, integrand: integrand)
            }, operation: { state, execution in
                _ = try state.integrand.centeredFanBounds(curve: curve, parameterChart: state.chart,
                    anchor: anchor, reference: .origin, boundaryFraction: t,
                    radialFraction: r, tolerance: tolerance, using: &execution)
            })
            for index in after.indices {
                #expect(actual.range[index].value.lower == after[index].value.lower && actual.range[index].value.upper == after[index].value.upper)
                let secondUU = try #require(actual.range[index].secondUU)
                let expectedSecondUU = try #require(after[index].secondUU)
                #expect(secondUU.lower == expectedSecondUU.lower && secondUU.upper == expectedSecondUU.upper)
                let secondUV = try #require(actual.range[index].secondUV)
                let expectedSecondUV = try #require(after[index].secondUV)
                #expect(secondUV.lower == expectedSecondUV.lower && secondUV.upper == expectedSecondUV.upper)
                let secondVV = try #require(actual.range[index].secondVV)
                let expectedSecondVV = try #require(after[index].secondVV)
                #expect(secondVV.lower == expectedSecondVV.lower && secondVV.upper == expectedSecondVV.upper)
            }
            let originalMidpoint = try prepared.fields(from:midpointJet,order:3,u:point.u,v:point.v,
                measure:point.measure,reference:.origin,tolerance:tolerance, using: &admitted)
            for index in originalMidpoint.indices {
                #expect(actual.midpoint[index].value.lower == originalMidpoint[index].value.lower && actual.midpoint[index].value.upper == originalMidpoint[index].value.upper)
                let secondUU = try #require(actual.midpoint[index].secondUU)
                let expectedSecondUU = try #require(originalMidpoint[index].secondUU)
                #expect(secondUU.lower == expectedSecondUU.lower && secondUU.upper == expectedSecondUU.upper)
                let secondUV = try #require(actual.midpoint[index].secondUV)
                let expectedSecondUV = try #require(originalMidpoint[index].secondUV)
                #expect(secondUV.lower == expectedSecondUV.lower && secondUV.upper == expectedSecondUV.upper)
                let secondVV = try #require(actual.midpoint[index].secondVV)
                let expectedSecondVV = try #require(originalMidpoint[index].secondVV)
                #expect(secondVV.lower == expectedSecondVV.lower && secondVV.upper == expectedSecondVV.upper)
            }
        }
    }

    /// Closed-form derivatives of the independent physical fan density.
    /// Columns are TT, TR and RR; no native spline basis or interval jet arithmetic is used.
    private func rationalCurvedFanLiteralHessians(_ tau: Double,_ radius: Double) -> [[Double]] {
        let t = 3.0/8+tau/4, s = 2*t/(1+t), b = s-10.0/13
        let d = 0.5/pow(1+t,2), e = -0.25/pow(1+t,3), f = 0.1875/pow(1+t,4)
        let u = 10.0/13+radius*b, g = 2-u, h = u/g
        let hp = 2/(g*g), hpp = 4/pow(g,3), l = sqrt(1+16*h*h)
        let lp = 16*h*hp/l
        let lpp = 16*((hp*hp+h*hpp)/l-16*h*h*hp*hp/pow(l,3))
        let density = l/(2048*g*g)
        let densityP = (lp/(g*g)+2*l/pow(g,3))/2048
        let densityPP = (lpp/(g*g)+4*lp/pow(g,3)+6*l/pow(g,4))/2048
        let area = radius*d*density
        let at = radius*e*density+radius*radius*d*d*densityP
        let ar = d*density+radius*d*densityP*b
        let att = radius*f*density+3*radius*radius*d*e*densityP+pow(radius,3)*pow(d,3)*densityPP
        let atr = e*density+radius*e*densityP*b+2*radius*d*d*densityP+radius*radius*d*d*densityPP*b
        let arr = 2*d*densityP*b+radius*d*densityPP*b*b
        var result = [[att,atr,arr]]
        for (position,first,second) in [(h*h/32,h*hp/16,(hp*hp+h*hpp)/16),(h/64,hp/64,hpp/64)] {
            result.append([att*position+2*at*first*radius*d+area*(second*radius*radius*d*d+first*radius*e),
                atr*position+at*first*b+ar*first*radius*d+area*(second*radius*d*b+first*d),
                arr*position+2*ar*first*b+area*second*b*b])
        }
        let z = (1-radius)/64
        result.append([att*z,atr*z-at/64,arr*z-2*ar/64])
        return result
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceCenteredPairRejectsForeignOwnerAndContradictoryBoxes() throws {
        var admitted = try execution()
        let (_,intersection) = try rationalImplicitAreaFixture()
        let source = intersection.secondSurface
        let curve = try rationalImplicitCurvedBand(intersection,backwards:false)[1]
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:source,tolerance:tolerance, using: &admitted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface:source,tolerance:tolerance, using: &admitted)
        let t = try ScalarInterval(lower:0.25,upper:0.75), r = try ScalarInterval(lower:0.25,upper:0.75)
        let anchor = SurfaceParameter(u:10.0/13,v:1)
        let foreign = try PreparedSurfaceAreaIntegrand(surface:intersection.firstSurface,tolerance:tolerance, using: &admitted)
        #expect(throws:KernelError.self) {
            try foreign.pairedFanBounds(curve:curve,parameterChart:chart,anchor:anchor,reference:.origin,
                boundaryFraction:t,radialFraction:r,tolerance:tolerance, using: &admitted)
        }
        let otherTolerance = ModelingTolerance(distance:2*tolerance.distance,angle:tolerance.angle,relative:tolerance.relative)
        #expect(throws:KernelError.self) {
            try prepared.pairedFanBounds(curve:curve,parameterChart:chart,anchor:anchor,reference:.origin,
                boundaryFraction:t,radialFraction:r,tolerance:otherTolerance, using: &admitted)
        }
        let box = SurfaceParameterBox(u:t,v:r)
        guard case .bSpline(let spline) = source else { Issue.record("The source fixture lost its spline."); return }
        let owner = try PreparedBSplineSurfaceDifferentialEncloser(surface:spline,tolerance:tolerance, using: &admitted)
        let rangeJet = try owner.intervalJet(overClosedBox:box,tolerance:tolerance, using: &admitted)
        let outside = SurfaceParameterBox(u:try ScalarInterval(lower:0,upper:0),v:r)
        #expect(throws:KernelError.self) {
            try PreparedSurfaceAreaIntegrand.centeredSourceRange(rangeJet,midpoint:rangeJet,
                over:box,midpointBox:outside,tolerance:tolerance)
        }
        let nonfinite = SurfaceIntervalVectorJet.constant(Point3D(x:Double.infinity,y:0,z:0))
        #expect(throws:KernelError.self) {
            try PreparedSurfaceAreaIntegrand.centeredSourceRange(rangeJet,midpoint:nonfinite,
                over:box,midpointBox:box,tolerance:tolerance)
        }
        let contradiction = SurfaceIntervalVectorJet.constant(Point3D(x:100,y:100,z:100))
        #expect(throws:KernelError.self) {
            try PreparedSurfaceAreaIntegrand.centeredSourceRange(rangeJet,midpoint:contradiction,
                over:box,midpointBox:box,tolerance:tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceCenteredPairKeepsOriginalKnotSidesOnLegacyRoute() throws {
        var admitted = try execution()
        let source = foldedSupport(knot:0.37)
        let curve = SurfaceParameterCurve.constantV(v:0.03,uStart:0,uEnd:1)
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:source,tolerance:tolerance, using: &admitted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface:source,tolerance:tolerance, using: &admitted)
        let t = try ScalarInterval(lower:0,upper:1), r = try ScalarInterval(lower:0.25,upper:0.75)
        let anchor = SurfaceParameter(u:0,v:0)
        let originalRange = try prepared.bounds(curve:curve,anchor:anchor,reference:.origin,
            boundaryFraction:t,radialFraction:r,tolerance:tolerance,parameterChart:chart, using: &admitted)
        let originalMidpoint = try prepared.bounds(curve:curve,anchor:anchor,reference:.origin,
            boundaryFraction:ScalarInterval(lower:0.5,upper:0.5),
            radialFraction:ScalarInterval(lower:0.5,upper:0.5),tolerance:tolerance,parameterChart:chart, using: &admitted)
        let pair = try prepared.pairedFanBounds(curve:curve,parameterChart:chart,anchor:anchor,reference:.origin,
            boundaryFraction:t,radialFraction:r,tolerance:tolerance, using: &admitted)
        for (old,new) in zip(originalRange,pair.range) {
            #expect(new.value.lower == old.value.lower && new.value.upper == old.value.upper)
            #expect(new.secondUU == nil && new.secondUV == nil && new.secondVV == nil)
        }
        for (old,new) in zip(originalMidpoint,pair.midpoint) {
            #expect(new.value.lower == old.value.lower && new.value.upper == old.value.upper)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func retainedRationalFanChartProofOwnsOnlyItsOriginalBoundaryInterval(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let surface = intersection.secondSurface
        let curve = try rationalImplicitCurvedBand(intersection,backwards:backwards)[2]
        var admitted = try execution()
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,
            tolerance:tolerance, using: &admitted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance, using: &admitted)
        let t = try ScalarInterval(lower:0.5,upper:0.5+1.0/64)
        let proof = try prepared.prepareCenteredFanChartProof(curve:curve,parameterChart:chart,
            boundaryFraction:t,tolerance:tolerance, using: &admitted)
        let anchor = SurfaceParameter(u:10.0/13,v:1)
        for r in [try ScalarInterval(lower:0.25,upper:0.5),try ScalarInterval(lower:0.5,upper:0.75)] {
            let pair = try prepared.centeredFanBounds(using:proof,curve:curve,parameterChart:chart,
                anchor:anchor,reference:.origin,boundaryFraction:t,radialFraction:r,tolerance:tolerance, using: &admitted)
            try exactWorkBoundary(prepare: { execution in
                let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
                    tolerance: tolerance, using: &execution)
                let integrand = try PreparedSurfaceAreaIntegrand(surface: surface,
                    tolerance: tolerance, using: &execution)
                let proof = try integrand.prepareCenteredFanChartProof(curve: curve,
                    parameterChart: chart, boundaryFraction: t, tolerance: tolerance, using: &execution)
                return (chart: chart, integrand: integrand, proof: proof)
            }, operation: { state, execution in
                _ = try state.integrand.centeredFanBounds(using: state.proof, curve: curve,
                    parameterChart: state.chart, anchor: anchor, reference: .origin,
                    boundaryFraction: t, radialFraction: r, tolerance: tolerance, using: &execution)
            })
            for atT in [t.lower,t.midpoint,t.upper] {
                for atR in [r.lower,r.midpoint,r.upper] {
                    for (bound,value) in zip(pair.range,rationalCurvedFanPhysicalFields(atT,atR)) {
                        #expect(bound.value.contains(value))
                    }
                }
            }
            for (bound,value) in zip(pair.midpoint,rationalCurvedFanPhysicalFields(t.midpoint,r.midpoint)) {
                #expect(bound.value.contains(value))
            }
        }
        let r = try ScalarInterval(lower:0.25,upper:0.75)
        let narrowerT = try ScalarInterval(lower:0.5,upper:0.5+1.0/128)
        let differentTolerance = ModelingTolerance(distance:tolerance.distance*2,
            angle:tolerance.angle,relative:tolerance.relative)
        let foreign = try PreparedSurfaceAreaIntegrand(surface:first,tolerance:tolerance, using: &admitted)
        for mismatch in 0..<4 {
            do {
                _ = try (mismatch == 0 ? foreign : prepared).centeredFanBounds(using:proof,
                    curve:mismatch == 1 ? .constantV(v:0.5,uStart:0,uEnd:1) : curve,
                    parameterChart:chart,anchor:anchor,reference:.origin,
                    boundaryFraction:mismatch == 2 ? narrowerT : t,radialFraction:r,
                    tolerance:mismatch == 3 ? differentTolerance : tolerance, using: &admitted)
                Issue.record("Retained chart proof accepted a foreign original authority.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .invalidInput)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func rationalFanChildRestrictionRetainsOriginalMidpointWorkAndPhysicalFields(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (_,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let originalSurface = intersection.secondSurface
        let originalCurve = try rationalImplicitCurvedBand(intersection,backwards:backwards)[2]
        for mapped in [false,true] {
            let surface: Surface3D, curve: SurfaceParameterCurve
            if mapped {
                let transform = try areaFixtureTransform()
                surface = try transform.applying(to:originalSurface,tolerance:tolerance)
                curve = try rigidTrims([originalCurve],source:originalSurface,target:surface,transform:transform)[0]
            } else { surface = originalSurface; curve = originalCurve }
            var admitted = try execution()
            let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,
                tolerance:tolerance, using: &admitted)
            let prepared = try PreparedSurfaceAreaIntegrand(surface:surface,tolerance:tolerance, using: &admitted)
            let parentT = try ScalarInterval(lower:0.25,upper:0.75)
            let childT = try ScalarInterval(lower:0.5,upper:0.5+1.0/64)
            let parent = try prepared.prepareCenteredFanChartProof(curve:curve,parameterChart:chart,
                boundaryFraction:parentT,tolerance:tolerance, using: &admitted)
            let originalRange = try chart.intervalProofRetainingRoot(over:parentT,
                tolerance:tolerance, using: &admitted)
            let pointProof = try chart.intervalProofRetainingRoot(
                over:ScalarInterval(lower:childT.midpoint,upper:childT.midpoint),
                restricting:originalRange.root,tolerance:tolerance, using: &admitted)
            guard case .smooth(let pointU,let pointV) = pointProof.proof else {
                Issue.record("Original restricted singleton lost its smooth chart derivatives.")
                continue
            }
            let point = (u:pointU,v:pointV)
            let physicalT = 3.0/8+childT.midpoint/4, d = 1+physicalT
            for (field,value) in zip([point.u.value,point.u.derivativeU,point.u.secondDerivativeUU,
                                     point.u.thirdDerivativeUUU],
                                    [2*physicalT/d,0.5/pow(d,2),-0.25/pow(d,3),0.1875/pow(d,4)]) {
                #expect(field.contains(value))
            }
            let child = try prepared.prepareCenteredFanChartProof(restricting:parent,curve:curve,
                parameterChart:chart,boundaryFraction:childT,tolerance:tolerance, using: &admitted)
            let r = try ScalarInterval(lower:0.25,upper:0.75)
            let pair = try prepared.centeredFanBounds(using:child,curve:curve,parameterChart:chart,
                anchor:SurfaceParameter(u:10.0/13,v:1),reference:.origin,
                boundaryFraction:childT,radialFraction:r,tolerance:tolerance, using: &admitted)
            try exactWorkBoundary(prepare: { execution in
                let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: surface,
                    tolerance: tolerance, using: &execution)
                let integrand = try PreparedSurfaceAreaIntegrand(surface: surface,
                    tolerance: tolerance, using: &execution)
                let parent = try integrand.prepareCenteredFanChartProof(curve: curve,
                    parameterChart: chart, boundaryFraction: parentT, tolerance: tolerance, using: &execution)
                return (chart: chart, integrand: integrand, parent: parent)
            }, operation: { state, execution in
                let child = try state.integrand.prepareCenteredFanChartProof(restricting: state.parent,
                    curve: curve, parameterChart: state.chart, boundaryFraction: childT,
                    tolerance: tolerance, using: &execution)
                _ = try state.integrand.centeredFanBounds(using: child, curve: curve,
                    parameterChart: state.chart, anchor: SurfaceParameter(u:10.0/13,v:1),
                    reference: .origin, boundaryFraction: childT, radialFraction: r,
                    tolerance: tolerance, using: &execution)
            })
            func physical(_ fraction: Double, _ radial: Double) -> [Double] {
                let fields = rationalCurvedFanPhysicalFields(fraction,radial)
                return mapped ? [fields[0],0.125*fields[0]-fields[2],
                    0.25*fields[0]+fields[1],0.5*fields[0]+fields[3]] : fields
            }
            for atT in [childT.lower,childT.midpoint,childT.upper] {
                for atR in [r.lower,r.midpoint,r.upper] {
                    for (bound,value) in zip(pair.range,physical(atT,atR)) {
                        #expect(bound.value.contains(value))
                    }
                }
            }
            for (bound,value) in zip(pair.midpoint,physical(childT.midpoint,r.midpoint)) {
                #expect(bound.value.contains(value))
            }
            do {
                _ = try prepared.prepareCenteredFanChartProof(restricting:parent,curve:curve,
                    parameterChart:chart,boundaryFraction:ScalarInterval(lower:0,upper:0.5),
                    tolerance:tolerance, using: &admitted)
                Issue.record("Child chart restriction escaped its original parent T domain.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .invalidInput)
            }
            let foreign = try PreparedSurfaceAreaIntegrand(surface:intersection.firstSurface,tolerance:tolerance, using: &admitted)
            let differentTolerance = ModelingTolerance(distance:tolerance.distance*2,
                angle:tolerance.angle,relative:tolerance.relative)
            for mismatch in 0..<3 {
                do {
                    _ = try (mismatch == 0 ? foreign : prepared).prepareCenteredFanChartProof(restricting:parent,
                        curve:mismatch == 1 ? .constantV(v:0.5,uStart:0,uEnd:1) : curve,
                        parameterChart:chart,boundaryFraction:childT,
                        tolerance:mismatch == 2 ? differentTolerance : tolerance, using: &admitted)
                    Issue.record("Child chart restriction adopted a foreign parent authority.")
                } catch {
                    let error = try #require(retainedKernelFailure(error))
                    #expect(error.code == .invalidInput)
                }
            }
            do {
                var refusedAdmission = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
                    throw SurfaceAreaEnclosureRefinementRequired.implicitLocalization
                }))
                _ = try prepared.prepareCenteredFanChartProof(restricting:parent,curve:curve,
                    parameterChart:chart,boundaryFraction:childT,tolerance:tolerance, using: &refusedAdmission)
                Issue.record("Inconclusive original child localization minted a chart proof.")
            } catch { #expect(retainedRefinementFailure(error)) }
            do {
                _ = try chart.centeredIntervalJets(over:childT,
                    restricting:(u:SurfaceIntervalJet.constant(10),v:SurfaceIntervalJet.constant(10)),
                    tolerance:tolerance, using: &admitted)
                Issue.record("A contradictory parent range accepted its original child midpoint.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .classificationFailure)
            }
        }
    }

    private func rationalCurvedFanPhysicalFields(_ fraction: Double, _ radial: Double) -> [Double] {
        let originalT = 3.0/8+fraction/4
        let s = 2*originalT/(1+originalT)
        let ds = 0.5/pow(1+originalT,2)
        let u = 10.0/13+radial*(s-10.0/13)
        let h = u/(2-u)
        // Native density times the literal signed fan Jacobian R*s'/2.
        let area = radial*ds*sqrt(1+16*h*h)/(2048*pow(2-u,2))
        return [area,area*h*h/32,area*h/64,area*(1-radial)/64]
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func originalImplicitIsoImageRetainsWholeRootFractionsAndRigidIdentity(_ backwards: Bool) throws {
        let tolerance = tolerance
        var admitted = try execution()
        let (_,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let original = try rationalImplicitCurvedBand(intersection,backwards:backwards)[2]
        for mapped in [false,true] {
            let support: Surface3D
            let curve: SurfaceParameterCurve
            if mapped {
                let transform = try areaFixtureTransform()
                support = try transform.applying(to:intersection.secondSurface,tolerance:tolerance)
                curve = try rigidTrims([original],source:intersection.secondSurface,target:support,transform:transform)[0]
            } else { support = intersection.secondSurface; curve = original }
            let workState = Mutex(0)
            var work: Int {
                get { workState.withLock { $0 } }
                set { workState.withLock { $0 = newValue } }
            }
            var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
                workState.withLock { $0 += 1 }
            }))
            let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:support,
                tolerance:tolerance, using: &admitted)
            let before = work
            let image = try #require(try chart.certifiedIsoBoundaryImage(tolerance:tolerance, using: &admitted))
            #expect(work > before)
            #expect(chart.exactIsoBoundary == nil)
            #expect(image.axis == .v && image.fixedParameter == 0.5)
            #expect(image.start.u.contains(6.0/11) && image.end.u.contains(10.0/13))
            #expect(image.start.v.contains(0.5) && image.end.v.contains(0.5))
            try image.validate(for:chart,on:support,tolerance:tolerance, using: &admitted)
            let wrong = ModelingTolerance(distance:tolerance.distance,angle:tolerance.angle,relative:tolerance.relative*2)
            do {
                try image.validate(for:chart,on:support,tolerance:wrong, using: &admitted)
                Issue.record("An iso-image receipt changed its original preparation tolerance.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .invalidInput)
            }
        }
        // Partial native fractions and reversed traversal remain the original
        // implicit parameterization, rather than an endpoint-fitted line.
        let partial = SurfaceParameterCurve.certifiedImplicit(try CertifiedImplicitSurfaceParameterCurve(
            intersection:intersection,role:.second,startFraction:0.25,endFraction:0.75,tolerance:tolerance))
        let partialChart = try SurfaceAreaParameterChartEncloser(curve:partial,on:intersection.secondSurface,
            tolerance:tolerance, using: &admitted)
        let partialImage = try #require(try partialChart.certifiedIsoBoundaryImage(tolerance:tolerance, using: &admitted))
        let firstT = backwards ? 9.0/16 : 7.0/16
        let lastT = backwards ? 7.0/16 : 9.0/16
        #expect(partialImage.start.u.contains(2*firstT/(1+firstT)))
        #expect(partialImage.end.u.contains(2*lastT/(1+lastT)))
        let chart = try SurfaceAreaParameterChartEncloser(curve:original,on:intersection.secondSurface,
            tolerance:tolerance, using: &admitted)
        do {
            try partialImage.validate(for:chart,on:intersection.secondSurface,tolerance:tolerance, using: &admitted)
            Issue.record("An iso-image receipt adopted different original trim fractions.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func interiorCoefficientPerturbationCannotAuthorizeAnImplicitIsoImage() throws {
        var admitted = try execution()
        let (_,original) = try rationalImplicitAreaFixture()
        guard case .bSpline(let plane) = original.firstSurface,
              case .bSpline(let originalExtrusion) = original.secondSurface else {
            Issue.record("The independent implicit fixture lost its original spline supports.")
            return
        }
        var controls = originalExtrusion.controlPoints
        // Both layers receive the same interior perturbation: the exact V
        // translation survives, but its intersection with Z=0 is no longer V=.5.
        let perturbation = 1.0/134_217_728
        controls[0][1].z += perturbation
        controls[1][1].z += perturbation
        let extrusion = BSplineSurface3D(uDegree:originalExtrusion.uDegree,vDegree:originalExtrusion.vDegree,
            uKnots:originalExtrusion.uKnots,vKnots:originalExtrusion.vKnots,
            controlPoints:controls,weights:originalExtrusion.weights)
        #expect(try SurfaceAreaTranslationCertificate.direction(of:.bSpline(extrusion), remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &admitted) == .v)
        let old = original.cells[0]
        let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox:old.parameterBox,
            freeParameter:old.freeParameter,direction:old.direction,lowerAnchor:old.lowerAnchor,
            midpointAnchor:old.midpointAnchor,upperAnchor:old.upperAnchor,
            firstSurface:plane,secondSurface:extrusion,tolerance:tolerance)
        let intersection = try CertifiedImplicitIntersectionCurve(firstSurface:plane,secondSurface:extrusion,
            cells:[cell],isClosed:false,tolerance:tolerance)
        let curve = SurfaceParameterCurve.certifiedImplicit(try CertifiedImplicitSurfaceParameterCurve(
            intersection:intersection,role:.second,tolerance:tolerance))
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:.bSpline(extrusion),
            tolerance:tolerance, using: &admitted)
        #expect(try chart.certifiedIsoBoundaryImage(tolerance:tolerance, using: &admitted) == nil)
        // Independent homogeneous numerator at s=2/3: the middle weighted
        // basis contributes 1/2 of the perturbation; solving Z=0 changes V.
        let actualV = 0.5 - 32 * (perturbation * 0.5)
        #expect(actualV != 0.5)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func isoImageEndpointTrianglesRetainIndependentNonzeroAreaAndAllMoments(_ uAxis: Bool) throws {
        let tolerance = tolerance
        let intersection = try planarIsoImageIntersection(uAxis:uAxis)
        let curve = SurfaceParameterCurve.certifiedImplicit(try CertifiedImplicitSurfaceParameterCurve(
            intersection:intersection,role:.second,tolerance:tolerance))
        var admitted = try execution()
        let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:intersection.secondSurface,
            tolerance:tolerance, using: &admitted)
        let image = try #require(try chart.certifiedIsoBoundaryImage(tolerance:tolerance, using: &admitted))
        let prepared = try PreparedSurfaceAreaIntegrand(surface:intersection.secondSurface,tolerance:tolerance, using: &admitted)
        let epsilon = Double.ulpOfOne * 8
        let start = uAxis ? SurfaceParameter(u:0.5,v:0.25+epsilon) : SurfaceParameter(u:0.25+epsilon,v:0.5)
        let end = uAxis ? SurfaceParameter(u:0.5,v:0.75-2*epsilon) : SurfaceParameter(u:0.75-2*epsilon,v:0.5)
        let anchor = uAxis ? SurfaceParameter(u:1,v:0.75) : SurfaceParameter(u:0.75,v:1)
        let correction = try prepared.isoImageEndpointCorrection(image:image,parameterChart:chart,
            nominalStart:start,nominalEnd:end,anchor:anchor,reference:Point3D(x:0,y:-2,z:-1),
            tolerance:tolerance, using: &admitted)
        try exactWorkBoundary(prepare: { execution in
            let chart = try SurfaceAreaParameterChartEncloser(curve: curve, on: intersection.secondSurface,
                tolerance: tolerance, using: &execution)
            let candidate = try chart.certifiedIsoBoundaryImage(tolerance: tolerance, using: &execution)
            let image = try #require(candidate)
            let integrand = try PreparedSurfaceAreaIntegrand(surface: intersection.secondSurface,
                tolerance: tolerance, using: &execution)
            return (chart: chart, image: image, integrand: integrand)
        }, operation: { state, execution in
            _ = try state.integrand.isoImageEndpointCorrection(image: state.image, parameterChart: state.chart,
                nominalStart: start, nominalEnd: end, anchor: anchor,
                reference: Point3D(x:0,y:-2,z:-1), tolerance: tolerance, using: &execution)
        })
        // S=(u,0,2v-1), or its original native-axis transpose, J=2.
        // These are exact planar triangle integrals,
        // independently of the implicit chart and its interval point arithmetic.
        let area = 1.5*epsilon
        let momentX = (0.5*epsilon*(1.25+epsilon)+epsilon*(2.25-2*epsilon))/3
        let expected = [area,momentX,2*area,4*area/3].map { $0 * (uAxis ? -1 : 1) }
        for (bound,value) in zip(correction,expected) {
            #expect(bound.contains(value))
            #expect(uAxis ? bound.lower < 0 : bound.upper > 0)
            #expect(bound.upper > bound.lower && value != 0)
        }
        do {
            _ = try prepared.isoImageEndpointCorrection(image:image,parameterChart:chart,
                nominalStart:uAxis ? SurfaceParameter(u:0.5,v:0.25+1e-12) : SurfaceParameter(u:0.25+1e-12,v:0.5),
                nominalEnd:end,anchor:anchor,
                reference:.origin,tolerance:tolerance, using: &admitted)
            Issue.record("Endpoint correction accepted a gap beyond original parameter connection precision.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        do {
            _ = try prepared.isoImageEndpointCorrection(image:image,parameterChart:chart,
                nominalStart:start,nominalEnd:uAxis ? SurfaceParameter(u:0.5+1e-12,v:end.v)
                    : SurfaceParameter(u:end.u,v:0.5+1e-12),anchor:anchor,
                reference:.origin,tolerance:tolerance, using: &admitted)
            Issue.record("Endpoint correction accepted an axis contrary to the original coefficient identity.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        do {
            var refusedAdmission = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
                throw KernelError(phase:.topology,code:.resourceLimitExceeded,residual:2,tolerance:tolerance,
                    message:"Original iso-image preparation shares caller work.")
            }))
            _ = try chart.certifiedIsoBoundaryImage(tolerance:tolerance, using: &refusedAdmission)
            Issue.record("Original iso-image preparation bypassed caller work refusal.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded && error.residual == 2)
        }
        do {
            var refusedAdmission = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
                throw KernelError(phase:.topology,code:.cancelled,tolerance:tolerance,
                    message:"Original endpoint corrections retain caller cancellation.")
            }))
            _ = try prepared.isoImageEndpointCorrection(image:image,parameterChart:chart,
                nominalStart:start,nominalEnd:end,anchor:anchor,reference:.origin,tolerance:tolerance, using: &refusedAdmission)
            Issue.record("Original endpoint correction swallowed caller cancellation.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .cancelled)
        }
    }

    private func planarIsoImageIntersection(uAxis: Bool) throws -> CertifiedImplicitIntersectionCurve {
        let plane = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[-1.0,1.0].map { y in [Point3D(x:0,y:y,z:0),Point3D(x:1,y:y,z:0)] })
        let extrusion = BSplineSurface3D(uDegree:uAxis ? 1 : 2,vDegree:uAxis ? 2 : 1,
            uKnots:uAxis ? [0,0,1,1] : [0,0,0,1,1,1],vKnots:uAxis ? [0,0,0,1,1,1] : [0,0,1,1],
            controlPoints:uAxis ? [0.0,0.5,1.0].map { x in [-1.0,1.0].map { Point3D(x:x,y:0,z:$0) } }
                : [-1.0,1.0].map { z in [0.0,0.5,1.0].map { Point3D(x:$0,y:0,z:z) } })
        func anchor(_ u: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:u,v:0.5),
                second:uAxis ? SurfaceParameter(u:0.5,v:u) : SurfaceParameter(u:u,v:0.5))
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
            firstU:ScalarInterval(lower:0.25,upper:0.75),firstV:ScalarInterval(lower:0.25,upper:0.75),
            secondU:ScalarInterval(lower:uAxis ? 0.25 : 0,upper:uAxis ? 0.75 : 1),
            secondV:ScalarInterval(lower:uAxis ? 0 : 0.25,upper:uAxis ? 1 : 0.75)),
            freeParameter:.firstU,direction:.forward,lowerAnchor:anchor(0.25),midpointAnchor:anchor(0.5),
            upperAnchor:anchor(0.75),firstSurface:plane,secondSurface:extrusion,tolerance:tolerance)
        return try CertifiedImplicitIntersectionCurve(firstSurface:plane,secondSurface:extrusion,
            cells:[cell],isClosed:false,tolerance:tolerance)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func rationalSingleCellOnCurvedSupportHasIndependentAreaAndCentroid(_ backwards: Bool) throws {
        let (_,intersection) = try rationalImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let curves = try rationalImplicitCurvedBand(intersection,backwards:backwards)
        let (id,model) = try fixture(intersection.secondSurface,outer:curves)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expected = rationalImplicitCurvedBandOracle()
        #expect(abs(result.area-expected.area) <= tolerance.distance*tolerance.distance+tolerance.relative*expected.area)
        #expect((result.centroid-expected.centroid).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalImplicitCurvedSupportRigidImageRetainsIndependentCentroid() throws {
        let (_,intersection) = try rationalImplicitAreaFixture()
        let source = intersection.secondSurface
        let transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let curves = try rigidTrims(rationalImplicitCurvedBand(intersection,backwards:false),
            source:source,target:target,transform:transform)
        let (id,model) = try fixture(target,outer:curves)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expected = rationalImplicitCurvedBandOracle()
        // Literal rigid image of the independently integrated physical moments.
        let center = Point3D(x:0.11705791243614231,y:0.25823465931059556,z:0.5078125)
        #expect(abs(result.area-expected.area) <= tolerance.distance*tolerance.distance+tolerance.relative*expected.area)
        #expect((result.centroid-center).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalImplicitCurvedSupportRetainsQueryWorkAndEndpointAuthority() throws {
        var admitted = try execution()
        let (first,intersection) = try rationalImplicitAreaFixture()
        let source = intersection.secondSurface
        let curves = try rationalImplicitCurvedBand(intersection,backwards:false)
        let (id,model) = try fixture(source,outer:curves)
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:1))
            Issue.record("Curved rational endpoint localization bypassed the shared query budget.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded && error.residual == 2)
        }
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:curves[2],on:first,
                tolerance:tolerance, using: &admitted)
            Issue.record("A second-role rational chart adopted the first support.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        var disconnected = curves
        // This actual UV gap is below modeling distance but above the unchanged
        // 64-ulp connection contract; endpoint overlap cannot authorize it.
        disconnected[0] = .constantV(v:1,uStart:10.0/13,uEnd:6.0/11+1e-12)
        let (brokenID,brokenModel) = try fixture(source,outer:disconnected)
        do {
            _ = try brokenModel.faceAreaMeasurement(of:brokenID,tolerance:tolerance)
            Issue.record("Curved rational area accepted a real original trim endpoint gap.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .topologyFailure)
        }
    }

    private func rationalImplicitCurvedBand(_ intersection: CertifiedImplicitIntersectionCurve,
                                           backwards: Bool) throws -> [SurfaceParameterCurve] {
        let implicit = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.second,
            startFraction:backwards ? 1 : 0,endFraction:backwards ? 0 : 1,tolerance:tolerance)
        // Top-right anchor=(10/13,1) makes the implicit bottom-edge fan
        // determinant +s'(fraction)/2, rather than a structurally zero fan.
        return [.constantV(v:1,uStart:10.0/13,uEnd:6.0/11),
                .constantU(u:6.0/11,vStart:1,vEnd:0.5),.certifiedImplicit(implicit),
                .constantU(u:10.0/13,vStart:0.5,vEnd:1)]
    }

    private func rationalImplicitCurvedBandOracle() -> (area: Double, centroid: Point3D) {
        // S2=(t^2/32,t/64,(2r-1)/64), t=s/(2-s),
        // t in [3/8,5/8], r in [1/2,1]. Integrate physical arc length
        // independently of the native rational basis and the root localizer.
        func f0(_ t: Double) -> Double { t*sqrt(1+16*t*t)/2+asinh(4*t)/8 }
        func f1(_ t: Double) -> Double { pow(1+16*t*t,1.5)/48 }
        func f2(_ t: Double) -> Double {
            (4*t*sqrt(1+16*t*t)*(32*t*t+1)-asinh(4*t))/512
        }
        let lower = 3.0/8, upper = 5.0/8
        let i0 = f0(upper)-f0(lower), i1 = f1(upper)-f1(lower), i2 = f2(upper)-f2(lower)
        return (i0/4096,Point3D(x:i2/(32*i0),y:i1/(64*i0),z:1.0/128))
    }

    private func rationalImplicitAreaFixture(direction: CertifiedImplicitIntersectionDirection = .forward)
        throws -> (Surface3D,CertifiedImplicitIntersectionCurve) {
        let first = BSplineSurface3D(uDegree:1,vDegree:1,
            uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0/64].map { y in
                [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)] })
        // Exact rational source chart, W=(2-s)^2. Neither X nor Y is polynomial.
        let second = BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
            controlPoints:[-1.0/64,1.0/64].map { z in
                [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)] },
            weights:[[4,2,1],[4,2,1]])
        func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),
                second:SurfaceParameter(u:2*t/(1+t),v:0.5))
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
            firstU:ScalarInterval(lower:-1.0/8,upper:1.0/2),firstV:ScalarInterval(lower:3.0/8,upper:5.0/8),
            secondU:ScalarInterval(lower:1.0/2,upper:13.0/16),secondV:ScalarInterval(lower:0,upper:1)),
            freeParameter:.firstV,direction:direction,lowerAnchor:anchor(3.0/8),
            midpointAnchor:anchor(1.0/2),upperAnchor:anchor(5.0/8),
            firstSurface:first,secondSurface:second,tolerance:tolerance)
        return (.bSpline(first),try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
            cells:[cell],isClosed:false,tolerance:tolerance))
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearOriginalTwoCellRegionHasIndependentAreaAndCentroid(_ backwards: Bool) throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture(
            direction:backwards ? .reversed : .forward,split:true)
        #expect(intersection.cells.count == 2)
        let curves = try nonlinearImplicitRegion(intersection)
        let (id,model) = try fixture(source,outer:curves)
        let original = model
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area-13.0/196608) <= tolerance.distance*tolerance.distance
            + tolerance.relative*(13.0/196608))
        #expect((result.centroid-Point3D(x:363.0/66560,y:15.0/1664,z:0)).length <= tolerance.distance)
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearOriginalTwoCellPartialAndRigidRegionsKeepIndependentCentroids(_ backwards: Bool) throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture(
            direction:backwards ? .reversed : .forward,split:true)
        let curves = try nonlinearImplicitPartialRegion(intersection)
        let transform = try areaFixtureTransform()
        for mapped in [false,true] {
            let support = mapped ? try transform.applying(to:source,tolerance:tolerance) : source
            let boundary = mapped ? try rigidTrims(curves,source:source,target:support,transform:transform) : curves
            let (id,model) = try fixture(support,outer:boundary)
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
            let literal = mapped ? Point3D(x:733.0/6272,y:255203.0/1003520,z:0.5)
                : Point3D(x:4323.0/1003520,y:51.0/6272,z:0)
            #expect(abs(result.area-49.0/1572864) <= tolerance.distance*tolerance.distance
                + tolerance.relative*(49.0/1572864))
            #expect((result.centroid-literal).length <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearOriginalTwoCellChartsPreserveOneSidedJetsAndValueOnlyJoins(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first,intersection) = try nonlinearImplicitAreaFixture(
            direction:backwards ? .reversed : .forward,split:true)
        let workState = Mutex(0)
        var work: Int {
            get { workState.withLock { $0 } }
            set { workState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try workState.withLock { work in
                work += 1
                guard work <= FaceAreaIntegrationOptions().maximumCellCount else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,
                        message:"The original chain test exhausted shared caller work.")
                }
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let support = role == .first ? first : intersection.secondSurface
            let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,tolerance:tolerance)
            let chart = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:support,
                tolerance:tolerance, using: &admitted)
            #expect(chart.requiresCallerWork && chart.hasNativeJoins)
            for range in [try ScalarInterval(lower:0.125,upper:0.375),
                          try ScalarInterval(lower:0.625,upper:0.875)] {
                let jets = try chart.intervalJet(over:range,tolerance:tolerance, using: &admitted)
                for fraction in [range.lower,range.midpoint,range.upper] {
                    let t = backwards ? 0.75-0.5*fraction : 0.25+0.5*fraction
                    let h = backwards ? -0.5 : 0.5
                    #expect(jets.u.value.contains(role == .first ? t*t : t))
                    #expect(jets.v.value.contains(role == .first ? t : 0.5))
                    #expect(jets.u.derivativeU.contains(role == .first ? 2*t*h : h))
                    #expect(jets.v.derivativeU.contains(role == .first ? h : 0))
                    #expect(jets.u.secondDerivativeUU.contains(role == .first ? 2*h*h : 0))
                    #expect(jets.u.thirdDerivativeUUU.contains(0) && jets.v.thirdDerivativeUUU.contains(0))
                }
            }
            for range in [try ScalarInterval(lower:0.375,upper:0.625),
                          try ScalarInterval(lower:0.5,upper:0.5)] {
                let proof = try chart.intervalProof(over:range,tolerance:tolerance, using: &admitted)
                guard case .valueOnly(let u,let v,let du,let dv) = proof else {
                    Issue.record("Both closed owning cell sides cannot supply a smooth join jet.")
                    continue
                }
                for fraction in [range.lower,range.midpoint,range.upper] {
                    let t = backwards ? 0.75-0.5*fraction : 0.25+0.5*fraction
                    let h = backwards ? -0.5 : 0.5
                    #expect(u.contains(role == .first ? t*t : t) && v.contains(role == .first ? t : 0.5))
                    #expect(du.contains(role == .first ? 2*t*h : h) && dv.contains(role == .first ? h : 0))
                }
            }
            for endpoint in [false,true] {
                let bounds = try chart.endpointBounds(atEnd:endpoint,tolerance:tolerance, using: &admitted)
                #expect(bounds.u.width <= Double.ulpOfOne*64 && bounds.v.width <= Double.ulpOfOne*64)
            }
        }
        #expect(work > 4)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearOriginalTwoCellPreparationRefusesRealGapAndSharedResourceExhaustion() throws {
        var admitted = try execution()
        let (source,intersection) = try nonlinearImplicitAreaFixture(split:true)
        let (id,model) = try fixture(source,outer:nonlinearImplicitRegion(intersection))
        for options in [FaceAreaIntegrationOptions(maximumCellCount:1),
                        FaceAreaIntegrationOptions(maximumSubdivisionDepth:1)] {
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
                Issue.record("An original nonlinear chain reset the aggregate work or depth ceiling.")
            } catch {
                let error = try #require(retainedKernelFailure(error))
                #expect(error.code == .resourceLimitExceeded)
            }
        }
        let (brokenSource,broken) = try nonlinearImplicitAreaFixture(split:true,gap:Double(sign:.plus,exponent:-36,significand:1))
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:broken,role:.first,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:brokenSource,
                tolerance:tolerance, using: &admitted)
            Issue.record("An original nonlinear chain certified a real native free-coordinate gap.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .unsupportedCapability)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearOriginalTwoCellCancellationRemainsAnActualQueryFailure() async throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture(split:true)
        let (id,model) = try fixture(source,outer:nonlinearImplicitRegion(intersection))
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("An original nonlinear chain hid query cancellation.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearImplicitPartialEndpointAnchorHasIndependentAreaAndCentroid(_ backwards: Bool) throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let original = try nonlinearImplicitPartialRegion(intersection)
        for mapped in [false,true] {
            let support: Surface3D
            let curves: [SurfaceParameterCurve]
            if mapped {
                let transform = try areaFixtureTransform()
                support = try transform.applying(to:source,tolerance:tolerance)
                curves = try rigidTrims(original,source:source,target:support,transform:transform)
            } else { support = source; curves = original }
            let (id,model) = try fixture(support,outer:curves)
            let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
            let area = 49.0/1_572_864
            let centroid = mapped ? Point3D(x:733.0/6_272,y:255_203.0/1_003_520,z:0.5)
                : Point3D(x:4_323.0/1_003_520,y:51.0/6_272,z:0)
            #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
            #expect((result.centroid-centroid).length <= tolerance.distance)
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,
                    integrationOptions:FaceAreaIntegrationOptions(maximumCellCount:1))
                Issue.record("The partial endpoint proof must consume the query work after chart preparation.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded && error.residual == 2)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearImplicitClosedEndpointsRetainBothRolesAndRigidDirection(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first,intersection) = try nonlinearImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,
                        message:"Closed endpoint proofs exhausted their shared work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let source = role == .first ? first : intersection.secondSurface
            let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,
                startFraction:0.75,endFraction:0.25,tolerance:tolerance)
            for mapped in [false,true] {
                let support: Surface3D
                let curve: SurfaceParameterCurve
                if mapped {
                    let transform = try areaFixtureTransform()
                    support = try transform.applying(to:source,tolerance:tolerance)
                    curve = .rigidImage(try RigidImageSurfaceParameterCurve(
                        source:SurfaceLiftCurve3D(surface:source,parameterCurve:.certifiedImplicit(trim)),
                        targetSurface:support,transform:transform,startFraction:1,endFraction:0,tolerance:tolerance))
                } else { support = source; curve = .certifiedImplicit(trim) }
                let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:support,
                    tolerance:tolerance, using: &admitted)
                for atEnd in [false,true] {
                    let fraction = (atEnd != mapped) ? 0.25 : 0.75
                    let t = backwards ? 0.75-0.5*fraction : 0.25+0.5*fraction
                    let bounds = try chart.endpointBounds(atEnd:atEnd,tolerance:tolerance, using: &admitted)
                    #expect(bounds.u.contains(role == .first ? t*t : t))
                    #expect(bounds.v.contains(role == .first ? t : 0.5))
                    #expect(bounds.u.width <= Double.ulpOfOne*64 && bounds.v.width <= Double.ulpOfOne*64)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitWholeRigidIdentityChartRetainsClosedEndpointProofs() throws {
        let tolerance = tolerance
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,
                        message:"Whole rigid endpoint proofs exhausted their shared work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        for direction in [CertifiedImplicitIntersectionDirection.forward,.reversed] {
            let (first,intersection) = try nonlinearImplicitAreaFixture(direction:direction)
            for role in [SurfaceIntersectionSurfaceRole.first,.second] {
                let source = role == .first ? first : intersection.secondSurface
                let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,tolerance:tolerance)
                let transform = try areaFixtureTransform()
                let target = try transform.applying(to:source,tolerance:tolerance)
                let image = try RigidImageSurfaceParameterCurve(
                    source:SurfaceLiftCurve3D(surface:source,parameterCurve:.certifiedImplicit(trim)),
                    targetSurface:target,transform:transform,tolerance:tolerance)
                #expect(try image.affineParameterTransform(tolerance:tolerance) == .identity)
                let original = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:source,
                    tolerance:tolerance, using: &admitted)
                let mapped = try SurfaceAreaParameterChartEncloser(curve:.rigidImage(image),on:target,
                    tolerance:tolerance, using: &admitted)
                for atEnd in [false,true] {
                    let fraction = atEnd ? 1.0 : 0.0
                    let t = direction == .forward ? 0.25+0.5*fraction : 0.75-0.5*fraction
                    let bounds = try mapped.endpointBounds(atEnd:atEnd,tolerance:tolerance, using: &admitted)
                    #expect(bounds.u.contains(role == .first ? t*t : t))
                    #expect(bounds.v.contains(role == .first ? t : 0.5))
                    #expect(bounds.u.width <= Double.ulpOfOne*64 && bounds.v.width <= Double.ulpOfOne*64)
                    let range = try ScalarInterval(lower:fraction,upper:fraction)
                    let a = try original.intervalJet(over:range,tolerance:tolerance, using: &admitted)
                    let b = try mapped.intervalJet(over:range,tolerance:tolerance, using: &admitted)
                    for (left,right) in [(a.u,b.u),(a.v,b.v)] {
                        for (x,y) in zip([left.value,left.derivativeU,left.secondDerivativeUU,left.thirdDerivativeUUU],
                                         [right.value,right.derivativeU,right.secondDerivativeUU,right.thirdDerivativeUUU]) {
                            #expect(x.lower == y.lower && x.upper == y.upper)
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitConnectionRejectsARealSubToleranceGap() throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        var curves = try nonlinearImplicitPartialRegion(intersection)
        curves[1] = .constantV(v:3.0/8,uStart:9.0/64+1e-12,uEnd:0)
        let (id,model) = try fixture(source,outer:curves)
        do {
            _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
            Issue.record("Overlapping or nearby hints cannot close an original chart gap.")
        } catch let error as KernelError { #expect(error.code == .topologyFailure) }
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearImplicitRegionHasIndependentAreaAndAllCentroidComponents(_ reversed: Bool) throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        let curves = try nonlinearImplicitRegion(intersection)
        let (id,model) = try fixture(source,outer:curves,reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expectedArea = 13.0/196_608
        #expect(abs(result.area-expectedArea) <= tolerance.distance*tolerance.distance+tolerance.relative*expectedArea)
        #expect((result.centroid-Point3D(x:363.0/66_560,y:15.0/1_664,z:0)).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitRigidImageHasIndependentLiteralCentroid() throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        let transform = try areaFixtureTransform()
        let target = try transform.applying(to:source,tolerance:tolerance)
        let curves = try rigidTrims(nonlinearImplicitRegion(intersection),source:source,target:target,transform:transform)
        let (id,model) = try fixture(target,outer:curves)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let expectedArea = 13.0/196_608
        #expect(abs(result.area-expectedArea) <= tolerance.distance*tolerance.distance+tolerance.relative*expectedArea)
        #expect((result.centroid-Point3D(x:193.0/1_664,y:17_003.0/66_560,z:0.5)).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)), arguments:[false,true])
    func nonlinearImplicitJetsRetainPartialReverseRolesAndRigidFractions(_ backwards: Bool) throws {
        let tolerance = tolerance
        let (first,intersection) = try nonlinearImplicitAreaFixture(direction:backwards ? .reversed : .forward)
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,message:"The original chart test exhausted its shared query work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        for role in [SurfaceIntersectionSurfaceRole.first,.second] {
            let support = role == .first ? first : intersection.secondSurface
            let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:role,
                startFraction:0.75,endFraction:0.25,tolerance:tolerance)
            for mapped in [false,true] {
                let curve: SurfaceParameterCurve
                let target: Surface3D
                if mapped {
                    let transform = try areaFixtureTransform()
                    target = try transform.applying(to:support,tolerance:tolerance)
                    curve = .rigidImage(try RigidImageSurfaceParameterCurve(
                        source:SurfaceLiftCurve3D(surface:support,parameterCurve:.certifiedImplicit(trim)),
                        targetSurface:target,transform:transform,startFraction:0.8,endFraction:0.2,tolerance:tolerance))
                } else { target = support; curve = .certifiedImplicit(trim) }
                let chart = try SurfaceAreaParameterChartEncloser(curve:curve,on:target,tolerance:tolerance, using: &admitted)
                #expect(chart.requiresCallerWork && !chart.hasNativeJoins)
                for interval in [try ScalarInterval(lower:0.2,upper:0.6),try ScalarInterval(lower:0.4,upper:0.4)] {
                    let jet = try chart.intervalJet(over:interval,tolerance:tolerance, using: &admitted)
                    for fraction in [interval.lower,interval.midpoint,interval.upper] {
                        let original = mapped ? 0.35+0.3*fraction : 0.75-0.5*fraction
                        let t = backwards ? 0.75-0.5*original : 0.25+0.5*original
                        let slope = (mapped ? 0.15 : -0.25) * (backwards ? -1.0 : 1.0)
                        let u = role == .first ? t*t : t
                        let v = role == .first ? t : 0.5
                        #expect(jet.u.value.contains(u) && jet.v.value.contains(v))
                        #expect(jet.u.derivativeU.contains(role == .first ? 2*t*slope : slope))
                        #expect(jet.v.derivativeU.contains(role == .first ? slope : 0))
                        #expect(jet.u.secondDerivativeUU.contains(role == .first ? 2*slope*slope : 0))
                        #expect(jet.v.secondDerivativeUU.contains(0))
                        #expect(jet.u.thirdDerivativeUUU.contains(0) && jet.v.thirdDerivativeUUU.contains(0))
                    }
                    if interval.width == 0 {
                        #expect(jet.u.value.width <= tolerance.relative && jet.v.value.width <= tolerance.relative)
                        #expect(jet.u.derivativeU.width <= tolerance.relative && jet.v.derivativeU.width <= tolerance.relative)
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitChartRequiresWorkAndRejectsForeignAuthority() throws {
        let tolerance = tolerance
        var identityAdmission = try execution()
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,tolerance:tolerance)
        do {
            var refusedAdmission = try execution(OriginalQueryBudget(workLimit: 0))
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:source,tolerance:tolerance, using: &refusedAdmission)
            Issue.record("A nonlinear chart cannot silently create its own work allowance.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        let foreign = try areaFixtureTransform().applying(to:source,tolerance:tolerance)
        do {
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:foreign,tolerance:tolerance, using: &identityAdmission)
            Issue.record("A nonlinear original chart cannot adopt a foreign support.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
        let (_,chain) = try nonlinearImplicitAreaFixture(split:true)
        let joined = try CertifiedImplicitSurfaceParameterCurve(intersection:chain,role:.first,tolerance:tolerance)
        do {
            var refusedAdmission = try execution(OriginalQueryBudget(workLimit: 0))
            _ = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(joined),on:source,tolerance:tolerance, using: &refusedAdmission)
            Issue.record("A nonlinear multi-cell certificate cannot create a private work allowance.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        let remainingState = Mutex(FaceAreaIntegrationOptions().maximumCellCount)
        var remaining: Int {
            get { remainingState.withLock { $0 } }
            set { remainingState.withLock { $0 = newValue } }
        }
        @Sendable func consume() throws {
            try remainingState.withLock { remaining in
                guard remaining > 0 else {
                    throw KernelError(phase:.topology,code:.resourceLimitExceeded,tolerance:tolerance,message:"The chart test exhausted its original query work.")
                }
                remaining -= 1
            }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in try consume() }))
        let chart = try SurfaceAreaParameterChartEncloser(curve:.certifiedImplicit(trim),on:source,tolerance:tolerance, using: &admitted)
        _ = try chart.signedFluxBounds(over:ScalarInterval(lower:0,upper:1),tolerance:tolerance, using: &admitted)
        #expect(remaining < FaceAreaIntegrationOptions().maximumCellCount-1)
        do {
            var refusedAdmission = try execution(OriginalQueryBudget(workLimit: 0))
            _ = try chart.intervalJet(over:ScalarInterval(lower:0.5,upper:0.5),tolerance:tolerance, using: &refusedAdmission)
            Issue.record("A prepared chart still requires caller work for each interval.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
        let integrand = try PreparedSurfaceAreaIntegrand(surface:source,tolerance:tolerance, using: &admitted)
        remaining = 0
        do {
            _ = try integrand.boundaryBounds(curve:.certifiedImplicit(trim),anchor:SurfaceParameter(u:0,v:0.75),
                reference:.origin,boundaryFraction:ScalarInterval(lower:0,upper:1),tolerance:tolerance,
                parameterChart:chart, using: &admitted)
            Issue.record("Integral evaluation cannot reset the work used for chart preparation and effort.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitQuerySharesWorkAndSubdivisionLimits() throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        let (id,model) = try fixture(source,outer:nonlinearImplicitRegion(intersection))
        for options in [FaceAreaIntegrationOptions(maximumCellCount:1),FaceAreaIntegrationOptions(maximumCellCount:4),
                        FaceAreaIntegrationOptions(maximumSubdivisionDepth:1)] {
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
                Issue.record("Implicit preparation, effort and quadrature must use the original query work/depth limits.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonlinearImplicitCancellationRemainsAQueryFailure() async throws {
        let (source,intersection) = try nonlinearImplicitAreaFixture()
        let (id,model) = try fixture(source,outer:nonlinearImplicitRegion(intersection))
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Nonlinear chart preparation must preserve query cancellation.") }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    private func nonlinearImplicitRegion(_ intersection: CertifiedImplicitIntersectionCurve) throws -> [SurfaceParameterCurve] {
        let backwards = intersection.cells[0].direction == .reversed
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:backwards ? 0 : 1,endFraction:backwards ? 1 : 0,tolerance:tolerance)
        // Anchor=(0,3/4), so the implicit fan determinant is t^2/2-3t/4,
        // strictly negative for the complete original t in [1/4,3/4].
        return [.constantV(v:0.75,uStart:0,uEnd:0.5625),.certifiedImplicit(trim),
                .constantV(v:0.25,uStart:0.0625,uEnd:0),.constantU(u:0,vStart:0.25,vEnd:0.75)]
    }

    private func nonlinearImplicitPartialRegion(_ intersection: CertifiedImplicitIntersectionCurve) throws -> [SurfaceParameterCurve] {
        let backwards = intersection.cells[0].direction == .reversed
        let trim = try CertifiedImplicitSurfaceParameterCurve(intersection:intersection,role:.first,
            startFraction:backwards ? 0.25 : 0.75,endFraction:backwards ? 0.75 : 0.25,tolerance:tolerance)
        // Anchor=(25/64,5/8) is the certified partial implicit endpoint. The
        // signed fan determinant is (t-5/8)^2/4, positive off that endpoint.
        return [.certifiedImplicit(trim),.constantV(v:3.0/8,uStart:9.0/64,uEnd:0),
                .constantU(u:0,vStart:3.0/8,vEnd:5.0/8),.constantV(v:5.0/8,uStart:0,uEnd:25.0/64)]
    }

    private func nonlinearImplicitAreaFixture(direction: CertifiedImplicitIntersectionDirection = .forward,
                                              split: Bool = false, gap: Double = 0) throws -> (Surface3D,CertifiedImplicitIntersectionCurve) {
        // Original exact dyadic polynomial controls, independent of the localizer.
        // S1(u,v)=(u/32,v/64,0); S2(s,r)=(s^2/32,s/64,(2r-1)/64).
        let first = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-0.5,-0.5,1.5,1.5],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0/64].map { y in [Point3D(x:-1.0/64,y:y,z:0),Point3D(x:3.0/64,y:y,z:0)] })
        let second = BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
            controlPoints:[-1.0/64,1.0/64].map { z in
                [Point3D(x:0,y:0,z:z),Point3D(x:0,y:1.0/128,z:z),Point3D(x:1.0/32,y:1.0/64,z:z)] })
        func anchor(_ t: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:t*t,v:t),second:SurfaceParameter(u:t,v:0.5))
        }
        let ranges: [(Double,Double)] = split ? [(0.25,0.5),(0.5+gap,0.75)] : [(0.25,0.75)]
        let ordered = direction == .forward ? ranges : Array(ranges.reversed())
        var cells: [CertifiedImplicitIntersectionGraphCell] = []
        for (lower,upper) in ordered {
            cells.append(try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
                firstU:ScalarInterval(lower:-0.25,upper:0.875),firstV:ScalarInterval(lower:lower,upper:upper),
                secondU:ScalarInterval(lower:0.2,upper:0.8),secondV:ScalarInterval(lower:0,upper:1)),
                freeParameter:.firstV,direction:direction,lowerAnchor:anchor(lower),
                midpointAnchor:anchor((lower+upper)/2),upperAnchor:anchor(upper),
                firstSurface:first,secondSurface:second,tolerance:tolerance))
        }
        return (.bSpline(first),try CertifiedImplicitIntersectionCurve(firstSurface:first,secondSurface:second,
            cells:cells,isClosed:false,tolerance:tolerance))
    }

    private func affineImplicitChainFixture(direction: CertifiedImplicitIntersectionDirection = .forward,
                                             gap: Double = 0, mixedCoordinate: Bool = false)
        throws -> (BSplineSurface3D,CertifiedImplicitIntersectionCurve) {
        let (source,original) = try affineImplicitAreaFixture()
        let second = original.secondSurface
        let ranges = [(7.0,7.25),(7.25+gap,8.5),(8.5,9.0)]
        var cells: [CertifiedImplicitIntersectionGraphCell] = []
        for (index,range) in ranges.enumerated() {
            let mixed = mixedCoordinate && index == 1
            func anchor(_ v: Double) throws -> SurfaceIntersectionParameterPair {
                try SurfaceIntersectionParameterPair(first:SurfaceParameter(u:2.75,v:v),
                    second:SurfaceParameter(u:(v-5)/6,v:5.0/12))
            }
            let box = try SurfaceIntersectionParameterBox(firstU:ScalarInterval(lower:2.5,upper:3),
                firstV:ScalarInterval(lower:mixed ? 7 : range.0,upper:mixed ? 9 : range.1),
                secondU:ScalarInterval(lower:mixed ? (range.0-5)/6 : 0,upper:mixed ? (range.1-5)/6 : 1),
                secondV:ScalarInterval(lower:0,upper:1))
            cells.append(try CertifiedImplicitIntersectionGraphCell(parameterBox:box,
                freeParameter:mixed ? .secondU : .firstV,direction:direction,
                lowerAnchor:try anchor(range.0),midpointAnchor:try anchor((range.0+range.1)/2),upperAnchor:try anchor(range.1),
                firstSurface:.bSpline(source),secondSurface:second,tolerance:tolerance))
        }
        if direction == .reversed { cells.reverse() }
        return (source,try CertifiedImplicitIntersectionCurve(firstSurface:.bSpline(source),secondSurface:second,
            cells:cells,isClosed:false,tolerance:tolerance))
    }

    private func affineImplicitAreaFixture(direction: CertifiedImplicitIntersectionDirection = .forward)
        throws -> (BSplineSurface3D,CertifiedImplicitIntersectionCurve) {
        // Literal dyadic affine equations on native U=[2,5], V=[7,9].
        let first = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[2,2,5,5],vKnots:[7,7,9,9],
            controlPoints:[0.25,0.265625].map { y in [Point3D(x:0.125,y:y,z:0.5),
                Point3D(x:0.15625,y:y,z:0.5234375)] })
        let second = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.4765625,0.546875].map { z in [Point3D(x:0.1328125,y:0.234375,z:z),
                Point3D(x:0.1328125,y:0.28125,z:z)] })
        let cell = try CertifiedImplicitIntersectionGraphCell(parameterBox:SurfaceIntersectionParameterBox(
            firstU:ScalarInterval(lower:2.5,upper:3),firstV:ScalarInterval(lower:7,upper:9),
            secondU:ScalarInterval(lower:0,upper:1),secondV:ScalarInterval(lower:0,upper:1)),
            freeParameter:.firstV,direction:direction,
            lowerAnchor:SurfaceIntersectionParameterPair(first:SurfaceParameter(u:2.75,v:7),
                second:SurfaceParameter(u:1.0/3,v:5.0/12)),
            midpointAnchor:SurfaceIntersectionParameterPair(first:SurfaceParameter(u:2.75,v:8),
                second:SurfaceParameter(u:0.5,v:5.0/12)),
            upperAnchor:SurfaceIntersectionParameterPair(first:SurfaceParameter(u:2.75,v:9),
                second:SurfaceParameter(u:2.0/3,v:5.0/12)),
            firstSurface:first,secondSurface:second,tolerance:tolerance)
        return (first,try CertifiedImplicitIntersectionCurve(firstSurface:.bSpline(first),secondSurface:.bSpline(second),
            cells:[cell],isClosed:false,tolerance:tolerance))
    }

    private func flatAreaSupport() -> Surface3D {
        .bSpline(BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,Point3D(x:0.04,y:0,z:0)],
                           [Point3D(x:0,y:0.02,z:0),Point3D(x:0.04,y:0.02,z:0)]]))
    }

    private func areaFixtureTransform() throws -> RigidTransform3D {
        try RigidTransform3D(basisX:Vector3D(x:0,y:1,z:0),basisY:Vector3D(x:-1,y:0,z:0),basisZ:.unitZ,
            translation:Vector3D(x:0.125,y:0.25,z:0.5),tolerance:tolerance)
    }

    private func areaFixtureImage(of point: Point3D) -> Point3D {
        Point3D(x:0.125-point.y,y:0.25+point.x,z:0.5+point.z)
    }

    private func rigidTrims(_ curves: [SurfaceParameterCurve],source: Surface3D,target: Surface3D,
                            transform: RigidTransform3D) throws -> [SurfaceParameterCurve] {
        try curves.map { .rigidImage(try RigidImageSurfaceParameterCurve(
            source:SurfaceLiftCurve3D(surface:source,parameterCurve:$0),targetSurface:target,
            transform:transform,tolerance:tolerance)) }
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
