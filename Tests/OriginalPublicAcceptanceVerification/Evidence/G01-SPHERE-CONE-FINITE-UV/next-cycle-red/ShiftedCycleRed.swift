import CADCore
import CADGeometry

@main struct ShiftedCycleRed {
    static func main() throws {
        typealias F = GeneralBoundedFiniteSphereConeSSIAcceptance
        try F.interiorOracle()
        let pair=F.input(),sphereBox=try F.boxes().sphere,B=2*Double.pi
        let coneBox=SurfaceParameterBox(u:try .init(lower:B+1,upper:B+2),v:try .init(lower:3,upper:4))
        let whole=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:pair.sphere,second:pair.cone,tolerance:.standard)
        guard let r=whole.originalBoundedSphereConeRelation?.original else { throw F.Failure(line:#line) }
        var a=try F.ledger();let base=r.source.original.field,q=ExactRationalScalarDomain()
        let zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let one=try OriginalParameterCycle(exact:q.integer(1,using:&a),using:&a)
        let section=try r.section(halfAngle:base.integer(1,using:&a),limits:F.limits(),using:&a)
        let m=try section.member(branch:1,coneCycle:one,sphereCycle:zero,limits:F.limits(),using:&a),f=m.field
        let period=try f.importing(r.source.original.labelPeriod,using:&a)
        try F.require(f.compare(m.coneLabelOffset,period,using:&a) == .equal)
        try F.require(f.sign(of:m.sphereLabelOffset,using:&a) == .zero)
        try F.require(f.compare(m.slant,f.integer(3,using:&a),using:&a) == .greater)
        try F.require(f.compare(m.slant,f.integer(4,using:&a),using:&a) == .less)
        try F.require(f.sign(of:m.x,using:&a) == .positive && f.sign(of:m.y,using:&a) == .zero)
        let actualU=try f.adding(m.coneLabelOffset,f.dividing(period,f.integer(4,using:&a),using:&a),using:&a)
        try F.require(f.compare(actualU,f.binary64(exactly:coneBox.u.lower,using:&a),using:&a) == .greater)
        try F.require(f.compare(actualU,f.binary64(exactly:coneBox.u.upper,using:&a),using:&a) == .less)
        for swapped in [false,true] {
            let counter=F.Counter()
            do {
                _=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:swapped ? pair.cone:pair.sphere,
                    over:swapped ? coneBox:sphereBox,second:swapped ? pair.sphere:pair.cone,
                    over:swapped ? sphereBox:coneBox,tolerance:.standard,maximumSpanCount:262_144,
                    maximumSubdivisionDepth:8,remainingSourceDepth:1,consumeWork:{try counter.consume()},
                    consumeStorage:{try counter.retain($0)},maximumAlgebraicDepth:32)
                throw F.Failure(line:#line)
            } catch let error as KernelError {
                try F.require(error.code == .unsupportedCapability)
            }
        }
        print("PASS constructive shifted-cone-cycle witness; both public orders explicitly stop at unsupported principal scope")
    }
}
