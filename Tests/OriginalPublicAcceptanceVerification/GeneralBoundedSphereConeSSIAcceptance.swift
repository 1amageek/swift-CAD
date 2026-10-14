import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct GeneralBoundedSphereConeSSIAcceptance {
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { guard value else { throw Failure(line:line) } }
    static func ledger() throws -> ExactScalarLedger {
        .init(limits:try .init(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32))
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:1),maximumTransportDepth:1,maximumCharts:2,maximumFamilies:2,maximumIdentityProofs:0)
    }
    static func success(selected:Int? = nil) throws {
        let angle=Double(bitPattern:0x3fddac670561bb50)
        let inputs:[(Point3D,Double,Point3D,Double)]=[
            (.origin,2,.init(x:3,y:0,z:-4),angle),
            (.init(x:1,y:-2,z:0.5),4,.init(x:7,y:-2,z:-7.5),angle),
            (.origin,2,.init(x:3,y:0,z:-4),0.5)]
        for (index,input) in inputs.enumerated() where selected == nil || selected == index {
            let (center,radius,apex,angle)=input
            let sphere=Surface3D.analytic(.sphere(center:center,radius:radius))
            let cone=Surface3D.analytic(.cone(apex:apex,axis:.unitZ,halfAngle:angle))
            for swapped in [false,true] {
                let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:swapped ? cone:sphere,
                    second:swapped ? sphere:cone,tolerance:.standard)
                guard let r=result.originalBoundedSphereConeRelation?.original else { throw Failure(line:#line) }
                try require(result.intersections.count==1 && !r.isEmpty && r.source.original.sphereIsFirst == !swapped)
                let source=r.source.original
                for endpoint in -1..<2 {
                    var a=try ledger()
                    let t=endpoint<0 ? try source.field.integer(1,using:&a):
                        (endpoint==0 ? source.lowerHalfAngle:source.upperHalfAngle)
                    let section=try r.section(halfAngle:t,limits:limits(),using:&a)
                    try require(section.isSharedEndpoint == (endpoint>=0))
                    let q=ExactRationalScalarDomain()
                    let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
                    for branch in 0..<2 {
                        var a=try ledger()
                        let m=try section.member(branch:branch,coneCycle:zero,sphereCycle:zero,limits:limits(),using:&a)
                        try verify(m,center:center,radius:radius)
                    }
                }
            }
        }
        print("PASS general bounded sphere-cone inputs, both orders, both roots, exact incident endpoints and all original UV")
    }
    static func verify(_ m:OriginalBoundedSphereConeSurfaceMember,center:Point3D,radius:Double) throws {
        let f=m.field
        do {
            var a=try ledger()
            let dx=try f.subtracting(m.x,f.binary64(exactly:center.x,using:&a),using:&a)
            let dy=try f.subtracting(m.y,f.binary64(exactly:center.y,using:&a),using:&a)
            let dz=try f.subtracting(m.z,f.binary64(exactly:center.z,using:&a),using:&a)
            let rr=try f.binary64(exactly:radius,using:&a)
            let metric=try f.adding(f.adding(f.multiplying(dx,dx,using:&a),f.multiplying(dy,dy,using:&a),using:&a),f.multiplying(dz,dz,using:&a),using:&a)
            try require(f.compare(metric,f.multiplying(rr,rr,using:&a),using:&a) == .equal)
        }
        do {
            var a=try ledger()
            let args=try m.sphereAzimuthArguments(limits:limits(),using:&a)
            let dx=try f.subtracting(m.x,f.binary64(exactly:center.x,using:&a),using:&a)
            let dy=try f.subtracting(m.y,f.binary64(exactly:center.y,using:&a),using:&a)
            try require(f.compare(args.sine,f.negated(dx,using:&a),using:&a) == .equal)
            try require(f.compare(args.cosine,dy,using:&a) == .equal)
        }
        do {
            var a=try ledger()
            let dz=try f.subtracting(m.z,f.binary64(exactly:center.z,using:&a),using:&a)
            let rr=try f.binary64(exactly:radius,using:&a)
            try require(f.compare(m.sphereLatitudeSine(limits:limits(),using:&a),f.dividing(dz,rr,using:&a),using:&a) == .equal)
        }
        do { var a=try ledger();_=try m.firstUV(limits:limits(),using:&a) }
        do { var a=try ledger();_=try m.secondUV(limits:limits(),using:&a) }
    }
    static func main() throws { try success() }

}
