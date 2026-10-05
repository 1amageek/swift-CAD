/// Parent-owned original directory/Hollerith parser, shared with exact IGES geometry.
public protocol IndependentIGESFieldReading: Sendable {
    func entity(_ pointer: Int) throws -> IndependentIGESEntity
    func string(_ token: String) throws -> String
    func integer(_ token: String) throws -> Int
    func number(_ token: String) throws -> Double
}
