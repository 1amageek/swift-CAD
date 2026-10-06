/// Immutable admission into a complete caller invocation, with explicit units.
public struct OriginalCurveContactAdmission: Sendable {
    private let work: @Sendable (Int) throws -> Void
    private let storage: @Sendable (Int) throws -> Void

    public init(consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void) {
        work = consumeWork; storage = consumeStorage
    }

    package func chargeWork(_ units: Int) throws { try work(units) }
    package func chargeStorage(bytes: Int) throws { try storage(bytes) }
}
