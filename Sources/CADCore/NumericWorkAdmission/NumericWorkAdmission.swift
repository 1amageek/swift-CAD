/// Caller-owned admission for numeric authoring work, without a Core-to-Geometry dependency.
public protocol NumericWorkAdmission: ~Copyable {
    mutating func checkpoint() throws
    mutating func consumeWork(_ units: Int) throws
    mutating func retainStorage(count: Int, stride: Int) throws
}
