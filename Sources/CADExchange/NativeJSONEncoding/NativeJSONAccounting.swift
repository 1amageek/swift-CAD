import CADCore

/// One existing invocation's JSON token admission; implementations never reset counters.
protocol NativeJSONAccounting: Sendable {
    var limits: ExchangeResourceLimits { get }
    var format: ExchangeFileFormat { get }
    var byteCount: Int { get }
    func checkTime() throws
    func validateNestingDepth(_ depth: Int) throws
    func charge(entities: Int, work: Int, bytes: Int) throws
    func recordIterations() throws
    func recordIterations(_ count: Int) throws
    func recordBytes(_ count: Int) throws
    func recordBytes(_ count: Int, label: String) throws
}

extension NativeJSONAccounting {
    func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try charge(entities: entities, work: work, bytes: bytes)
    }
    func recordIterations() throws { try recordIterations(1) }
    func recordBytes(_ count: Int) throws { try recordBytes(count, label: "processed") }
}

extension SharedExchangeResourceAccountant: NativeJSONAccounting {}
