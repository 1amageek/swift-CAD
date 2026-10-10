#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
import Synchronization
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import CallerAdapters
#if !OLD_SOURCE_RED
@testable import RequestedOrderAdapters
#endif

@main struct RequestedOrderLiftProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    #if OLD_SOURCE_RED
    typealias SurfaceJets=CADGeometry.OriginalSurfaceHigherJetProvider
    #else
    typealias SurfaceJets=RequestedOrderAdapters.OriginalSurfaceHigherJetProvider
    #endif
    final class Ledger: Sendable {
        struct State: Sendable {
            var work=0
            var bytes=0
            let maximumWork: Int
            let maximumBytes: Int
            let cancelAt: Int?
        }
        let state: Mutex<State>
        init(work: Int=100_000_000,bytes: Int=400_000_000,cancelAt: Int?=nil) {
            state=Mutex(.init(maximumWork:work,maximumBytes:bytes,cancelAt:cancelAt))
        }
        func work() throws {
            try state.withLock { s in
                if s.work==s.maximumWork { throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:.standard,message:"Requested-order work cap") }
                s.work+=1
                if s.work==s.cancelAt { throw KernelError(phase:.geometry,code:.cancelled,tolerance:.standard,message:"Requested-order cancellation") }
            }
        }
        func storage(_ count: Int) throws {
            try state.withLock { s in
                let next=s.bytes.addingReportingOverflow(count)
                guard count>=0,!next.overflow,next.partialValue<=s.maximumBytes else {
                    throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:.standard,message:"Requested-order byte cap")
                }
                s.bytes=next.partialValue
            }
        }
        var usage: (work: Int,bytes: Int) { state.withLock { ($0.work,$0.bytes) } }
    }
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        guard value else { print("FAIL requested order line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    nonisolated static func contains(_ bounds: OutwardScalarInterval,_ value: Double) throws {
        try require(bounds.lower<=value && value<=bounds.upper)
    }
    nonisolated static func nativeHost(crease: Bool=false) -> Surface3D {
        let stations=[0.0,0.5,1.0]
        return .bSpline(.init(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in stations.map { u in Point3D(x:0,y:v,z:crease ? max(0,u-0.5):u) } }))
    }
    nonisolated static func host(_ index: Int,using a: inout Admission) throws -> Surface3D {
        index==0 ? nativeHost():try Legacy.host(x:0,y:0,coons:index==1,using:&a)
    }
    nonisolated static func nested(_ surface: Surface3D,using a: inout Admission) throws -> Curve3D {
        let lift=Curve3D.surfaceLift(.init(surface:surface,parameterCurve:Legacy.nativePcurve(mode:1)))
        return try ParameterCurveGraphProof.traversal(ParameterCurveGraphProof.image(lift,gain:-1,offset:1),start:0.75,end:0.25,using:&a)
    }
    nonisolated static func surface(_ source: Surface3D,_ box: SurfaceParameterBox,order: Int,ledger: Ledger,
        spans: Int=16,depth: Int=16,algebra: Int=16) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try SurfaceJets.intervalTaylorJet(of:source,over:box,tolerance:.standard,throughOrder:order,
            maximumSpanCount:spans,maximumSubdivisionDepth:8,remainingSourceDepth:depth,
            consumeWork:ledger.work,consumeStorage:ledger.storage,maximumAlgebraicDepth:algebra)
    }
    nonisolated static func pointRegression() throws {
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        for index in 0..<3 {
            let original=try nested(host(index,using:&a),using:&a)
            for t in [0.25,0.5,0.75] {
                let p=try original.point(at:t,tolerance:.standard)
                let expected=0.375+0.5*t-0.5*t*t
                try require(abs(p.x)<1e-12 && abs(p.y)<1e-12 && abs(p.z-expected)<1e-12)
            }
        }
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let family=try ParameterCurveGraphProof.family(lifted:true,traversed:true,field:f,using:&a)
        for t in [0.25,0.5,0.75] {
            let p=try family.source.original.original.point(u:t,v:0.5)
            try require(abs(p.x-5)<1e-12 && abs(p.y)<1e-12 && abs(p.z-(0.25+0.5*t))<1e-12)
        }
        print("PASS actual nested lifted-traversal point and rolling-ball caller")
    }
    nonisolated static func curveJets() throws {
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        for index in 0..<3 {
            let original=try nested(host(index,using:&a),using:&a)
            for order in 0...4 {
                let ledger=Ledger()
                let jet=try CADGeometry.OriginalCurveHigherJetProvider.intervalTaylorJet(of:original,over:.init(lower:0.5,upper:0.5),
                    tolerance:.standard,throughOrder:order,maximumSpanCount:16,maximumSubdivisionDepth:8,
                    remainingSourceDepth:16,consumeWork:ledger.work,consumeStorage:ledger.storage,maximumAlgebraicDepth:16)
                try require(jet.x.order==order && jet.y.order==order && jet.z.order==order)
                for k in 0...order {
                    try contains(jet.x.coefficient(k,0),0);try contains(jet.y.coefficient(k,0),0)
                    try contains(jet.z.coefficient(k,0),k==0 ? 0.5:k==2 ? -0.5:0)
                }
            }
        }
        print("PASS requested D0-D4 original lift composition and traversal scale")
    }
    nonisolated static func coordinateHulls() throws {
        for value in [0.0,1.0,Double.leastNonzeroMagnitude,2.0,-Double.leastNonzeroMagnitude] {
            let native=SurfaceParameterCurve.bSpline(.init(degree:2,knots:[-2,-1,0,1,2,3],
                controlPoints:[0.25,0.5,0.75].map { .init(x:$0,y:value) },weights:[1,2,1]))
            for curve in [native,.constantV(v:value,uStart:1,uEnd:0),
                .constantU(u:value,vStart:0,vEnd:1),
                .affine(origin:.init(x:0.25,y:value),direction:.init(x:0.5,y:0),startParameter:0,endParameter:1)] {
                for order in 0...4 {
                    let ledger=Ledger()
                    let jet=try CADGeometry.OriginalParameterCurveHigherTaylor.enclosure(curve,over:.init(lower:0,upper:1),
                        order:order,tolerance:.standard,maximumSpanCount:16,maximumSubdivisionDepth:8,remainingSourceDepth:16,
                        consumeWork:ledger.work,consumeStorage:ledger.storage,maximumAlgebraicDepth:16)
                    let constant: SurfaceAreaIntervalTaylorScalarJet
                    if case .constantU=curve { constant=jet.u } else { constant=jet.v }
                    let bound=try constant.coefficient(0,0)
                    try require(bound.lower==value && bound.upper==value)
                    if order>0 { for k in 1...order { try contains(constant.coefficient(k,0),0) } }
                }
            }
        }
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        for index in 0..<3 {
            let source=try host(index,using:&a)
            for value in [0.0,1.0] {
                let pcurve=SurfaceParameterCurve.constantV(v:value,uStart:0,uEnd:1)
                let lift=Curve3D.surfaceLift(.init(surface:source,parameterCurve:pcurve))
                let original=try ParameterCurveGraphProof.traversal(ParameterCurveGraphProof.image(lift,gain:-1,offset:1),start:0.75,end:0.25,using:&a)
                for t in [0.0,0.5,1.0] {
                    let p=try original.point(at:t,tolerance:.standard)
                    try require(abs(p.y-value)<1e-12 && abs(p.z-(0.25+0.5*t))<1e-12)
                }
            }
        }
        for value in [2.0,-Double.leastNonzeroMagnitude] {
            let lift=Curve3D.surfaceLift(.init(surface:nativeHost(),parameterCurve:.constantV(v:value,uStart:0,uEnd:1)))
            do {
                _=try CADGeometry.OriginalCurveHigherJetProvider.intervalTaylorJet(of:lift,over:.init(lower:0.5,upper:0.5),
                    tolerance:.standard,throughOrder:0,maximumSpanCount:16,maximumSubdivisionDepth:8,remainingSourceDepth:16,
                    consumeWork:Ledger().work,maximumAlgebraicDepth:16)
                throw ExactScalarFailure.invalidEvidence
            } catch GeometryError.invalidDistance(_) {}
            catch GeometryConversionError.invalidInput(_) {}
            catch let error as KernelError { try require(error.code == .invalidInput) }
        }
        print("PASS original weighted/nonclamped pcurve hull, exact boundaries and nonzero/outside coordinates")
    }
    nonisolated static func joinAndResources() throws {
        let box=try SurfaceParameterBox(u:.init(lower:0.25,upper:0.75),v:.init(lower:0.25,upper:0.75))
        let original=nativeHost(crease:true),ledger=Ledger()
        let value=try surface(original,box,order:0,ledger:ledger)
        try contains(value.z.coefficient(0,0),0);try contains(value.z.coefficient(0,0),0.25)
        do { _=try surface(original,box,order:1,ledger:Ledger());throw ExactScalarFailure.invalidEvidence }
        catch let e as KernelError { try require(e.code == .singularGeometry) }
        let cost=ledger.usage
        _=try surface(original,box,order:0,ledger:Ledger(work:cost.work,bytes:cost.bytes))
        for failed in [Ledger(work:cost.work-1),Ledger(bytes:cost.bytes-1)] {
            do { _=try surface(original,box,order:0,ledger:failed);throw ExactScalarFailure.invalidEvidence }
            catch let e as KernelError { try require(e.code == .resourceLimitExceeded) }
        }
        for step in [1,max(1,cost.work/2),cost.work] {
            do { _=try surface(original,box,order:0,ledger:Ledger(cancelAt:step));throw ExactScalarFailure.invalidEvidence }
            catch let e as KernelError { try require(e.code == .cancelled) }
        }
        for (order,spans,depth,algebra) in [(-1,16,16,16),(0,0,16,16),(0,16,-1,16),(0,16,16,33)] {
            do { _=try surface(original,box,order:order,ledger:Ledger(),spans:spans,depth:depth,algebra:algebra);throw ExactScalarFailure.invalidEvidence }
            catch let e as KernelError { try require(e.code == .invalidInput) }
        }
        print("PASS C0-not-C1 join, exact work/bytes, independent caps and cancellation")
    }
    nonisolated static func procedural() throws {
        func rail(_ x: Double) -> Curve3D { SpatialCurveGraphProof.native(x) }
        let ruled=Surface3D.procedural(.ruled(.init(startBoundary:rail(0),endBoundary:rail(2))))
        let box=try SurfaceParameterBox(u:.init(lower:0.5,upper:0.5),v:.init(lower:0.25,upper:0.25))
        for order in 0...4 {
            let jet=try surface(ruled,box,order:order,ledger:Ledger())
            try contains(jet.x.coefficient(0,0),0.5);try contains(jet.z.coefficient(0,0),0.5)
            if order>0 { try contains(jet.x.coefficient(0,1),2);try contains(jet.z.coefficient(1,0),1) }
        }
        var a=try Admission()
        let revolution=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let generator=try OriginalCurveRootSpan3D(source:rail(1),start:.authored(0),end:.authored(1),
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                usage:&usage,maximumSpanCount:8,remainingSourceDepth:12,maximumAlgebraicDepth:0)
            return try OriginalRevolutionSurface3D(generator:generator,axisOrigin:.init(x:0,y:0,z:0),axisDirection:.init(x:0,y:0,z:1),uDomain:.closed(0,1),tolerance:.standard,usage:&usage)
        }.value
        let revolutionBox=try SurfaceParameterBox(u:.init(lower:0,upper:0),v:.init(lower:0.5,upper:0.5))
        for order in 0...4 {
            let jet=try surface(.procedural(.originalRevolution(revolution)),revolutionBox,order:order,ledger:Ledger())
            try contains(jet.x.coefficient(0,0),1);try contains(jet.y.coefficient(0,0),0);try contains(jet.z.coefficient(0,0),0.5)
            if order>0 { try contains(jet.y.coefficient(1,0),CADGeometry.CanonicalSphereAngularPhase.scaleBounds.midpoint);try contains(jet.z.coefficient(0,1),1) }
        }
        let rolling=CADGeometry.RollingBallBlendSurface3D(centerSpine:rail(0),firstContact:SpatialCurveGraphProof.native(3,4),secondContact:SpatialCurveGraphProof.native(3,-4),radius:5,tolerance:.standard)
        let rollingBox=try SurfaceParameterBox(u:.init(lower:0.5,upper:0.5),v:.init(lower:0.5,upper:0.5))
        for order in 0...1 {
            let jet=try surface(.procedural(.rollingBall(rolling)),rollingBox,order:order,ledger:Ledger())
            try contains(jet.x.coefficient(0,0),5);try contains(jet.y.coefficient(0,0),0);try contains(jet.z.coefficient(0,0),0.5)
        }
        do { _=try surface(ruled,box,order:0,ledger:Ledger(),depth:0);throw ExactScalarFailure.invalidEvidence }
        catch let e as KernelError { try require(e.code == .resourceLimitExceeded) }
        print("PASS ruled, rolling-ball and revolution requested-order producers")
    }
    static func main() {
        do {
            try pointRegression()
            #if !OLD_SOURCE_RED
            try curveJets();try coordinateHulls();try joinAndResources();try procedural()
            #endif
        } catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL requested-order original lift caller");exit(1)
        }
    }
}
