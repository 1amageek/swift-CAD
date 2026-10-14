import CADCore
import CADGeometry

@main struct FiniteBoundedRed {
    struct Failure: Error {}
    static func require(_ value: Bool) throws { guard value else { throw Failure() } }
    static func main() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 3, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        let whole = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: sphere, second: cone, tolerance: .standard)
        let r = try BoundedSphereConeSSIAcceptance.owner(whole)
        var a = try BoundedSphereConeSSIAcceptance.ledger()
        let section = try r.section(halfAngle: r.source.original.field.integer(1, using: &a),
            limits: BoundedSphereConeSSIAcceptance.limits(), using: &a)
        var query = try BoundedSphereConeSSIAcceptance.ledger()
        let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &query), using: &query)
        let m = try section.member(branch: 1, coneCycle: zero, sphereCycle: zero,
            limits: BoundedSphereConeSSIAcceptance.limits(), using: &query)
        var proof = try BoundedSphereConeSSIAcceptance.ledger()
        let f = m.field
        try require(f.compare(m.slant, f.integer(3, using: &proof), using: &proof) == .greater)
        try require(f.compare(m.slant, f.integer(4, using: &proof), using: &proof) == .less)
        try require(f.sign(of: m.x, using: &proof) == .positive && f.sign(of: m.y, using: &proof) == .zero)
        let latitudeSine = try m.sphereLatitudeSine(limits: BoundedSphereConeSSIAcceptance.limits(), using: &proof)
        let bound = try f.dividing(f.integer(-61, using: &proof), f.integer(100, using: &proof), using: &proof)
        try require(f.compare(latitudeSine, bound, using: &proof) == .greater && f.sign(of: latitudeSine, using: &proof) == .negative)
        try require(f.compare(section.sine, f.integer(1, using: &proof), using: &proof) == .equal)
        try require(f.sign(of: section.cosine, using: &proof) == .zero)
        let b = try f.importing(r.source.original.labelPeriod, using: &proof)
        try require(f.compare(b, f.integer(6, using: &proof), using: &proof) == .greater)
        try require(f.compare(b, f.dividing(f.integer(63, using: &proof), f.integer(10, using: &proof), using: &proof), using: &proof) == .less)
        // sin(2/3) > 2/3 - (2/3)^3/6 = 50/81 > 61/100, and pi > 3.
        // Hence original sphere V is in (-7/10, 0), U=-B/4, cone U=B/4, V=slant.
        print("PASS exact source witness inside sphere[-2,-1]x[-1,0] and cone[1,2]x[3,4]")
        let sb = SurfaceParameterBox(u: try .init(lower: -2, upper: -1), v: try .init(lower: -1, upper: 0))
        let cb = SurfaceParameterBox(u: try .init(lower: 1, upper: 2), v: try .init(lower: 3, upper: 4))
        var direct = try BoundedSphereConeSSIAcceptance.ledger()
        do {
            _ = try OriginalBoundedSphereConeSurfaceRelation.resolve(source: r.source,
                firstBox: sb, secondBox: cb, maximumComponents: 1,
                limits: BoundedSphereConeSSIAcceptance.limits(), prepared: r, using: &direct)
            throw Failure()
        } catch let error as OriginalDomainIdentityFailure {
            guard case .incompleteCoverage = error else { throw error }
            print("STOP retained DI: OriginalDomainIdentityFailure.incompleteCoverage")
        }
        let counter = BoundedSphereConeSSIAcceptance.Counter()
        do {
            _ = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: sphere, over: sb, second: cone, over: cb,
                tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
                consumeWork: { try counter.consume() }, consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
            throw Failure()
        } catch let failure as Failure { throw failure }
        catch let error as KernelError {
            try require(error.code == .intersectionFailure)
            print("STOP finite nonempty original UV publication: KernelError.intersectionFailure")
        }
    }
}
