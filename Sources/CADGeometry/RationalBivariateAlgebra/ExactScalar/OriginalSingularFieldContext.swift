/// Immutable original ordered-field owner for one retained singular-resolution path.
package final class OriginalSingularFieldContext: Sendable {
    enum Source: Sendable {
        case rational
        case original(ExactAlgebraicPairAuthority)
        case extended(OriginalSingularFieldRoot)
    }
    enum ConstantAuthority: Sendable {
        case original(unit: ExactBivariatePolynomial)
        case extended(zero: OriginalSingularFieldPolynomial, unit: OriginalSingularFieldPolynomial)
    }
    let source: Source
    let constantAuthority: ConstantAuthority
    var parent: OriginalSingularFieldContext? {
        switch source { case .rational, .original: nil; case .extended(let root): root.polynomial.context }
    }
    package let depth: Int
    package let coefficientDepth: Int
    package init<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        try Self.admit(usage: &usage); source = .rational; depth = 0; coefficientDepth = 0
        constantAuthority = .original(unit: try .constant(.one, usage: &usage))
        try exactScalarTaskCheckpoint()
    }
    init<B: RationalAlgebraAdmitting>(original: ExactAlgebraicPairAuthority, usage: inout B) throws {
        try Self.admit(usage: &usage); source = .original(original)
        depth = max(original.projectionRoot.isolation.isolationDepth, original.fiberRoot.isolationDepth)
        coefficientDepth = 0
        constantAuthority = .original(unit: try .constant(.one, usage: &usage))
        try exactScalarTaskCheckpoint()
    }
    init<B: RationalAlgebraAdmitting>(root: OriginalSingularFieldRoot, usage: inout B) throws {
        try Self.admit(usage: &usage); source = .extended(root)
        switch root.admissionDomain {
        case .parameter:
            depth = max(root.polynomial.context.depth, root.isolation.depth)
            coefficientDepth = root.polynomial.context.coefficientDepth
        case .coefficient:
            depth = root.polynomial.context.depth
            coefficientDepth = max(root.polynomial.context.coefficientDepth, root.isolation.depth)
        }
        let parent = root.polynomial.context
        let one = try OriginalSingularFieldElement.constant(.one, in: parent,
            maximumDepth: parent.depth, usage: &usage)
        let zero = try OriginalSingularFieldPolynomial(context: parent, coefficients: [],
            maximumDepth: parent.depth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
        let unit = try OriginalSingularFieldPolynomial(context: parent, coefficients: [one],
            maximumDepth: parent.depth, usage: &usage)
        constantAuthority = .extended(zero: zero, unit: unit)
        try exactScalarTaskCheckpoint()
    }
    private static func admit<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        // The immutable owner retains source and structural-constant authority. The
        // Swift heap object header has metadata and reference-count words; all
        // are admitted before allocation, while child buffers admit themselves.
        let header = try exactScalarCount(2, MemoryLayout<UnsafeRawPointer>.stride, multiply: true)
        let sourcePayload = try exactScalarCount(MemoryLayout<Source>.stride, MemoryLayout<OriginalSingularFieldContext>.stride)
        let originalPayload = try exactScalarCount(sourcePayload,
            exactScalarCount(2, MemoryLayout<Int>.stride, multiply: true))
        let payload = try exactScalarCount(originalPayload, MemoryLayout<ConstantAuthority>.stride)
        try RationalAlgebraStorage.retainBytes(exactScalarCount(header, payload), usage: &usage)
    }
}
