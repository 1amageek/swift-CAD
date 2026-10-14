import CADCore
import CADGeometry

enum GeneralBoundedSphereConeSSIControls {
    typealias Failure=GeneralBoundedSphereConeSSIAcceptance.Failure
    static func require(_ value:Bool,line:Int = #line) throws { try GeneralBoundedSphereConeSSIAcceptance.require(value,line:line) }
    static func ledger() throws -> ExactScalarLedger { try GeneralBoundedSphereConeSSIAcceptance.ledger() }
    static func limits() throws -> OriginalDomainIdentityLimits { try GeneralBoundedSphereConeSSIAcceptance.limits() }
    static func controls() throws {
        typealias Counter=FullSphereConeSSIAcceptance.Counter
        let sphere=Surface3D.analytic(.sphere(center:.origin,radius:2))
        let cone=Surface3D.analytic(.cone(apex:.init(x:3,y:0,z:-4),axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
        func admitted(_ counter:Counter,sourceDepth:Int=1) throws -> SurfaceSurfaceIntersectionResult {
            try DefaultSurfaceSurfaceIntersector().intersectionResult(first:sphere,second:cone,tolerance:.standard,
                maximumSpanCount:262_144,maximumSubdivisionDepth:8,remainingSourceDepth:sourceDepth,
                consumeWork:{try counter.consume()},consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32)
        }
        let counter=Counter();let result=try admitted(counter)
        guard let relation=result.originalBoundedSphereConeRelation?.original else { throw Failure(line:#line) }
        let n=counter.totals
        try require(try admitted(Counter(work:n.work,bytes:n.bytes)).intersections.count==1)
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(work:n.work-1,bytes:n.bytes)) }
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(work:n.work,bytes:n.bytes-1)) }
        for at in [1,n.work/2,n.work] {
            try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(cancelAt:at)) }
        }
        try FullSphereConeSSIAcceptance.rejects { _=try admitted(Counter(),sourceDepth:0) }
        var a=try ledger();let t=try relation.source.original.field.integer(1,using:&a)
        var cancelled=try ledger();cancelled.cancel()
        try FullSphereConeSSIAcceptance.rejects { _=try relation.section(halfAngle:t,limits:limits(),using:&cancelled) }
        let first=Surface3D.analytic(.sphere(center:.init(x:1,y:-2,z:0.5),radius:4))
        var second=Surface3D.analytic(.cone(apex:.init(x:7,y:-2,z:-7.5),axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
        let detached=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:first,second:second,tolerance:.standard)
        second = .analytic(.plane(origin:.origin,normal:.unitZ))
        try require(second != cone)
        guard let kept=detached.originalBoundedSphereConeRelation?.original else { throw Failure(line:#line) }
        var query=try ledger();_=try kept.section(halfAngle:kept.source.original.field.integer(1,using:&query),limits:limits(),using:&query)
        print("PASS general bounded public N/N-1 work/storage, depth, entry/mid/final/query cancel and detached/COW ownership")
    }
}
