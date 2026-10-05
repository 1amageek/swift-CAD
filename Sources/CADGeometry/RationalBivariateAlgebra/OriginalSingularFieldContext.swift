/// Immutable original ordered-field owner for one retained singular-resolution path.
package final class OriginalSingularFieldContext: Sendable {
    enum Source: Sendable {
        case rational
        case original(ExactBivariateSystemRoot)
        case extended(OriginalSingularFieldRoot)
    }
    let source: Source
    var parent: OriginalSingularFieldContext? {
        switch source { case .rational, .original: nil; case .extended(let root): root.polynomial.context }
    }
    package let depth: Int
    package let coefficientDepth: Int
    package init<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        try Self.admit(usage: &usage); source = .rational; depth = 0; coefficientDepth = 0
    }
    package init<B: RationalAlgebraAdmitting>(original: ExactBivariateSystemRoot, usage: inout B) throws {
        try Self.admit(usage: &usage); source = .original(original)
        depth = max(original.projectionRoot.isolation.isolationDepth, original.fiberRoot.isolationDepth)
        coefficientDepth = 0
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
    }
    private static func admit<B: RationalAlgebraAdmitting>(usage: inout B) throws {
        // The immutable owner retains one Source payload and one reference. The
        // Swift heap object header has metadata and reference-count words; all
        // are admitted before allocation, while child buffers admit themselves.
        let header = try rationalAlgebraCount(2, MemoryLayout<UnsafeRawPointer>.stride, multiply: true)
        let sourcePayload = try rationalAlgebraCount(MemoryLayout<Source>.stride, MemoryLayout<OriginalSingularFieldContext>.stride)
        let payload = try rationalAlgebraCount(sourcePayload,
            rationalAlgebraCount(2, MemoryLayout<Int>.stride, multiply: true))
        try RationalAlgebraStorage.retainBytes(rationalAlgebraCount(header, payload), usage: &usage)
    }
}
