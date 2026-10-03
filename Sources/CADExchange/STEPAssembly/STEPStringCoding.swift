/// ISO 10303-21 lexical strings, independent of product and presentation semantics.
public protocol STEPStringCoding: Sendable {
    func decode(_ token: String, limits: STEPStringLimits) throws -> STEPStringResult
    func encode(_ value: String, limits: STEPStringLimits) throws -> STEPStringResult
}
