import CADCore
import CADGeometry
import Synchronization

/// One target-common owner for every callback in a public real-relation invocation.
@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
final class OriginalRealRelationAllowance: Sendable {
    enum Failure: Error, Equatable { case work, storage, parameter, coefficient, cells, coefficientCells, overflow }
    struct Counts: Sendable {
        var work = 0, bytes = 0, cells = 0, coefficientCells = 0
        var parameterDepth = 0, coefficientDepth = 0, callbacks = 0
    }
    enum Event { case work(Int), storage(Int), parameter(Int), coefficient(Int) }
    private let state = Mutex(Counts())
    private let maximumWork: Int, maximumBytes: Int, maximumCells: Int, maximumCoefficientCells: Int
    private let maximumParameterDepth: Int, maximumCoefficientDepth: Int
    private let cancelAtCallback: Int?

    init(work: Int = 10_000_000, bytes: Int = 40_000_000,
        cells: Int = 100_000, coefficientCells: Int = 100_000,
        parameterDepth: Int = 24, coefficientDepth: Int = 24, cancelAtCallback: Int? = nil) {
        maximumWork = work; maximumBytes = bytes
        maximumCells = cells; maximumCoefficientCells = coefficientCells
        maximumParameterDepth = parameterDepth; maximumCoefficientDepth = coefficientDepth
        self.cancelAtCallback = cancelAtCallback
    }
    var counts: Counts { state.withLock { $0 } }
    var usage: OriginalRelationUsage {
        .init(consumeWork: { try self.admit(.work($0)) },
            retainStorage: { try self.admit(.storage($0)) },
            visitCell: { try self.admit(.parameter($0)) },
            visitCoefficientCell: { try self.admit(.coefficient($0)) })
    }
    private func admit(_ event: Event) throws {
        let cancel = try state.withLock { value in
            switch event {
            case .work(let count):
                guard count >= 0, count <= maximumWork - value.work else { throw Failure.work }
                value.work += count
            case .storage(let words):
                let bytes = words.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
                guard words >= 0, !bytes.overflow else { throw Failure.overflow }
                guard bytes.partialValue <= maximumBytes - value.bytes else { throw Failure.storage }
                value.bytes += bytes.partialValue
            case .parameter(let depth):
                guard depth >= 0, depth <= maximumParameterDepth else { throw Failure.parameter }
                guard value.cells < maximumCells else { throw Failure.cells }
                value.cells += 1; value.parameterDepth = max(value.parameterDepth, depth)
            case .coefficient(let depth):
                guard depth >= 0, depth <= maximumCoefficientDepth else { throw Failure.coefficient }
                guard value.coefficientCells < maximumCoefficientCells else { throw Failure.coefficientCells }
                value.coefficientCells += 1; value.coefficientDepth = max(value.coefficientDepth, depth)
            }
            let next = value.callbacks.addingReportingOverflow(1)
            guard !next.overflow else { throw Failure.overflow }
            value.callbacks = next.partialValue
            return next.partialValue == cancelAtCallback
        }
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
