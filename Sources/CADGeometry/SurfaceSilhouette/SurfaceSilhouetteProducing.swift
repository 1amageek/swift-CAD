import CADCore

/// Extracts the complete original zero set or fails without publishing a prefix.
public protocol SurfaceSilhouetteProducing: Sendable {
    func silhouette(of surface: Surface3D, over domain: SurfaceParameterBox,
                    view: Vector3D, tolerance: ModelingTolerance,
                    using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteEnvelope
}
