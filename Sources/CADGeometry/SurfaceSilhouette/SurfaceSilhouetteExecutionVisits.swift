import CADCore

extension OriginalQueryExecution {
    mutating func visitSilhouetteCell(depth: Int) throws {
        try admitGeometricDepth(depth)
        try consumeCells()
    }
    mutating func visitSilhouetteSource(depth: Int) throws {
        try admitSourceDepth(depth)
        try consumeWork(1)
    }
}
