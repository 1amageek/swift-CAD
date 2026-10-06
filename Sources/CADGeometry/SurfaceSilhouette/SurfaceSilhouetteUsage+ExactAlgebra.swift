/// Exact source arithmetic shares the existing extraction and clipping ledger.
extension SurfaceSilhouetteUsage: RationalAlgebraAdmitting {
    public mutating func visitExactCell(depth: Int) throws { try consumeCell(depth: depth) }
    public mutating func visitCoefficientCell(depth: Int) throws { try consumeAlgebraicCell(depth: depth) }
    public mutating func consumeExactWork(_ count: Int) throws { try consumeWork(count) }
    public mutating func retainExactStorage(_ count: Int) throws { try retain(count) }
}
