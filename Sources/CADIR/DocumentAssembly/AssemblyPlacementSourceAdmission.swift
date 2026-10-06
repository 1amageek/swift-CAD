import CADGeometry

/// Adapts the existing caller visit contract to original exact work and storage.
struct AssemblyPlacementSourceAdmission: RationalAlgebraAdmitting {
    let maximumDepth: Int
    let consume: () throws -> Void
    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else { throw AssemblyError.resourceLimitExceeded("negative original source work") }
        for _ in 0..<count { try consume() }
    }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw AssemblyError.resourceLimitExceeded("original placement source storage")
        }
        try consumeExactWork(bytes.partialValue)
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumDepth else { throw AssemblyError.resourceLimitExceeded("original placement source depth") }
        try consume()
    }
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }

}
