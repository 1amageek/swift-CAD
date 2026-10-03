/// Shared lexical contract for STEP entity fields. Semantic interpretation belongs to each consumer.
public protocol STEPFieldReading: Sendable {
    func entity(_ id: Int) throws -> String
    func name(_ id: Int) throws -> String
    func arguments(_ id: Int, component: String?) throws -> [String]
    func split(_ value: String) throws -> [String]
    func reference(_ value: String) throws -> Int
    func list(_ value: String) throws -> [Int]
    func string(_ value: String) throws -> String
    func numbers(_ value: String) throws -> [Double]
}
