@testable import CADGeometry

@main struct PureSquareRootAdmissionAcceptance {
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { guard value else { throw Failure(line:line) } }
    static func ledger(work:Int=8_388_608,storage:Int=268_435_456) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:storage,valueDepth:32,coefficientDepth:32))
    }
    static func workflow<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws {
        let q=ExactRationalScalarDomain()
        let f=try ExactAlgebraicScalarDomain.base(field:q,maximumExtensionLevel:4,using:&a)
        let roots=try ExactRealRootDomain(field:f,using:&a),p=roots.polynomials
        let x=try p.variable(0,using:&a)
        let law=try p.subtracting(p.multiplying(x,x,using:&a),p.constant(f.integer(2,using:&a),using:&a),using:&a)
        let source=try roots.bind(law,using:&a)
        let all=try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let finite=try roots.domain(lower:.finite(f.integer(-2,using:&a)),upper:.finite(f.integer(2,using:&a)),includesLower:true,includesUpper:true,using:&a)
        let positive=try roots.domain(lower:.finite(f.integer(1,using:&a)),upper:.finite(f.integer(2,using:&a)),includesLower:false,includesUpper:false,using:&a)
        let both=try roots.isolate(source,in:all,limits:.init(maximumRoots:2),using:&a)
        let finiteBoth=try roots.isolate(source,in:finite,limits:.init(maximumRoots:2),using:&a)
        let one=try roots.isolate(source,in:positive,limits:.init(maximumRoots:1),using:&a)
        try require(both.roots.count==2 && finiteBoth.roots.count==2 && one.roots.count==1)
        try require(one.roots[0].ordinal==1 && both.roots.allSatisfy { $0.multiplicity==1 })
        for root in both.roots {
            let extended=try f.adjoin(root,using:&a),g=extended.domain,z=extended.generator
            let expected=root.ordinal==0 ? ExactSign.negative:.positive
            try require(g.sign(of:z,using:&a)==expected)
            for shift in [-2,-1,0,1,2] {
                let value=try g.adding(z,g.integer(shift,using:&a),using:&a)
                let sign=shift<=(-2) ? ExactSign.negative:shift>=2 ? .positive:expected
                try require(g.sign(of:value,using:&a)==sign)
            }
        }
        let square=try roots.bind(p.subtracting(p.multiplying(x,x,using:&a),p.constant(f.integer(4,using:&a),using:&a),using:&a),using:&a)
        let squareScope=try roots.domain(lower:.finite(f.integer(1,using:&a)),upper:.finite(f.integer(3,using:&a)),using:&a)
        let squareSet=try roots.isolate(square,in:squareScope,limits:.init(maximumRoots:1),using:&a)
        let squareExtension=try f.adjoin(squareSet.roots[0],using:&a),g=squareExtension.domain
        try require(g.sign(of:g.subtracting(squareExtension.generator,g.integer(2,using:&a),using:&a),using:&a) == .zero)
        let depth=try ExactScalarDepth(value:0,coefficient:0)
        let closed=try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(0,using:&a)),depth:depth,using:&a)
        let open=try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(f.integer(0,using:&a)),includesLower:false,depth:depth,using:&a)
        try require(!closed.isEmpty && open.isEmpty)
        let foreign=try ExactAlgebraicScalarDomain.base(field:q,maximumExtensionLevel:4,using:&a)
        do {
            _=try ExactParameterInterval.checked(field:f,lower:.finite(foreign.integer(0,using:&a)),upper:.finite(f.integer(1,using:&a)),depth:depth,using:&a)
            throw Failure(line:#line)
        } catch let failure as Failure { throw failure } catch {}
        let repeated=try roots.bind(p.multiplying(x,x,using:&a),using:&a)
        let repeatedSet=try roots.isolate(repeated,in:finite,limits:.init(maximumRoots:1),using:&a)
        try require(repeatedSet.roots.count==1 && repeatedSet.roots[0].multiplicity==2)
        let empty=try roots.bind(p.adding(p.multiplying(x,x,using:&a),p.constant(f.integer(1,using:&a),using:&a),using:&a),using:&a)
        try require(roots.isolate(empty,in:all,limits:.init(maximumRoots:0),using:&a).roots.isEmpty)
    }
    static func intervalSigns() throws {
        var a = try ledger()
        let q = ExactRationalScalarDomain()
        let ranges = [(-5, -2), (-3, 4), (0, 5), (0, 0), (-4, 0)]
        for (lo, hi) in ranges {
            for (left, right) in ranges {
                let first = try OriginalPhysicalAngleInterval(lower: q.integer(lo, using: &a), upper: q.integer(hi, using: &a))
                let second = try OriginalPhysicalAngleInterval(lower: q.integer(left, using: &a), upper: q.integer(right, using: &a))
                let product = try first.multiplying(second, q, &a)
                let corners = [lo * left, lo * right, hi * left, hi * right]
                try require(q.compare(product.lower, q.integer(corners.min()!, using: &a), using: &a) == .equal)
                try require(q.compare(product.upper, q.integer(corners.max()!, using: &a), using: &a) == .equal)
            }
        }
        print("PASS all exact interval sign pairs and zero boundaries against independent four-corner integer oracle")
    }
    static func physicalSigns() throws {
        var a=try ledger()
        let f=try OriginalPhysicalAngleScalarDomain(originalRadians:Double(bitPattern:0x3fddac670561bb50),using:&a)
        let value=try f.subtracting(f.cosine(using:&a),f.multiplying(f.integer(2,using:&a),f.sine(using:&a),using:&a),using:&a)
        try require(f.sign(of:value,using:&a) == .negative)
        try require(f.sign(of:f.negated(value,using:&a),using:&a) == .positive)
        try require(f.sign(of:f.subtracting(value,value,using:&a),using:&a) == .zero)
        print("PASS independent whole-angle rational oracle: exact near-zero physical coefficient remains negative; opposite and equality controls")
    }
    static func main() throws {
        try intervalSigns()
        try physicalSigns()
        var measured=try ledger();try workflow(using:&measured)
        let work=measured.work,storage=measured.storageBytes
        var exact=try ledger(work:work,storage:storage);try workflow(using:&exact)
        for axis in 0..<2 {
            var short=try ledger(work:work-(axis==0 ? 1:0),storage:storage-(axis==1 ? 1:0))
            do { try workflow(using:&short);throw Failure(line:#line) }
            catch let failure as Failure { throw failure } catch {}
        }
        var cancelled=try ledger();cancelled.cancel()
        do { try workflow(using:&cancelled);throw Failure(line:#line) }
        catch let failure as Failure { throw failure } catch {}
        print("PASS pure-square whole/finite/one-sided roots, original ordinals/multiplicities, positive/negative linear signs, generic repeated/empty controls, N/N-1 and cancellation")
    }
}
