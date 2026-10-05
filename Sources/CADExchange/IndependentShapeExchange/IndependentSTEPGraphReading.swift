import CADCore
import CADIR

/// Reconstructs independent membership and local mappings using original primitive producers.
public protocol IndependentSTEPGraphReading: Sendable {
    func read(entityIDs: [Int], standaloneItemEntityIDs: [Int],
        fields: any STEPFieldReading, ambientOriginalAngularSource: IndependentShapeAngularSource?, ambientOriginalLengthSource: OriginalSTEPLengthSource?, ambientContexts: [IndependentShapeContext], productDefinitions: [Int: AssemblyDefinitionID], bodySources: [Int: SubshapeID], bodySourceGraph: DesignGraph?, standaloneUnits: UnitSystem, tolerance: ModelingTolerance,
        producer: inout any IndependentSTEPGeometryReading, usage: inout IndependentShapeExchangeUsage) throws -> IndependentShapeSource?
}
