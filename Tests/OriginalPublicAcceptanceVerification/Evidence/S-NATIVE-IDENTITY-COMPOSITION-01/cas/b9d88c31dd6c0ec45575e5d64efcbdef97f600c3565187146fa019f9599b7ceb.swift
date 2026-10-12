/// Preserves a retained scalar root's parameter or coefficient admission domain.
struct OriginalScalarRootDomainAdmission<Base: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
    var exactDepthResource: ExactResource {
        switch domain { case .parameter: .valueDepth; case .coefficient: .coefficientDepth }
    }
    var base: Base
    let domain: OriginalSingularFieldRoot.AdmissionDomain

    mutating func visitExactCell(depth: Int) throws { try domain.visit(depth, usage: &base) }
    mutating func visitCoefficientCell(depth: Int) throws { try base.visitCoefficientCell(depth: depth) }
    mutating func consumeExactWork(_ count: Int) throws { try base.consumeExactWork(count) }
    mutating func retainExactStorage(_ count: Int) throws { try base.retainExactStorage(count) }
}
