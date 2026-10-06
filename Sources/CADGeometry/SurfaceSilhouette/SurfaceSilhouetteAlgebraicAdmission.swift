/// Borrows the invocation counters while preserving independent coefficient depth.
struct SurfaceSilhouetteAlgebraicAdmission: RationalAlgebraAdmitting {
    var usage: SurfaceSilhouetteUsage
    mutating func visitExactCell(depth: Int) throws { try usage.consumeCell(depth: depth) }
    mutating func visitCoefficientCell(depth: Int) throws { try usage.consumeAlgebraicCell(depth: depth) }
    mutating func consumeExactWork(_ count: Int) throws { try usage.consumeWork(count) }
    mutating func retainExactStorage(_ count: Int) throws { try usage.retain(count) }
}
