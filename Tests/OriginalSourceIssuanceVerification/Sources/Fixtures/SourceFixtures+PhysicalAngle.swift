import L0
import L1
import SourceIssuer

extension SourceFixtures {
    public static func physicalAngleCoefficients() throws {
        var a = try TraceAdmission()
        let f = try OriginalPhysicalAngleScalarDomain(originalRadians: 1, using: &a)
        let s = try f.sine(using: &a), c = try f.cosine(using: &a), one = try f.integer(1, using: &a)
        let identity = try f.adding(f.multiplying(s,s,using:&a),f.multiplying(c,c,using:&a),using:&a)
        try require(try f.compare(identity,one,using:&a) == .equal)
        let quotient = try f.dividing(s,c,using:&a)
        try require(try f.compare(f.multiplying(quotient,c,using:&a),s,using:&a) == .equal)
        try require(try f.compare(s,f.binary64(exactly:0.84,using:&a),using:&a) == .greater)
        try require(try f.compare(s,f.binary64(exactly:0.85,using:&a),using:&a) == .less)
        try require(try f.compare(c,f.binary64(exactly:0.54,using:&a),using:&a) == .greater)
        try require(try f.compare(c,f.binary64(exactly:0.55,using:&a),using:&a) == .less)
        // Consecutive binary64 separators verify that rounded trig values are not
        // treated as original equality. The sign must be proved from exact bounds.
        let rounded = 0.8414709848078965
        try require(try f.compare(s,f.binary64(exactly:rounded,using:&a),using:&a) == .greater)
        try require(try f.compare(s,f.binary64(exactly:rounded.nextUp,using:&a),using:&a) == .less)
        for (angle,ss,cs) in [(4.0,ExactSign.negative,ExactSign.negative),
            (8.0,.positive,.negative),(-1.0,.negative,.positive)] {
            var local = try TraceAdmission()
            let g = try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&local)
            try require(try g.sign(of:g.sine(using:&local),using:&local) == ss)
            try require(try g.sign(of:g.cosine(using:&local),using:&local) == cs)
        }
        let retained: OriginalPhysicalAngleValue
        do {
            let temporary = try OriginalPhysicalAngleScalarDomain(originalRadians:0.5,using:&a)
            retained = try temporary.sine(using:&a)
        }
        let retainedField = try OriginalPhysicalAngleScalarDomain(retaining:retained,using:&a)
        try require(retained.originalRadians == 0.5)
        try require(try retainedField.sign(of:retained,using:&a) == .positive)
        let foreign = try OriginalPhysicalAngleScalarDomain(originalRadians:1,using:&a)
        do { _ = try foreign.importing(s,using:&a); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.incompatibleDomain {}
        let zero = try f.subtracting(s,s,using:&a)
        do { _ = try f.dividing(one,zero,using:&a); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.divisionByZero {}
        for bad in [0.0,Double.infinity,Double.nan] {
            do { _ = try OriginalPhysicalAngleScalarDomain(originalRadians:bad,using:&a); throw Failure.incorrectEvidence }
            catch ExactScalarFailure.invalidSource {}
        }
        print("PASS physical-radian exact identities, near-binary64 sign separation, range doubling, lifetime and typed failures")
    }

    public static func physicalAngleResources() throws {
        func calculation(_ a: inout TraceAdmission) throws {
            let f = try OriginalPhysicalAngleScalarDomain(originalRadians:1,using:&a)
            let s = try f.sine(using:&a)
            try require(try f.compare(s,f.binary64(exactly:0.84,using:&a),using:&a) == .greater)
        }
        var measured = try TraceAdmission()
        try calculation(&measured)
        let work = measured.work, bytes = measured.storageBytes, calls = measured.storageCalls
        var exact = try TraceAdmission(work:work,storage:bytes)
        try calculation(&exact)
        try require(exact.work == work && exact.storageBytes == bytes)
        var lowWork = try TraceAdmission(work:work-1)
        do { try calculation(&lowWork); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var lowStorage = try TraceAdmission(storage:bytes-1)
        do { try calculation(&lowStorage); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var cancelled = try TraceAdmission(cancelAtStorage:calls)
        do { try calculation(&cancelled); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        var entry = try TraceAdmission(); entry.base.cancel()
        do { try calculation(&entry); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.cancelled {}
        try require(entry.work == 0 && entry.storageBytes == 0)
        var a = try TraceAdmission()
        let f = try OriginalPhysicalAngleScalarDomain(originalRadians:1,using:&a)
        let s = try f.sine(using:&a)
        var noRefinement = ExactScalarLedger(limits:try .init(work:20_000_000,storageBytes:134_217_728,
            valueDepth:0,coefficientDepth:0))
        do { _ = try f.sign(of:s,using:&noRefinement); throw Failure.incorrectEvidence }
        catch ExactScalarFailure.resourceLimit(.coefficientDepth) {}
        try require(noRefinement.valueDepth == 0 && noRefinement.coefficientDepth == 0)
        print("PASS physical-angle exact cumulative work/storage, entry/final cancellation and independent coefficient depth")
        print("MEASURE physical-angle work=\(work) generatedBytes=\(bytes)")
    }
}
