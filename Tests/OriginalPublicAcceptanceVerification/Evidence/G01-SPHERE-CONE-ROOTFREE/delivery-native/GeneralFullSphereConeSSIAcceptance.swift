import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct GeneralFullSphereConeSSIAcceptance {
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { guard value else { throw Failure(line:line) } }
    static func ledger() throws -> ExactScalarLedger {
        .init(limits:try .init(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32))
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:1),maximumTransportDepth:1,maximumCharts:4,maximumFamilies:2,maximumIdentityProofs:0)
    }
    static func success(selected:Int? = nil) throws {
        let inputs:[(Point3D,Double,Point3D,Double)]=[
            (.origin,3,.init(x:1,y:0,z:-4),Double(bitPattern:0x3fddac670561bb50)),
            (.init(x:2,y:-1,z:0.75),1,.init(x:2.25,y:-0.875,z:1),0.25),
            (.init(x:0.5,y:0.25,z:1),2,.init(x:0.75,y:-0.25,z:4),0.125)]
        for (index,input) in inputs.enumerated() where selected == nil || selected == index {
            let (center,radius,apex,angle)=input
            let sphere=Surface3D.analytic(.sphere(center:center,radius:radius))
            let cone=Surface3D.analytic(.cone(apex:apex,axis:.unitZ,halfAngle:angle))
            for swapped in [false,true] {
                let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:swapped ? cone:sphere,
                    second:swapped ? sphere:cone,tolerance:.standard)
                guard let r=result.originalFullSphereConeRelation?.original else { throw Failure(line:#line) }
                try require(result.intersections.count==2 && !r.isEmpty && r.source.original.sphereIsFirst == !swapped)
                var a=try ledger();let f=r.source.original.field,q=ExactRationalScalarDomain()
                let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
                for chart in 0..<2 {
                    for t in [-1.0,0.0,0.375,1.0] {
                        var a=try ledger()
                        let section=try r.section(chart:chart,halfAngle:f.binary64(exactly:t,using:&a),limits:limits(),using:&a)
                        let ff=section.field
                        try require(ff.compare(section.minusSlant,section.plusSlant,using:&a) == .less)
                        for branch in 0..<2 {
                            var a=try ledger()
                            let m=try section.member(branch:branch,coneCycle:zero,sphereCycle:zero,limits:limits(),using:&a)
                            let dx=try ff.subtracting(m.x,ff.binary64(exactly:center.x,using:&a),using:&a)
                            let dy=try ff.subtracting(m.y,ff.binary64(exactly:center.y,using:&a),using:&a)
                            let dz=try ff.subtracting(m.z,ff.binary64(exactly:center.z,using:&a),using:&a)
                            let sum=try ff.adding(ff.adding(ff.multiplying(dx,dx,using:&a),ff.multiplying(dy,dy,using:&a),using:&a),ff.multiplying(dz,dz,using:&a),using:&a)
                            let rr=try ff.binary64(exactly:radius,using:&a)
                            try require(ff.compare(sum,ff.multiplying(rr,rr,using:&a),using:&a) == .equal)
                            try require(ff.compare(m.sphereLatitudeSine(limits:limits(),using:&a),ff.dividing(dz,rr,using:&a),using:&a) == .equal)
                            let args=try m.sphereAzimuthArguments(limits:limits(),using:&a)
                            try require(ff.compare(args.sine,ff.negated(dx,using:&a),using:&a) == .equal && ff.compare(args.cosine,dy,using:&a) == .equal)
                            _=try m.firstUV(limits:limits(),using:&a);_=try m.secondUV(limits:limits(),using:&a)
                        }
                    }
                }
            }
        }
        print("PASS original root-free sphere-cone family, both orders, both ordered branches and all chart incidents")
    }
    static func controls() throws {
        let sphere=Surface3D.analytic(.sphere(center:.init(x:2,y:-1,z:0.75),radius:1))
        let cone=Surface3D.analytic(.cone(apex:.init(x:2.25,y:-0.875,z:1),axis:.unitZ,halfAngle:0.25))
        typealias Counter=FullSphereConeSSIAcceptance.Counter
        func admitted(_ counter:Counter,sourceDepth:Int=1) throws -> SurfaceSurfaceIntersectionResult {
            try DefaultSurfaceSurfaceIntersector().intersectionResult(first:sphere,second:cone,tolerance:.standard,
                maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:sourceDepth,
                consumeWork:{try counter.consume()},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32)
        }
        let counter=Counter();let result=try admitted(counter)
        guard let relation=result.originalFullSphereConeRelation?.original else { throw Failure(line:#line) }
        let n=counter.totals
        try require(try admitted(Counter(work:n.work,bytes:n.bytes)).intersections.count==2)
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(work:n.work-1,bytes:n.bytes)) }
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(work:n.work,bytes:n.bytes-1)) }
        for at in [1,n.work/2,n.work] {
            try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(cancelAt:at)) }
        }
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(),sourceDepth:0) }
        var a=try ledger();let t=try relation.source.original.field.integer(0,using:&a)
        var cancelled=try ledger();cancelled.cancel()
        try FullSphereConeSSIAcceptance.rejects { _=try relation.section(chart:0,halfAngle:t,limits:limits(),using:&cancelled) }
        let noFull=Surface3D.analytic(.sphere(center:.origin,radius:0.5))
        let outside=Surface3D.analytic(.cone(apex:.init(x:1,y:0,z:0),axis:.unitZ,halfAngle:0.3))
        try FullSphereConeSSIAcceptance.rejects {
            _=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:noFull,second:outside,tolerance:.standard)
        }
        print("PASS new full input exact N/N-1 work/storage, source depth, entry/mid/final/query cancel and false full-topology refusal")
    }
    static func main() async throws {
#if hasFeature(Embedded)
        let group=getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "general-all"
#else
        let group=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"general-all"
#endif
        if group=="general-all" { try success();try controls();return }
        for index in 0..<3 where group=="general-"+String(index) { try success(selected:index);return }
        if group=="controls" { try controls();return }
        switch group {
        case "full-success":try FullSphereConeSSIAcceptance.success()
        case "full-endpoints":try FullSphereConeSSIAcceptance.endpoints()
        case "full-publication":try FullSphereConeSSIAcceptance.publication()
        case "full-prepared":try FullSphereConeSSIAcceptance.prepared()
        case "full-terminal":try await FullSphereConeSSIAcceptance.terminalCancel()
        case "bounded-success":try BoundedSphereConeSSIAcceptance.success()
        case "bounded-endpoints":try BoundedSphereConeSSIAcceptance.endpoints()
        case "bounded-publication":try BoundedSphereConeSSIAcceptance.publication()
        case "bounded-prepared":try BoundedSphereConeSSIAcceptance.prepared()
        case "bounded-terminal":try await BoundedSphereConeSSIAcceptance.terminalCancel()
        default:throw Failure(line:#line)
        }
    }

}
