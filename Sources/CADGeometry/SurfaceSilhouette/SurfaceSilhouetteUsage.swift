import CADCore
import Synchronization

/// One live invocation account shared by extraction, preparation and retained queries.
public struct SurfaceSilhouetteUsage: Sendable {
    public let maximumWork: Int
    public let maximumCells: Int
    public let maximumStorage: Int
    public let maximumDepth: Int
    public let maximumAlgebraicDepth: Int
    public let maximumSourceDepth: Int
    private let owner: any SurfaceSilhouetteAccounting
    public func sharesAccountingOwner(with other: Self) -> Bool { owner === other.owner }
    public func sharesAdmission(with admission: SurfaceSilhouetteAdmission) -> Bool {
        owner.sharesAdmission(with: admission)
    }
    public var work: Int { owner.counters.work }
    public var cells: Int { owner.counters.cells }
    public var storage: Int { owner.counters.storage }

    public init(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
                maximumDepth: Int, maximumAlgebraicDepth: Int = 32, maximumSourceDepth: Int = 16, admission: SurfaceSilhouetteAdmission? = nil) throws {
        guard maximumWork > 0, maximumCells > 0, maximumStorage > 0,
              maximumDepth >= 0, maximumAlgebraicDepth >= 0, maximumAlgebraicDepth <= 32, (0...16).contains(maximumSourceDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Silhouette admission requires explicit positive caller limits.")
        }
        self.maximumWork = maximumWork; self.maximumCells = maximumCells
        self.maximumStorage = maximumStorage; self.maximumDepth = maximumDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.maximumSourceDepth = maximumSourceDepth
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) {
            let bytes = try SurfaceSilhouetteSharedAccounting.trackingStorageBytes()
            let words = try rationalAlgebraCount(bytes, MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
            guard words <= maximumStorage, words <= maximumWork else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original silhouette tracking owner exceeds the caller storage or work allowance.")
            }
            try Task.checkCancellation()
            try admission?.consumeWork(words)
            try admission?.consumeStorage(bytes)
            owner = SurfaceSilhouetteSharedAccounting(maximumWork: maximumWork, maximumCells: maximumCells,
                maximumStorage: maximumStorage, maximumDepth: maximumDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, admission: admission, trackingWords: words)
        } else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Original silhouette invocation accounting requires platform Synchronization.Mutex support.")
        }
    }
    public mutating func consumeWork(_ count: Int = 1) throws { try owner.consumeWork(count) }
    public mutating func consumeSourceVisit(depth: Int) throws {
        guard depth >= 0, depth <= maximumSourceDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original silhouette traversal exhausted its independent source depth.")
        }
        try owner.consumeWork(1)
    }
    public mutating func consumeCell(depth: Int) throws { try owner.consumeCell(depth: depth, coefficient: false) }
    mutating func consumeAlgebraicCell(depth: Int) throws { try owner.consumeCell(depth: depth, coefficient: true) }
    public mutating func retain(_ count: Int) throws { try owner.retain(count) }

    /// Each lower callback reports one work visit and its actual geometric proof depth.
    public var preparationProofWorkCallback: @Sendable (Int) throws -> Void {
        let retained = owner
        return { try retained.consumeProofWork(depth: $0) }
    }
    public var preparationWorkCallback: @Sendable () throws -> Void {
        let retained = owner
        return { try retained.consumeWork(1) }
    }
    public var preparationCellCallback: @Sendable (Int) throws -> Void {
        let retained = owner
        return { try retained.consumeCell(depth: $0, coefficient: false) }
    }
    public var preparationCoefficientCellCallback: @Sendable (Int) throws -> Void {
        let retained = owner
        return { try retained.consumeCell(depth: $0, coefficient: true) }
    }
    public var preparationStorageCallback: @Sendable (Int) throws -> Void {
        let retained = owner
        return { bytes in
            guard bytes >= 0 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                    message: "Original silhouette preparation storage must be a nonnegative byte count.")
            }
            try retained.retainBytes(bytes)
        }
    }
}
