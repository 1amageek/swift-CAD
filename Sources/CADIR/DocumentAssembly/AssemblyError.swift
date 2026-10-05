import CADCore

public enum AssemblyError: Error, Equatable, Sendable {
    case invalidSource(String)
    case missingDefinition(AssemblyDefinitionID)
    case missingFeature(FeatureID)
    case cycle(AssemblyDefinitionID)
    case invalidPlacement
    case unsupportedOriginalPlacementOperation
    case resourceLimitExceeded(String)
    case unresolvedOutput(FeatureID)
    case inconsistentArtifact(String)
    case identityCollision
}
