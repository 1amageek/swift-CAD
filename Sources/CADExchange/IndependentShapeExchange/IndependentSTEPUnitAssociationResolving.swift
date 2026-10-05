import CADCore

/// Selects ambient presentation units while preserving every original representation context.
public protocol IndependentSTEPUnitAssociationResolving: Sendable {
    func resolveOriginal(entityIDs: [Int], primitiveRootEntityIDs: [Int], fields: any STEPFieldReading,
                 producer: inout any IndependentSTEPGeometryReading,
                 usage: inout IndependentShapeExchangeUsage) throws -> IndependentSTEPOriginalUnitAssociation
    func resolve(entityIDs: [Int], primitiveRootEntityIDs: [Int], fields: any STEPFieldReading,
                 producer: inout any IndependentSTEPGeometryReading,
                 usage: inout IndependentShapeExchangeUsage) throws -> UnitSystem
}
