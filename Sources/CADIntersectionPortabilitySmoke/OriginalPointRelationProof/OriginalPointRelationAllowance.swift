import CADCore
import Synchronization

@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
final class OriginalPointRelationAllowance: Sendable {
    private struct State { var work = 0; var storage = 0; var storageCalls = 0 }
    private let state = Mutex(State())
    private let maximumWork: Int
    private let maximumStorage: Int

    init(work: Int = 80_000_000, storage: Int = 1_073_741_824) {
        maximumWork = work
        maximumStorage = storage
    }

    func consumeWork(_ count: Int = 1) throws { try debit(work: count, storage: 0) }
    func consumeStorage(_ count: Int) throws { try debit(work: 0, storage: count, storageCall: true) }

    func consumeWordStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Portable UInt32 storage conversion overflowed.")
        }
        try consumeStorage(bytes.partialValue)
    }

    var counts: (work: Int, storage: Int, storageCalls: Int) {
        state.withLock { ($0.work, $0.storage, $0.storageCalls) }
    }

    private func debit(work: Int, storage: Int, storageCall: Bool = false) throws {
        try state.withLock { value in
            guard work >= 0, storage >= 0,
                work <= maximumWork - value.work,
                storage <= maximumStorage - value.storage else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: nil, message: "Portable original point allowance exhausted.")
            }
            let calls = value.storageCalls.addingReportingOverflow(storageCall ? 1 : 0)
            guard !calls.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: nil, message: "Portable storage callback count overflowed.")
            }
            value.storageCalls = calls.partialValue
            value.work += work
            value.storage += storage
        }
    }
}
