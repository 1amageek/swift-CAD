import CADCore

/// Face-issued complete directed loops retained with the graph's selected source role.
public final class OriginalIssuedGraphBoundaryDomain<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: Sendable {
    public let source: OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>
    package let loops: [OriginalNativeBoundaryDomain.Loop]

    package init<A: ExactScalarAdmission & ~Copyable>(source: OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>,
        loops: [OriginalNativeBoundaryDomain.Loop], using a: inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint()
            guard !loops.isEmpty, loops.contains(where: { !$0.isInner }) else { throw NativeExactRelationFailure.invalidDomain }
            let compiler = try OriginalExactBoundaryCompiler<OriginalExactScalarDomain>(field: source.raw.first.field, using: &a)
            try compiler.validate(loops, using: &a)
            let fields = MemoryLayout<OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>>.stride.addingReportingOverflow(MemoryLayout<[OriginalNativeBoundaryDomain.Loop]>.stride)
            let bytes = fields.partialValue.addingReportingOverflow(2 * MemoryLayout<UInt>.stride)
            guard !fields.overflow, !bytes.overflow else { throw ExactScalarFailure.countOverflow }
            try a.retainStorage(bytes: bytes.partialValue)
            self.source = source
            self.loops = loops
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }
}
