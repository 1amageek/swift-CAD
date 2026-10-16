/// Query-local proof recording; this storage is neither an admission nor a budget.
public struct ExactScalarProofScopes: ~Copyable, Sendable {
    private struct Frame: Sendable {
        let serial: Int
        let mapping: ExactScalarProofScopeMapping
        var reached: ExactScalarDepth
        let maximumWorkUnits: Int?
        var workUnits = 0
    }
    private var owner: ExactScalarProofScopeOwner?
    private var frames: [Frame] = []
    private var serial = 0
    private var reserved = 0
    public private(set) var lastWorkRejection: (used: Int, limit: Int, requested: Int)?
    public init() {}
    public var depth: ExactScalarDepth { frames.last?.reached ?? .zero }
    public var exactDepthResource: ExactResource {
        frames.contains(where: { $0.mapping.valueAxis == .coefficient }) ? .coefficientDepth : .valueDepth
    }

    /// Storage is admitted before the first owner or a larger frame buffer exists.
    func openingStorageBytes() throws(ExactScalarFailure) -> Int {
        guard serial<Int.max else { throw .countOverflow }
        var bytes=0
        if owner == nil {
            let header=try exactScalarPayloadBytes(count:2,of:UnsafeRawPointer.self)
            bytes=try exactScalarCount(header,MemoryLayout<ExactScalarProofScopeOwner>.stride)
        }
        if frames.count==reserved {
            let next=reserved == 0 ? 1:try exactScalarCount(reserved,2,multiply:true)
            let payload=try exactScalarPayloadBytes(count:next,of:Frame.self)
            let header=try exactScalarPayloadBytes(count:4,of:UnsafeRawPointer.self)
            bytes=try exactScalarCount(bytes,exactScalarCount(payload,header))
        }
        return bytes
    }
    mutating func open(_ mapping: ExactScalarProofScopeMapping, maximumWorkUnits: Int?) throws(ExactScalarFailure) -> ExactScalarProofScopeToken {
        guard serial<Int.max else { throw .countOverflow }
        if owner == nil { owner=ExactScalarProofScopeOwner() }
        if frames.count==reserved {
            reserved=reserved == 0 ? 1:try exactScalarCount(reserved,2,multiply:true)
            frames.reserveCapacity(reserved)
        }
        serial += 1
        frames.append(.init(serial:serial,mapping:mapping,reached:mapping.inherited,maximumWorkUnits:maximumWorkUnits))
        return .init(owner:owner!,serial:serial)
    }
    /// No allocation, resource callback or cancellation check occurs on close.
    mutating func close(_ token: ExactScalarProofScopeToken) throws(ExactScalarFailure) -> ExactScalarDepth {
        guard let owner,owner === token.owner,let last=frames.last,last.serial==token.serial else { throw .invalidEvidence }
        frames.removeLast()
        return last.reached
    }
    /// Failure cleanup also discards unclosed descendant scopes without callbacks.
    mutating func unwind(_ token:ExactScalarProofScopeToken) throws(ExactScalarFailure) {
        guard let owner,owner === token.owner else { throw .invalidEvidence }
        guard let index=frames.lastIndex(where: { $0.serial==token.serial }) else { throw .invalidEvidence }
        frames.removeLast(frames.count-index)
    }
    /// Validate every local observation before the original admission debits work.
    public mutating func checkWork(_ units: Int) throws(ExactScalarFailure) {
        lastWorkRejection = nil
        guard units >= 0 else { throw .countOverflow }
        for frame in frames {
            let next = frame.workUnits.addingReportingOverflow(units)
            guard !next.overflow else { throw .countOverflow }
            if let maximum = frame.maximumWorkUnits, next.partialValue > maximum {
                lastWorkRejection = (frame.workUnits, maximum, units)
                throw .resourceLimit(.work)
            }
        }
    }
    /// The original work debit succeeded after checkWork; no allocation or callback.
    public mutating func recordWork(_ units: Int) {
        for index in frames.indices { frames[index].workUnits += units }
    }
    public func mapped(value:Int,coefficient:Int) throws(ExactScalarFailure) -> ExactScalarDepth {
        guard value>=0,coefficient>=0 else { throw .countOverflow }
        var event=ExactScalarDepth(uncheckedValue:value,coefficient:coefficient)
        for frame in frames.reversed() { event=try frame.mapping.applying(event) }
        return event
    }
    public mutating func record(value:Int,coefficient:Int) throws(ExactScalarFailure) {
        _=try mapped(value:value,coefficient:coefficient)
        var event=try ExactScalarDepth(value:value,coefficient:coefficient)
        for index in frames.indices.reversed() {
            event=try frames[index].mapping.applying(event)
            frames[index].reached = .init(uncheckedValue:max(frames[index].reached.value,event.value),
                coefficient:max(frames[index].reached.coefficient,event.coefficient))
        }
    }
}
