import CADCore
import Synchronization

/// One immutable invocation owner with identical synchronization on every target.
@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
final class SurfaceSilhouetteSharedAccounting: SurfaceSilhouetteAccounting, Sendable {
    private struct State: Sendable {
        var work: Int
        var cells: Int
        var storage: Int
    }
    private let maximumWork: Int
    private let maximumCells: Int
    private let maximumStorage: Int
    private let maximumDepth: Int
    private let maximumAlgebraicDepth: Int
    private let admission: SurfaceSilhouetteAdmission?
    private let state: Mutex<State>

    static func trackingStorageBytes() throws -> Int {
        let payload = try rationalAlgebraCount(MemoryLayout<Mutex<State>>.stride,
            rationalAlgebraCount(5, MemoryLayout<Int>.stride, multiply: true))
        let callbackPayload = try rationalAlgebraCount(payload, MemoryLayout<SurfaceSilhouetteAdmission?>.stride)
        return try rationalAlgebraCount(callbackPayload,
            rationalAlgebraCount(3, MemoryLayout<UnsafeRawPointer>.stride, multiply: true))
    }

    init(maximumWork: Int, maximumCells: Int, maximumStorage: Int,
        maximumDepth: Int, maximumAlgebraicDepth: Int,
        admission: SurfaceSilhouetteAdmission?, trackingWords: Int) {
        self.admission = admission
        self.maximumWork = maximumWork; self.maximumCells = maximumCells; self.maximumStorage = maximumStorage
        self.maximumDepth = maximumDepth; self.maximumAlgebraicDepth = maximumAlgebraicDepth
        state = Mutex(State(work: trackingWords, cells: 0, storage: trackingWords))
    }
    func sharesAdmission(with other: SurfaceSilhouetteAdmission) -> Bool {
        guard let admission else { return false }
        return admission.sharesIdentity(with: other)
    }
    var counters: (work: Int, cells: Int, storage: Int) {
        state.withLock { ($0.work, $0.cells, $0.storage) }
    }
    func consumeWork(_ count: Int) throws {
        try Task.checkCancellation()
        try state.withLock { value in
            guard count >= 0, count <= maximumWork - value.work else { throw Self.exhausted("work") }
            value.work += count
        }
        try admission?.consumeWork(count)
    }
    func consumeCell(depth: Int, coefficient: Bool) throws {
        try consumeWork(1)
        try state.withLock { value in
            let limit = coefficient ? maximumAlgebraicDepth : maximumDepth
            guard depth >= 0, depth <= limit, value.cells < maximumCells else {
                throw Self.exhausted(coefficient ? "algebraic cells or depth" : "cells or depth")
            }
            value.cells += 1
        }
        try admission?.consumeCell?()
    }
    func consumeProofWork(depth: Int) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= maximumDepth else { throw Self.exhausted("proof depth") }
        try consumeWork(1)
    }
    func retain(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw Self.exhausted("storage byte conversion") }
        try retainBytes(bytes.partialValue)
    }
    func retainBytes(_ bytes: Int) throws {
        guard bytes >= 0 else { throw Self.exhausted("negative storage") }
        let count = try rationalAlgebraCount(bytes, MemoryLayout<UInt32>.stride - 1) / MemoryLayout<UInt32>.stride
        try consumeWork(count)
        try state.withLock { value in
            guard count <= maximumStorage - value.storage else { throw Self.exhausted("storage") }
            value.storage += count
        }
        try admission?.consumeStorage(bytes)
    }
    private static func exhausted(_ resource: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
            message: "Original silhouette exhausted its cumulative caller \(resource) allowance.")
    }
}
