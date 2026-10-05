import CADCore
import CADIR

/// Native presentation units and the actual ambient foreign angular coordinate law.
public struct IndependentSTEPOriginalUnitAssociation: Sendable {
    public let ambientContexts: [IndependentShapeContext]
    public let units: UnitSystem
    public let originalLengthSource: OriginalSTEPLengthSource?
    public let originalAngularSource: IndependentShapeAngularSource?
    public init(units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, ambientContexts: [IndependentShapeContext] = [], originalLengthSource: OriginalSTEPLengthSource? = nil) {
        self.originalLengthSource = originalLengthSource; self.ambientContexts = ambientContexts; self.units = units; self.originalAngularSource = originalAngularSource
    }
}
