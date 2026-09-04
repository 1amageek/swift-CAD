import CADCore
import CADIR

public struct DocumentEvaluationConfiguration: Codable, Sendable, Equatable {
    public var tolerance: ModelingTolerance
    public var tessellationOptions: TessellationOptions
    /// The purpose the Mesh artifacts of this evaluation were produced for.
    /// It scopes cache reuse; the kernel never interprets the value.
    public var meshArtifactPurpose: MeshArtifactPurpose
    /// The resource ceilings this evaluation's tessellation was admitted under.
    public var tessellationLimits: TessellationLimits

    public init(
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions,
        meshArtifactPurpose: MeshArtifactPurpose = .unspecified,
        tessellationLimits: TessellationLimits = .standard
    ) {
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
        self.meshArtifactPurpose = meshArtifactPurpose
        self.tessellationLimits = tessellationLimits
    }
}
