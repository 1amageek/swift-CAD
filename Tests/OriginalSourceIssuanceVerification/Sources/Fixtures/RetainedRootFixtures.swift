import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct RetainedRootPreparation: RationalAlgebraAdmitting {
        var work = 0, storage = 0
        mutating func consumeExactWork(_ count:Int) throws {
            guard count >= 0,count <= 50_000_000-work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count:Int) throws {
            guard count >= 0,count <= 50_000_000-storage else { throw ExactScalarFailure.resourceLimit(.storage) }
            storage += count
        }
        mutating func visitExactCell(depth:Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth:Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    static func selectedRoot(_ constant:Double,dependent:Bool = false) throws -> ExactAlgebraicRealRoot {
        var u = RetainedRootPreparation()
        let t2 = try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&u)
        var polynomial = try t2.subtracting(.constant(.originalDouble(constant,usage:&u),usage:&u),usage:&u)
        if dependent {
            polynomial = try polynomial.multiplied(by:t2.subtracting(.constant(.originalDouble(3,usage:&u),usage:&u),usage:&u),usage:&u)
        }
        let upper = try ExactRationalCoefficient.originalDouble(dependent ? 1.5 : 2,usage:&u)
        let roots = try ExactUnivariateRootIsolator().isolate(polynomial,lower:.one,upper:upper,maximumDepth:32,usage:&u)
        try require(roots.count == 1)
        let original = try ExactAlgebraicRealRoot(polynomial:polynomial,isolation:roots[0],usage:&u)
        return try original.refined(maximumWidth:.originalDouble(0x1p-4,usage:&u),maximumDepth:32,usage:&u)
    }
    static func retainedRootBinding<A: ExactScalarAdmission & ~Copyable>(_ root:ExactAlgebraicRealRoot,
        using a:inout A) throws -> OriginalExactScalarDomain {
        let parent = try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        return try OriginalExactScalarDomain(extending:parent,root:root,axis:.coefficient,using:&a)
    }
    public static func retainedRootExtensions() throws {
        let twoRoot = try selectedRoot(2),threeRoot = try selectedRoot(3),reducible = try selectedRoot(2,dependent:true)
        var a = try TraceAdmission()
        let first = try retainedRootBinding(twoRoot,using:&a),alpha = try first.generator(using:&a)
        let second = try OriginalExactScalarDomain(extending:first,root:threeRoot,axis:.coefficient,using:&a)
        let x = try second.importing(alpha,using:&a),y = try second.generator(using:&a)
        let two = try second.integer(2,using:&a),three = try second.integer(3,using:&a)
        try require(try second.compare(second.multiplying(x,x,using:&a),two,using:&a) == .equal)
        try require(try second.compare(second.multiplying(y,y,using:&a),three,using:&a) == .equal)
        try require(try second.compare(x,y,using:&a) == .less)
        let xy = try second.multiplying(x,y,using:&a)
        try require(try second.compare(second.multiplying(xy,xy,using:&a),second.integer(6,using:&a),using:&a) == .equal)
        let third = try OriginalExactScalarDomain(extending:second,root:reducible,axis:.coefficient,using:&a)
        let gamma = try third.generator(using:&a),original = try third.importing(x,using:&a)
        try require(try third.compare(gamma,original,using:&a) == .equal)
        let sum = try third.adding(gamma,original,using:&a)
        let divided = try third.dividing(sum,third.multiplying(third.integer(2,using:&a),original,using:&a),using:&a)
        try require(try third.compare(divided,third.integer(1,using:&a),using:&a) == .equal)
        do { _ = try third.dividing(gamma,third.subtracting(gamma,original,using:&a),using:&a)
            throw Failure.incorrectEvidence }
        catch ExactScalarFailure.divisionByZero {}
        let unrelated = try retainedRootBinding(twoRoot,using:&a)
        do { _ = try third.importing(unrelated.generator(using:&a),using:&a);throw Failure.incorrectEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let retained:OriginalExactScalar
        do { let temporary = try OriginalExactScalarDomain(extending:first,root:threeRoot,axis:.coefficient,using:&a)
            retained = try temporary.adding(temporary.importing(alpha,using:&a),temporary.generator(using:&a),using:&a) }
        let owner = try OriginalExactScalarDomain(retaining:retained,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try require(try owner.sign(of:retained,using:&a) == .positive)
        var measured = try TraceAdmission();_ = try retainedRootBinding(twoRoot,using:&measured)
        var exact = try TraceAdmission(work:measured.work,storage:measured.storageBytes)
        _ = try retainedRootBinding(twoRoot,using:&exact)
        var work = try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try retainedRootBinding(twoRoot,using:&work);throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var storage = try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try retainedRootBinding(twoRoot,using:&storage);throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var entry = try TraceAdmission();entry.base.cancel()
        do { _ = try retainedRootBinding(twoRoot,using:&entry);throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        var final = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try retainedRootBinding(twoRoot,using:&final);throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        for axis in [ExactScalarRootAxis.value,.coefficient] {
            let limited = try OriginalExactScalarDomain(maximumValueDepth:axis == .value ? 0 : 32,
                maximumCoefficientDepth:axis == .coefficient ? 0 : 32,using:&a)
            do { _ = try OriginalExactScalarDomain(extending:limited,root:twoRoot,axis:axis,using:&a)
                throw Failure.incorrectEvidence }
            catch ExactScalarFailure.resourceLimit(let resource) {
                try require(resource == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
        let mixed = try OriginalExactScalarDomain(root:twoRoot,axis:.value,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let both = try OriginalExactScalarDomain(extending:mixed,root:threeRoot,axis:.coefficient,using:&a)
        let mixedGenerator = try both.generator(using:&a)
        try require(mixedGenerator.depth.value >= twoRoot.isolation.isolationDepth &&
            mixedGenerator.depth.coefficient >= threeRoot.isolation.isolationDepth)
        print("PASS retained two-root extension, dependent reducible root, original selectors, ancestor import, lifetime and independent atomic limits/cancel/depth")
    }
}
