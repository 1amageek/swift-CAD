#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry

@main struct RequestedOrderLifetimeProof {
    typealias Shared=RequestedOrderLiftProof
    nonisolated static func pcurve(_ ledger: Shared.Ledger) throws -> SurfaceAreaIntervalTaylorScalarJet {
        let source=SurfaceParameterCurve.bSpline(.init(degree:2,knots:[-2,-1,0,1,2,3],
            controlPoints:[0.25,0.5,0.75].map { .init(x:$0,y:0) },weights:[1,2,1]))
        return try CADGeometry.OriginalParameterCurveHigherTaylor.enclosure(source,over:.init(lower:0,upper:1),
            order:4,tolerance:.standard,maximumSpanCount:16,maximumSubdivisionDepth:8,remainingSourceDepth:16,
            consumeWork:ledger.work,consumeStorage:ledger.storage,maximumAlgebraicDepth:16).v
    }
    nonisolated static func detachedCurve() throws -> Curve3D {
        var a=try Shared.Admission(work:300_000_000,storage:1_073_741_824)
        var original=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in [0.0,0.5,1.0].map { u in Point3D(x:0,y:v,z:u) } })
        var uv=BSplineCurve2D(degree:2,knots:[0,0,0,1,1,1],controlPoints:[.init(x:0,y:0),.init(x:1,y:0),.init(x:0,y:0)])
        let lift=Curve3D.surfaceLift(.init(surface:.bSpline(original),parameterCurve:.bSpline(uv)))
        let result=try ParameterCurveGraphProof.traversal(ParameterCurveGraphProof.image(lift,gain:-1,offset:1),start:0.75,end:0.25,using:&a)
        original.controlPoints[0][0] = .init(x:9,y:9,z:9)
        uv.controlPoints[0] = .init(x:9,y:9)
        let direct=try lift.point(at:0.5,tolerance:.standard)
        try Shared.require(abs(direct.z-0.5)<1e-12 && abs(direct.y)<1e-12)
        return result
    }
    static func main() {
        do {
            let ledger=Shared.Ledger(),value=try pcurve(ledger),cost=ledger.usage
            let bound=try value.coefficient(0,0)
            try Shared.require(bound.lower==0 && bound.upper==0)
            _=try pcurve(Shared.Ledger(work:cost.work,bytes:cost.bytes))
            for limited in [Shared.Ledger(work:cost.work-1),Shared.Ledger(bytes:cost.bytes-1)] {
                do { _=try pcurve(limited);throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError { try Shared.require(error.code == .resourceLimitExceeded) }
            }
            for step in [1,max(1,cost.work/2),cost.work] {
                do { _=try pcurve(Shared.Ledger(cancelAt:step));throw ExactScalarFailure.invalidEvidence }
                catch let error as KernelError { try Shared.require(error.code == .cancelled) }
            }
            let detached=try detachedCurve()
            for t in [0.0,0.5,1.0] {
                let point=try detached.point(at:t,tolerance:.standard)
                try Shared.require(abs(point.y)<1e-12 && abs(point.z-(0.375+0.5*t-0.5*t*t))<1e-12)
            }
            for k in 0...4 { try Shared.contains(value.coefficient(k,0),0) }
            print("PASS requested-order pcurve exact work/bytes and terminal cancellation")
            print("PASS requested-order detached source/COW and coefficient lifetime")
        } catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL requested-order lifetime finding");exit(1)
        }
    }
}
