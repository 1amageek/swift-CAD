import L0
import L1
import L2
import OriginalCoordinateTransfer

enum ProofFailure: Error { case incorrect; case check(Int) }
func require(_ value: Bool, line: Int = #line) throws { guard value else { throw ProofFailure.check(line) } }
@main struct CoordinateProof {
    static func main() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let base = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try ExactAlgebraicScalarDomain.base(field: base, maximumExtensionLevel: 4, using: &a)
        let roots = try ExactRealRootDomain(field: field, using: &a), p = roots.polynomials
        let x = try p.variable(0, using: &a)
        let law = try p.subtracting(p.multiplying(x, x, using: &a), p.constant(field.integer(2, using: &a), using: &a), using: &a)
        let source = try roots.bind(law, using: &a)
        let range = try roots.domain(lower: .finite(field.integer(1, using: &a)), upper: .finite(field.integer(2, using: &a)), using: &a)
        let selected = try roots.isolate(source, in: range, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extended = try field.adjoin(selected, using: &a)
        let y = extended.generator, f = extended.domain
        let square = try f.multiplying(y, y, using: &a)
        let reciprocal = try f.dividing(f.integer(1, using: &a), y, using: &a)
        let sum = try f.adding(y, f.integer(1, using: &a), using: &a)
        var measured = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let values = [y, square, reciprocal, sum, y]
        let result = try DefaultExactOriginalScalarTransporter().transfer(values, into: base, using: &measured)
        let original = result.field
        try require(try original.compare(original.multiplying(result.values[0], result.values[0], using: &a), original.integer(2, using: &a), using: &a) == .equal)
        try require(try original.compare(result.values[1], original.integer(2, using: &a), using: &a) == .equal)
        try require(try original.compare(original.multiplying(result.values[0], result.values[2], using: &a), original.integer(1, using: &a), using: &a) == .equal)
        try require(try original.compare(original.subtracting(result.values[3], result.values[0], using: &a), original.integer(1, using: &a), using: &a) == .equal)
        try require(try original.compare(result.values[0], result.values[4], using: &a) == .equal)
        var exact = ExactScalarLedger(limits: try .init(work: measured.work, storageBytes: measured.storageBytes, valueDepth: 32, coefficientDepth: 32))
        _ = try DefaultExactOriginalScalarTransporter().transfer(values, into: base, using: &exact)
        var exhausted = ExactScalarLedger(limits: try .init(work: measured.work - 1, storageBytes: measured.storageBytes, valueDepth: 32, coefficientDepth: 32))
        do { _ = try DefaultExactOriginalScalarTransporter().transfer(values, into: base, using: &exhausted); throw ProofFailure.incorrect }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var shortStorage = ExactScalarLedger(limits: try .init(work: measured.work,
            storageBytes: measured.storageBytes - 1, valueDepth: 32, coefficientDepth: 32))
        do { _ = try DefaultExactOriginalScalarTransporter().transfer(values, into: base, using: &shortStorage); throw ProofFailure.incorrect }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var cancelled = ExactScalarLedger(limits: try .init(work: 20_000_000,
            storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        cancelled.cancel()
        do { _ = try DefaultExactOriginalScalarTransporter().transfer(values, into: base, using: &cancelled); throw ProofFailure.incorrect }
        catch ExactScalarFailure.cancelled {}
        let nestedRoots = try ExactRealRootDomain(field: f, using: &a)
        let np = nestedRoots.polynomials, nx = try np.variable(0, using: &a)
        let nestedLaw = try np.subtracting(np.multiplying(nx, nx, using: &a), np.constant(y, using: &a), using: &a)
        let nestedSource = try nestedRoots.bind(nestedLaw, using: &a)
        let nestedRange = try nestedRoots.domain(lower: .finite(f.integer(1, using: &a)),
            upper: .finite(f.integer(2, using: &a)), using: &a)
        let nestedRoot = try nestedRoots.isolate(nestedSource, in: nestedRange,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let nestedField = try f.adjoin(nestedRoot, using: &a)
        let nested = try DefaultExactOriginalScalarTransporter().transfer([nestedField.generator, y], into: base, using: &a)
        let nf = nested.field, z = nested.values[0]
        try require(try nf.compare(nf.multiplying(z, z, using: &a), nested.values[1], using: &a) == .equal)
        let z2 = try nf.multiplying(z, z, using: &a)
        try require(try nf.compare(nf.multiplying(z2, z2, using: &a), nf.integer(2, using: &a), using: &a) == .equal)
        let originalBase = try ExactAlgebraicScalarDomain.base(field: copy original,
            maximumExtensionLevel: 4, using: &a)
        let originalRoots = try ExactRealRootDomain(field: originalBase, using: &a)
        let op = originalRoots.polynomials, ox = try op.variable(0, using: &a)
        let alpha = try originalBase.importingBase(result.values[0], using: &a)
        let originalLaw = try op.subtracting(op.multiplying(ox, ox, using: &a), op.constant(alpha, using: &a), using: &a)
        let originalSource = try originalRoots.bind(originalLaw, using: &a)
        let originalRange = try originalRoots.domain(lower: .finite(originalBase.integer(1, using: &a)),
            upper: .finite(originalBase.integer(2, using: &a)), using: &a)
        let originalRoot = try originalRoots.isolate(originalSource, in: originalRange,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let originalExtension = try originalBase.adjoin(originalRoot, using: &a)
        let foreignDestination = try OriginalExactScalarDomain(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, using: &a)
        let nonrational = try DefaultExactOriginalScalarTransporter().transfer([originalExtension.generator, alpha],
            into: foreignDestination, using: &a)
        let cf = nonrational.field
        try require(try cf.compare(cf.multiplying(nonrational.values[0], nonrational.values[0], using: &a),
            nonrational.values[1], using: &a) == .equal)
        print("PASS retained L2 selected root, fractions, repeated owner, original arithmetic and exact work boundary")
        print("COORDINATE_TRANSFER_OK work=\(measured.work) bytes=\(measured.storageBytes)")
    }
}
