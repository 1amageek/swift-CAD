import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing
import Synchronization

@Suite("Original nested offset area and XYZ centroid", .timeLimit(.minutes(1)))
struct NestedOffsetSurfaceAreaIntegrationTests {
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

    private let tolerance = ModelingTolerance(distance:1e-6,angle:1e-9,relative:1e-4)

    @Test(arguments:[false,true])
    func twoGenuineCurvedOffsetsPublishIndependentAreaAndAllCentroidCoordinates(reversed: Bool) throws {
        let distance = 0.0015, a = 0.02, b = 0.03, k = 10.0
        let surface = nested(graph(),distances:[0.001,0.0005])
        let (id,model) = fixture(surface,reversed:reversed)
        let measured = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let t = 2*k*a
        let length = (t*sqrt(1+t*t)+asinh(t))/(4*k)
        let area = b*(length-distance*atan(t))
        #expect(abs(measured.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        // Parallel regular offsets preserve the original normal, so their
        // physical distances add. This independent physical-X integral never
        // consumes the production Taylor coefficients or parameter derivatives.
        let samples = 1024
        var densitySum = 0.0, xSum = 0.0, zSum = 0.0
        for index in 0...samples {
            let x = a*Double(index)/Double(samples)
            let slope = 2*k*x, norm = sqrt(1+slope*slope)
            let curvature = 2*k/(norm*norm*norm)
            let density = (1-distance*curvature)*norm
            let weight = index == 0 || index == samples ? 1.0 : (index % 2 == 0 ? 2.0 : 4.0)
            densitySum += weight*density
            xSum += weight*(x-distance*slope/norm)*density
            zSum += weight*(k*x*x+distance/norm)*density
        }
        let center = Point3D(x:xSum/densitySum,y:0.015,z:zSum/densitySum)
        #expect(abs(measured.centroid.x-center.x) <= tolerance.distance)
        #expect(abs(measured.centroid.y-center.y) <= tolerance.distance)
        #expect(abs(measured.centroid.z-center.z) <= tolerance.distance)
        #expect(model.geometry.surfaces.values.first == surface)
    }

    @Test
    func nonpolynomialRationalSourceRetainsItsOriginalFourthAndFifthOrders() throws {
        let plane = Surface3D.bSpline(BSplineSurface3D(uDegree:2,vDegree:1,
            uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],controlPoints:[0.0,0.03].map { y in
                [0.0,0.01,0.02].map { Point3D(x:$0,y:y,z:0) }
            },weights:[[4,2,1],[4,2,1]]))
        let (id,model) = fixture(nested(plane,distances:[0.001,0.002]))
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        #expect(abs(result.area-0.0006) <= tolerance.distance*tolerance.distance+tolerance.relative*0.0006)
        #expect(abs(result.centroid.x-0.01) <= tolerance.distance)
        #expect(abs(result.centroid.y-0.015) <= tolerance.distance)
        #expect(abs(result.centroid.z-0.003) <= tolerance.distance)
    }

    @Test
    func preparationWorkInputControlAndSubdivisionLimitsRemainTypedFailures() throws {
        let (id,model) = fixture(nested(graph(),distances:[0.001,0.0005]))
        for options in [FaceAreaIntegrationOptions(maximumCellCount:1),
                        FaceAreaIntegrationOptions(maximumSubdivisionDepth:1),
                        FaceAreaIntegrationOptions(maximumControlPointCount:2)] {
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
                Issue.record("Original nested offsets must preserve the query resource owner.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
    }

    @Test
    func validHighDegreeSurfaceIsRefusedBeforeOriginalLowerAllocation() throws {
        let tolerance = tolerance
        let degree = 32
        let knots = Array(repeating:0.0,count:degree+1)+Array(repeating:1.0,count:degree+1)
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree:degree,vDegree:degree,
            uKnots:knots,vKnots:knots,controlPoints:(0...degree).map { row in
                (0...degree).map { column in Point3D(x:0.02*Double(column)/Double(degree),
                    y:0.03*Double(row)/Double(degree),z:0) }
            }))
        try surface.validate(tolerance:tolerance)
        let workState = Mutex(0)
        var work: Int {
            get { workState.withLock { $0 } }
            set { workState.withLock { $0 = newValue } }
        }
        do {
            var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
                try workState.withLock { work in
                    work += 1
                    if work > 1024 { throw KernelError(phase:.topology,code:.resourceLimitExceeded,
                        residual:Double(work),tolerance:tolerance,message:"Original work refused lower surface allocation.") }
                }
            }))
            _ = try SurfaceAreaNativeOffsetTaylorPartition(surface:nested(surface,distances:[0.001,0.0005]),
                tolerance:tolerance, using: &admitted)
            Issue.record("Valid large original lower allocation must be admitted first.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == 1025)
            #expect(work == 1025)
        }
    }

    @Test
    func cancelledPublicNestedOffsetQueryDoesNotPublishMeasurement() async throws {
        let (id,model) = fixture(nested(graph(),distances:[0.001,0.0005]))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        do { _ = try await task.value; Issue.record("Cancelled nested offset query must fail.") }
        catch is CancellationError { }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    private func graph() -> Surface3D {
        .bSpline(BSplineSurface3D(uDegree:2,vDegree:1,uKnots:[0,0,0,1,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,0.03].map { y in
                [Point3D(x:0,y:y,z:0),Point3D(x:0.01,y:y,z:0),Point3D(x:0.02,y:y,z:0.004)]
            }))
    }

    private func nested(_ source: Surface3D, distances: [Double]) -> Surface3D {
        distances.reduce(source) { .procedural(.offset(OffsetSurface3D(source:$0,distance:$1))) }
    }

    private func fixture(_ surface: Surface3D, reversed: Bool = false) -> (FaceID,BRepModel) {
        let surfaceID = SurfaceID(), faceID = FaceID(), loopID = LoopID()
        let forward: [SurfaceParameterCurve] = [
            .constantV(v:0,uStart:0,uEnd:1),.constantU(u:1,vStart:0,vEnd:1),
            .constantV(v:1,uStart:1,uEnd:0),.constantU(u:0,vStart:1,vEnd:0)]
        let reverse: [SurfaceParameterCurve] = [
            .constantU(u:0,vStart:0,vEnd:1),.constantV(v:1,uStart:0,uEnd:1),
            .constantU(u:1,vStart:1,vEnd:0),.constantV(v:0,uStart:1,uEnd:0)]
        let loop = Loop(id:loopID,role:.outer,coedges:(reversed ? reverse : forward).map {
            Coedge(edgeID:EdgeID(),surfaceParameterCurve:$0)
        })
        return (faceID,BRepModel(geometry:GeometryStore(surfaces:[surfaceID:surface]),
            faces:[faceID:Face(id:faceID,surfaceID:surfaceID,loops:[loopID],orientation:reversed ? .reversed : .forward)],
            loops:[loopID:loop]))
    }
}
