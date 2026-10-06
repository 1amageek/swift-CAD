import CADCore

/// Exact source arithmetic forwards to the invocation's existing owner.
struct NativeSurfaceOriginalProofAllowance: RationalAlgebraAdmitting {
    let admission: NativeSurfaceEmbeddingAdmission
    mutating func consumeExactWork(_ count: Int) throws { try admission.work(count) }
    mutating func retainExactStorage(_ count: Int) throws { try admission.storageWords(count) }
    mutating func visitExactCell(depth: Int) throws { try admission.cell(depth: depth) }
}
