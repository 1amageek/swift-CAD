import L0
import L1
import L2

public enum TransportFixtures {
    private typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    private typealias Root = ExactRealRoot<Field>

    private static func prepared(_ a: inout ExactScalarLedger) throws -> (
        positive: Root, negative: Root, repeated: Root, target: ExactRealRootDomain<Field>, targetField: Field, sibling: Root,
        unrelated: ExactRealRootDomain<Field>
    ) {
        let base = try Field.base(field: .init(), maximumExtensionLevel: 2, using: &a)
        let issuer = try ExactRealRootDomain(field: base, variableCount: 3, using: &a)
        let p = issuer.polynomials, x = try p.variable(2, using: &a)
        let quadratic = try p.subtracting(p.multiplying(x, x, using: &a),
            p.constant(base.integer(2, using: &a), using: &a), using: &a)
        let quartic = try p.multiplying(quadratic,
            p.subtracting(p.multiplying(x, x, using: &a),
                p.constant(base.integer(3, using: &a), using: &a), using: &a), using: &a)
        let source = try issuer.bind(quartic,
            variable: 2, refinementAxis: .coefficient, using: &a)
        let one = try base.integer(1, using: &a)
        let half = try base.dividing(base.integer(3, using: &a), base.integer(2, using: &a), using: &a)
        let positiveInterval = try issuer.domain(lower: .finite(one), upper: .finite(half),
            includesLower: true, includesUpper: false, using: &a)
        let negativeInterval = try issuer.domain(lower: .finite(base.negated(half, using: &a)),
            upper: .finite(base.negated(one, using: &a)), includesLower: false, includesUpper: true, using: &a)
        let positive = try issuer.isolate(source, in: positiveInterval,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let negative = try issuer.isolate(source, in: negativeInterval,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let divisor = try issuer.bind(quadratic, variable: 2, refinementAxis: .coefficient, using: &a)
        let reduced = try issuer.refine(positive, usingDefiningDivisor: divisor, using: &a)
        let refined = try issuer.refine(reduced,
            maximumWidth: base.dividing(one, base.integer(16, using: &a), using: &a), using: &a)
        let linear = try p.subtracting(x, p.constant(one, using: &a), using: &a)
        let repeatedSource = try issuer.bind(p.multiplying(linear,
            p.multiplying(linear, linear, using: &a), using: &a),
            variable: 2, refinementAxis: .coefficient, using: &a)
        let singleton = try issuer.domain(lower: .finite(one), upper: .finite(one), using: &a)
        let repeated = try issuer.isolate(repeatedSource, in: singleton,
            limits: .init(maximumRoots: 1), using: &a).roots[0]
        let extensionRoot = try FieldFixtures.root(base, degree: 2, right: base.integer(3, using: &a), &a)
        let child = try base.adjoin(extensionRoot, using: &a)
        let siblingField = try base.adjoin(extensionRoot, using: &a)
        let sibling = try FieldFixtures.root(siblingField.domain, degree: 1, right: siblingField.generator, &a)
        let unrelated = try Field.base(field: .init(), maximumExtensionLevel: 2, using: &a)
        return (refined, negative, repeated, try .init(field: child.domain, variableCount: 3, using: &a), child.domain,
            sibling, try .init(field: unrelated, variableCount: 3, using: &a))
    }

    private static func correspondence(_ receipt: ExactRealRootTransport<Field>, field: Field,
        _ a: inout ExactScalarLedger) throws {
        let original = receipt.original, root = receipt.transferred
        let target = try ExactRealRootDomain(retaining: root.source, using: &a)
        try RootFixtures.require(root.source.variable == 2 && root.source.original.variableCount == 3)
        try RootFixtures.require(root.source.refinementAxis == original.source.refinementAxis)
        try RootFixtures.require(root.ordinal == original.ordinal && root.multiplicity == original.multiplicity)
        try RootFixtures.require(root.isolation.includesLower == original.isolation.includesLower
            && root.isolation.includesUpper == original.isolation.includesUpper)
        try RootFixtures.require(root.depth.value >= original.depth.value
            && root.depth.coefficient >= original.depth.coefficient
            && receipt.depth.value >= root.depth.value && receipt.depth.coefficient >= root.depth.coefficient)
        let law = try target.polynomials.importing(original.source.original, using: &a)
        try RootFixtures.require(target.polynomials.equals(law, root.source.original, using: &a))
        try RootFixtures.require(target.sign(of: root.source, at: root, using: &a) == .zero)
        guard case .finite(let beforeLower) = original.isolation.lower,
            case .finite(let beforeUpper) = original.isolation.upper,
            case .finite(let afterLower) = root.isolation.lower,
            case .finite(let afterUpper) = root.isolation.upper else { throw ExactRealRootFailure.invalidEvidence }
        try RootFixtures.require(field.compare(field.importing(beforeLower, using: &a), afterLower, using: &a) == .equal)
        try RootFixtures.require(field.compare(field.importing(beforeUpper, using: &a), afterUpper, using: &a) == .equal)
    }

    public static func verify() throws {
        var a = ExactScalarLedger(limits: try .init(work: 100_000_000, storageBytes: 150_000_000,
            valueDepth: 100, coefficientDepth: 100))
        let inputs = try prepared(&a)
        var ancestor = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 50_000_000,
            valueDepth: 32, coefficientDepth: 32))
        let positive = try inputs.target.transport(inputs.positive, using: &ancestor)
        let negative = try inputs.target.transport(inputs.negative, using: &a)
        try correspondence(positive, field: inputs.targetField, &a)
        try correspondence(negative, field: inputs.targetField, &a)
        try RootFixtures.require(positive.transferred.ordinal == 2 && positive.transferred.multiplicity == 1)
        try RootFixtures.require(negative.transferred.ordinal == 1 && negative.transferred.multiplicity == 1)
        let repeated = try inputs.target.transport(inputs.repeated, using: &a)
        try correspondence(repeated, field: inputs.targetField, &a)
        try RootFixtures.require(repeated.transferred.ordinal == 0 && repeated.transferred.multiplicity == 3)
        try RootFixtures.require(inputs.target.compare(negative.transferred, positive.transferred, using: &a) == .less)
        let coordinate = try inputs.target.bind(inputs.target.polynomials.variable(2, using: &a),
            variable: 2, refinementAxis: .coefficient, using: &a)
        try RootFixtures.require(inputs.target.sign(of: coordinate, at: positive.transferred, using: &a) == .positive)
        try RootFixtures.require(inputs.target.sign(of: coordinate, at: negative.transferred, using: &a) == .negative)
        let p = inputs.target.polynomials, field = inputs.targetField
        let x = try p.variable(2, using: &a), square = try p.multiplying(x, x, using: &a)
        let selectedLaw = try inputs.target.bind(p.subtracting(square,
            p.constant(field.integer(2, using: &a), using: &a), using: &a), variable: 2, using: &a)
        let otherLaw = try inputs.target.bind(p.subtracting(square,
            p.constant(field.integer(3, using: &a), using: &a), using: &a), variable: 2, using: &a)
        try RootFixtures.require(inputs.target.sign(of: selectedLaw, at: positive.transferred, using: &a) == .zero)
        try RootFixtures.require(inputs.target.sign(of: otherLaw, at: positive.transferred, using: &a) == .negative)
        let selfReceipt = try inputs.target.transport(positive.transferred, using: &a)
        try correspondence(selfReceipt, field: inputs.targetField, &a)
        try RootFixtures.require(inputs.target.compare(selfReceipt.transferred, positive.transferred, using: &a) == .equal)

        // Independently issued roots in the same coefficient field require explicit transfer too.
        let sameField = try ExactRealRootDomain(field: inputs.targetField, variableCount: 3, using: &a)
        let sameFieldReceipt = try sameField.transport(positive.transferred, using: &a)
        try correspondence(sameFieldReceipt, field: inputs.targetField, &a)
        let siblingTarget = try ExactRealRootDomain(field: inputs.targetField, using: &a)
        do {
            _ = try siblingTarget.transport(inputs.sibling, using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.polynomial(.scalar(.incompatibleDomain)) { }
        do {
            _ = try inputs.unrelated.transport(inputs.positive, using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.polynomial(.scalar(.incompatibleDomain)) { }
        let wrongBasis = try ExactRealRootDomain(field: inputs.targetField, using: &a)
        do {
            _ = try wrongBasis.transport(inputs.positive, using: &a)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.polynomial(.invalidVariableCount) { }

        var observed = TerminalAdmission()
        _ = try inputs.target.transport(inputs.positive, using: &observed)
        var cancelled = TerminalAdmission(cancelAt: observed.checkpoints)
        do {
            _ = try inputs.target.transport(inputs.positive, using: &cancelled)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.cancelled) { }

        try RootFixtures.require(inputs.positive.depth.coefficient > 0)
        var insufficientDepth = ExactScalarLedger(limits: try .init(work: 16_777_216, storageBytes: 50_000_000,
            valueDepth: 100, coefficientDepth: inputs.positive.depth.coefficient - 1))
        do {
            _ = try inputs.target.transport(inputs.positive, using: &insufficientDepth)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.resourceLimit(.coefficientDepth)) { }
        var entryCancelled = ExactScalarLedger(limits: try .init(work: 1_000_000, storageBytes: 1_000_000,
            valueDepth: 100, coefficientDepth: 100))
        entryCancelled.cancel()
        do {
            _ = try inputs.target.transport(positive.transferred, using: &entryCancelled)
            throw ExactRealRootFailure.invalidEvidence
        } catch ExactRealRootFailure.scalar(.cancelled) { }

        // The returned receipts retain both source and target owners after construction locals are released.
        let retained = try lifetime(&a)
        guard let coefficient = retained.transferred.source.original.terms.first?.coefficient else {
            throw ExactRealRootFailure.invalidEvidence
        }
        let retainedField = try Field(retaining: coefficient, using: &a)
        try correspondence(retained, field: retainedField, &a)
        print("PASS: explicit root transport preserves source, conjugate, endpoints, depth and lifetime; foreign owners and cancellation reject")
    }

    private static func lifetime(_ a: inout ExactScalarLedger) throws -> ExactRealRootTransport<Field> {
        let inputs = try prepared(&a)
        return try inputs.target.transport(inputs.positive, using: &a)
    }
}
