@testable import L0
import L1
import L2
import OriginalCoordinateTransfer

enum ProofFailure: Error { case incorrect; case check(Int) }
func require(_ value: Bool, line: Int = #line) throws { guard value else { throw ProofFailure.check(line) } }
/// Observes the two owned array admissions before lower scalar transport starts.
struct CoordinateStorageAdmission: ExactScalarAdmission, ~Copyable {
    var ledger: ExactScalarLedger
    var storageCalls = 0
    var secondPayload = 0
    var workAtSecondPayload = 0
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        storageCalls += 1
        if storageCalls == 2 {
            secondPayload = bytes
            workAtSecondPayload = ledger.work
        }
        try ledger.retainStorage(bytes: bytes)
    }
    mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
        try ledger.visitCell(axis: axis, depth: depth)
    }
    mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
        try ledger.admitDepth(value: value, coefficient: coefficient)
    }
}

@main struct CoordinateProof {
    /// Only the returned receipt retains the temporary refined source extension.
    static func retainedConstants(axis: ExactScalarRootAxis, destination: OriginalExactScalarDomain,
        using a: inout ExactScalarLedger) throws -> ExactOriginalScalarTransferReceipt {
        let field = try ExactAlgebraicScalarDomain.base(field: destination, maximumExtensionLevel: 4, using: &a)
        let roots = try ExactRealRootDomain(field: field, using: &a), ring = roots.polynomials
        let x = try ring.variable(0, using: &a)
        let law = try ring.subtracting(ring.multiplying(x, x, using: &a),
            ring.constant(field.integer(2, using: &a), using: &a), using: &a)
        let source = try roots.bind(law, refinementAxis: axis, using: &a)
        let interval = try roots.domain(lower: .finite(field.integer(1, using: &a)),
            upper: .finite(field.integer(2, using: &a)), using: &a)
        let selected = try roots.isolate(source, in: interval, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let refined = try roots.refine(selected, maximumWidth: field.binary64(exactly: 0.0625, using: &a), using: &a)
        let extensionField = try field.adjoin(refined, using: &a), f = extensionField.domain
        let values = [try f.integer(7, using: &a), try f.integer(0, using: &a),
            try f.dividing(f.integer(-7, using: &a), f.integer(3, using: &a), using: &a),
            try f.multiplying(extensionField.generator, extensionField.generator, using: &a)]
        var bounded = ExactScalarLedger(limits: try .init(work: 512, storageBytes: 16_384, valueDepth: 32, coefficientDepth: 32))
        return try DefaultExactOriginalScalarTransporter().transfer(values, into: destination, using: &bounded)
    }

    static func main() throws {
        var a = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32))
        let base = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try ExactAlgebraicScalarDomain.base(field: base, maximumExtensionLevel: 4, using: &a)
        let integer = try field.integer(7, using: &a)
        let payload = MemoryLayout<OriginalExactScalar>.stride
        var storageGate = CoordinateStorageAdmission(ledger: .init(limits: try .init(
            work: 20_000_000, storageBytes: 2 * payload - 1, valueDepth: 32, coefficientDepth: 32)))
        do {
            _ = try DefaultExactOriginalScalarTransporter().transfer([integer], into: base, using: &storageGate)
            throw ProofFailure.incorrect
        } catch ExactScalarFailure.resourceLimit(.storage) {}
        try require(storageGate.storageCalls == 2 && storageGate.secondPayload == payload &&
            storageGate.workAtSecondPayload == 1 && storageGate.ledger.storageBytes == payload)
        print("COORDINATE_SOURCE_STORAGE_OK pre-admission rejects before lower transport")
        let roots = try ExactRealRootDomain(field: field, using: &a), p = roots.polynomials
        let x = try p.variable(0, using: &a)
        let law = try p.subtracting(p.multiplying(x, x, using: &a), p.constant(field.integer(2, using: &a), using: &a), using: &a)
        let source = try roots.bind(law, using: &a)
        let range = try roots.domain(lower: .finite(field.integer(1, using: &a)), upper: .finite(field.integer(2, using: &a)), using: &a)
        let selected = try roots.isolate(source, in: range, limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extended = try field.adjoin(selected, using: &a)
        let constant = try extended.domain.integer(7, using: &a)
        var constantBudget = CoordinateStorageAdmission(ledger: .init(limits: try .init(
            work: 256, storageBytes: 8_192, valueDepth: 32, coefficientDepth: 32)))
        let constantResult = try DefaultExactOriginalScalarTransporter().transfer([constant], into: base, using: &constantBudget)
        print("CONSTANT_BOUNDED work=\(constantBudget.ledger.work) bytes=\(constantBudget.ledger.storageBytes)")
        try require(constantResult.sources.count == 1 && constantResult.field.context.parent == nil)
        try require(try constantResult.field.compare(constantResult.values[0],
            constantResult.field.integer(7, using: &a), using: &a) == .equal)
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            let retained = try retainedConstants(axis: axis, destination: base, using: &a)
            let retainedDomain = try ExactAlgebraicScalarDomain(retaining: retained.sources[0], using: &a)
            try require(retainedDomain.extensionLevel == 1 && retained.field.context.parent == nil)
            let inherited = retained.sources[0].depth
            try require((axis == .value ? inherited.value : inherited.coefficient) > 0)
            for value in retained.values {
                try require(value.depth.value >= inherited.value && value.depth.coefficient >= inherited.coefficient)
            }
            let expected = [try base.integer(7, using: &a), try base.integer(0, using: &a),
                try base.dividing(base.integer(-7, using: &a), base.integer(3, using: &a), using: &a),
                try base.integer(2, using: &a)]
            for index in expected.indices {
                try require(try retained.field.compare(retained.values[index],
                    retained.field.importing(expected[index], using: &a), using: &a) == .equal)
            }
            var shallow = ExactScalarLedger(limits: try .init(work: 20_000_000, storageBytes: 134_217_728,
                valueDepth: axis == .value ? inherited.value - 1 : 32,
                coefficientDepth: axis == .coefficient ? inherited.coefficient - 1 : 32))
            do { _ = try retained.field.sign(of: retained.values[0], using: &shallow); throw ProofFailure.incorrect }
            catch ExactScalarFailure.resourceLimit(let exhausted) {
                try require(exhausted == (axis == .value ? .valueDepth : .coefficientDepth))
            }
            let strictDestination = try OriginalExactScalarDomain(
                maximumValueDepth: axis == .value ? 0 : 32,
                maximumCoefficientDepth: axis == .coefficient ? 0 : 32, using: &a)
            do { _ = try DefaultExactOriginalScalarTransporter().transfer(retained.sources, into: strictDestination, using: &a)
                throw ProofFailure.incorrect }
            catch ExactScalarFailure.resourceLimit(let exhausted) {
                try require(exhausted == (axis == .value ? .valueDepth : .coefficientDepth))
            }
            for cap in [ExactResource.work, .storage] {
                var limited = ExactScalarLedger(limits: try .init(work: cap == .work ? 0 : 20_000_000,
                    storageBytes: cap == .storage ? 0 : 134_217_728, valueDepth: 32, coefficientDepth: 32))
                do { _ = try DefaultExactOriginalScalarTransporter().transfer(retained.sources, into: base, using: &limited)
                    throw ProofFailure.incorrect }
                catch ExactScalarFailure.resourceLimit(let exhausted) { try require(exhausted == cap) }
            }
            var cancelledConstant = ExactScalarLedger(limits: try .init(work: 20_000_000,
                storageBytes: 134_217_728, valueDepth: 32, coefficientDepth: 32)); cancelledConstant.cancel()
            do { _ = try DefaultExactOriginalScalarTransporter().transfer(retained.sources, into: base, using: &cancelledConstant)
                throw ProofFailure.incorrect }
            catch ExactScalarFailure.cancelled {}
            let verified = try DefaultExactOriginalScalarTransporter().transfer(retained.sources, into: base, using: &a)
            try require(try verified.field.compare(verified.values[0], verified.field.integer(7, using: &a), using: &a) == .equal)
        }
        print("CONSTANT_TRANSFER_OK zero, rational, reduced-square, both retained depths, destination policy, released source and atomic failures")
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
        let liftedParent = try nestedField.domain.importing(y, using: &a)
        let parentOnly = try DefaultExactOriginalScalarTransporter().transfer([liftedParent], into: base, using: &a)
        try require(try parentOnly.field.compare(parentOnly.field.multiplying(parentOnly.values[0], parentOnly.values[0], using: &a),
            parentOnly.field.integer(2, using: &a), using: &a) == .equal)
        try require(try ExactAlgebraicScalarDomain(retaining: parentOnly.sources[0], using: &a).extensionLevel == 2)
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
