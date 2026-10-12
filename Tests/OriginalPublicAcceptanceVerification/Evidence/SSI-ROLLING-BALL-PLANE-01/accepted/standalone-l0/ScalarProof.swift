import L0
@main enum ScalarProof {
 typealias Base=OriginalExactScalarDomain
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init(work: Int = 50_000_000, bytes: Int = 1_073_741_824) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
 enum Assertion: Error { case failed }
 static func require(_ b: Bool)throws { if !b { throw Assertion.failed } }
 static func main() throws {

            var a = try Admission()
            let f = try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            for (value,expected) in [(25,5),(0,0)] {
                guard let root = try f.exactRationalSquareRoot(of:f.integer(value,using:&a),using:&a) else { throw ExactScalarFailure.invalidEvidence }
                try require(try f.compare(root,f.integer(expected,using:&a),using:&a) == .equal)
            }
            let fraction = try f.dividing(f.integer(9,using:&a),f.integer(25,using:&a),using:&a)
            guard let root = try f.exactRationalSquareRoot(of:fraction,using:&a) else { throw ExactScalarFailure.invalidEvidence }
            try require(try f.compare(root,f.dividing(f.integer(3,using:&a),f.integer(5,using:&a),using:&a),using:&a) == .equal)
            for value in [2,-1] { try require(try f.exactRationalSquareRoot(of:f.integer(value,using:&a),using:&a) == nil) }
            let other = try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            do { _ = try f.exactRationalSquareRoot(of:other.integer(25,using:&a),using:&a);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.incompatibleDomain { }
            let value = try f.integer(25,using:&a)
            var exhausted = try Admission(work:0)
            do { _ = try f.exactRationalSquareRoot(of:value,using:&exhausted);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.resourceLimit(.work) { }
            a.ledger.cancel()
            do { _ = try f.exactRationalSquareRoot(of:value,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.cancelled { }
 print("PASS standalone L0 square root")
 }
}
