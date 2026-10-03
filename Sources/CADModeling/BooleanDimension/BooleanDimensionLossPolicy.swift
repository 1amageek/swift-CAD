/// Semantic exclusions and source retention; this is not measured geometric loss.
public struct BooleanDimensionLossPolicy: Sendable, Equatable {
    public enum SliceToolRegions: Sendable, Equatable {
        case notApplicable
        case includedForDefaultSolidInputs
        case notGeneratedInCurrentEnvelope
    }

    /// Boundary edges and vertices remain owned by the result body; standalone
    /// lower-dimensional contacts are excluded from this regularized result.
    public let returnsStandaloneLowerDimensionalContacts: Bool
    public let replacesTargetIdentities: Bool
    public let retainsOriginalTools: Bool
    public let sliceToolRegions: SliceToolRegions

    init(keepTools: Bool, sliceToolRegions: SliceToolRegions) {
        returnsStandaloneLowerDimensionalContacts = false
        replacesTargetIdentities = true
        retainsOriginalTools = keepTools
        self.sliceToolRegions = sliceToolRegions
    }
}
