import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing
import Synchronization

@Suite("Original C0 rolling-ball area and centroid", .timeLimit(.minutes(1)))
struct RollingBallSurfaceAreaIntegrationTests {
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

    private let tolerance = ModelingTolerance(distance:1e-6,angle:1e-9,relative:1e-6)

    @Test(arguments:[false,true])
    func originalC0QuarterCylinderPublishesAreaAndAllCentroidCoordinates(reversed: Bool) throws {
        let surface = support()
        let (id,model) = try fixture(surface,reversed:reversed)
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        check(result,length:0.02,centerX:0.01)
        #expect(model.geometry.surfaces.values.first == surface)
    }

    @Test
    func clippedCrossKnotRectangleAndHoleKeepOriginalPhysicalMeasure() throws {
        let u0 = 0.1, u1 = 0.9, h0 = 0.25, h1 = 0.75
        let (id,model) = try fixture(support(),outer:rectangle(u0,u1),holes:[rectangle(h0,h1)])
        let result = try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        let a = position(u0), b = position(u1), c = position(h0), d = position(h1)
        let length = (b-a)-(d-c)
        check(result,length:length,centerX:((b*b-a*a)-(d*d-c*c))/(2*length))
    }

    @Test
    func lowerPreparationAndNativeQuadratureShareQueryWorkAndDepthLimits() throws {
        let (id,model) = try fixture(support())
        for options in [FaceAreaIntegrationOptions(maximumCellCount:1),
                        FaceAreaIntegrationOptions(maximumSubdivisionDepth:1),
                        FaceAreaIntegrationOptions(maximumControlPointCount:2)] {
            do {
                _ = try model.faceAreaMeasurement(of:id,tolerance:tolerance,integrationOptions:options)
                Issue.record("Original rolling-ball queries must retain their existing resource limits.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
    }

    @Test
    func validHighDegreeOriginalMatrixWorkIsRefusedBeforeLowerPreparation() throws {
        let tolerance = tolerance
        let degree = 64, count = 256
        let interior = ((1...127).map { Double($0)/129 }+Array(repeating:0.5,count:degree)).sorted()
        let knots = Array(repeating:0.0,count:degree+1)+interior+Array(repeating:1.0,count:degree+1)
        func rail(_ y: Double,_ z: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:degree,knots:knots,
                controlPoints:(0..<count).map { Point3D(x:0.02*Double($0)/Double(count-1),y:y,z:z) }))
        }
        let blend = RollingBallBlendSurface3D(centerSpine:rail(0,0),firstContact:rail(0.01,0),
            secondContact:rail(0,0.01),radius:0.01,tolerance:tolerance)
        try blend.validate()
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
                    residual:Double(work),tolerance:tolerance,message:"Original query work exhausted before lower allocation.") }
                }
            }))
            _ = try SurfaceAreaNativeRollingBallPartition(blend:blend,tolerance:tolerance, using: &admitted)
            Issue.record("Valid high-degree matrix preparation must obey the original work owner before allocation.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == 1025)
            #expect(work == 1025)
        }
    }

    @Test
    func crossKnotFanDoesNotPublishDensityDerivativesAndForeignReceiptFails() throws {
        let tolerance = tolerance
        let workState = Mutex(0)
        var work: Int {
            get { workState.withLock { $0 } }
            set { workState.withLock { $0 = newValue } }
        }
        var admitted = try execution(OriginalQueryBudget(consumeWorkUnits: { _ in
            workState.withLock { $0 += 1 }
        }))
        let source = support()
        let prepared = try PreparedSurfaceAreaIntegrand(surface:source,tolerance:tolerance, using: &admitted)
        let before = work
        let fields = try prepared.bounds(curve:.constantU(u:1,vStart:0,vEnd:1),
            anchor:SurfaceParameter(u:0,v:0),reference:.origin,
            boundaryFraction:ScalarInterval(lower:0.2,upper:0.8),
            radialFraction:ScalarInterval(lower:0.2,upper:0.8),tolerance:tolerance, using: &admitted)
        #expect(work > before)
        #expect(fields.count == 4)
        #expect(fields.allSatisfy { $0.value.isFinite && $0.derivativeU == nil && $0.secondUU == nil })
        let unit = try ScalarInterval(lower:0,upper:1)
        let issuedDomains = try prepared.nativeRectangleDomains(over:SurfaceParameterBox(u:unit,v:unit),
            maximumCount:2,tolerance:tolerance, using: &admitted)
        let domains = try #require(issuedDomains)
        #expect(domains.map(\.rectangle.u.upper) == [0.37,1])
        let other = try PreparedSurfaceAreaIntegrand(surface:support(length:0.03),tolerance:tolerance, using: &admitted)
        do {
            _ = try other.rectangularTranslationBounds(rectangle:domains[0].rectangle,fraction:unit,
                reference:.origin,tolerance:tolerance,domain:domains[0], using: &admitted)
            Issue.record("A native rolling rectangle cannot authorize another original surface.")
        } catch {
            let error = try #require(retainedKernelFailure(error))
            #expect(error.code == .invalidInput)
        }
    }

    @Test
    func cancelledPublicMeasurementDoesNotPublishArea() async throws {
        let (id,model) = try fixture(support())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try model.faceAreaMeasurement(of:id,tolerance:tolerance)
        }
        do { _ = try await task.value; Issue.record("Cancelled area queries must fail.") }
        catch is CancellationError { }
        catch let error as KernelError { #expect(error.code == .cancelled) }
    }

    private func check(_ result: FaceAreaMeasurement, length: Double, centerX: Double) {
        let area = .pi*0.5*0.01*length
        #expect(abs(result.area-area) <= tolerance.distance*tolerance.distance+tolerance.relative*area)
        let centroid = Point3D(x:centerX,y:0.02/Double.pi,z:0.02/Double.pi)
        #expect(abs(result.centroid.x-centroid.x) <= tolerance.distance)
        #expect(abs(result.centroid.y-centroid.y) <= tolerance.distance)
        #expect(abs(result.centroid.z-centroid.z) <= tolerance.distance)
        #expect((result.centroid-centroid).length <= tolerance.distance)
    }

    private func position(_ u: Double) -> Double {
        u <= 0.37 ? 0.01*u/0.37 : 0.01+0.01*(u-0.37)/0.63
    }

    private func support(length: Double = 0.02) -> Surface3D {
        func rail(_ y: Double,_ z: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree:1,knots:[0,0,0.37,1,1],
                controlPoints:[0.0,length/2,length].map { Point3D(x:$0,y:y,z:z) }))
        }
        return .procedural(.rollingBall(RollingBallBlendSurface3D(centerSpine:rail(0,0),
            firstContact:rail(0.01,0),secondContact:rail(0,0.01),radius:0.01,tolerance:tolerance)))
    }

    private func rectangle(_ lower: Double = 0,_ upper: Double = 1) -> [SurfaceParameterCurve] {
        [.constantV(v:0,uStart:lower,uEnd:upper),.constantU(u:upper,vStart:0,vEnd:1),
         .constantV(v:1,uStart:upper,uEnd:lower),.constantU(u:lower,vStart:1,vEnd:0)]
    }

    private func fixture(_ surface: Surface3D, outer: [SurfaceParameterCurve]? = nil,
                         holes: [[SurfaceParameterCurve]] = [], reversed: Bool = false) throws -> (FaceID,BRepModel) {
        let surfaceID = SurfaceID(), faceID = FaceID()
        var loops: [LoopID:Loop] = [:], ids: [LoopID] = []
        for (index,original) in ([outer ?? rectangle()]+holes).enumerated() {
            let curves = reversed ? try original.reversed().map { try $0.reversed(tolerance:tolerance) } : original
            let id = LoopID(); ids.append(id)
            loops[id] = Loop(id:id,role:index == 0 ? .outer : .inner,
                coedges:curves.map { Coedge(edgeID:EdgeID(),surfaceParameterCurve:$0) })
        }
        return (faceID,BRepModel(geometry:GeometryStore(surfaces:[surfaceID:surface]),
            faces:[faceID:Face(id:faceID,surfaceID:surfaceID,loops:ids,
                orientation:reversed ? .reversed : .forward)],loops:loops))
    }
}
