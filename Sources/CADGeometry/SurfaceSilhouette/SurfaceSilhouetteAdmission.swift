import CADCore

/// Actual work and byte admission supplied by an enclosing live invocation.
public struct SurfaceSilhouetteAdmission: Sendable {
    private let identity: SurfaceSilhouetteAdmissionIdentity
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: @Sendable (Int) throws -> Void
    let consumeCell: (@Sendable () throws -> Void)?

    public init(consumeWork: @escaping @Sendable (Int) throws -> Void,
                consumeStorage: @escaping @Sendable (Int) throws -> Void,
                consumeCell: (@Sendable () throws -> Void)? = nil) throws {
        let bytes = try rationalAlgebraCount(2, MemoryLayout<UnsafeRawPointer>.stride, multiply: true)
        let words = try rationalAlgebraCount(bytes, MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
        try Task.checkCancellation()
        try consumeWork(words)
        try consumeStorage(bytes)
        identity = SurfaceSilhouetteAdmissionIdentity()
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.consumeCell = consumeCell
    }

    func sharesIdentity(with other: Self) -> Bool { identity === other.identity }
}
