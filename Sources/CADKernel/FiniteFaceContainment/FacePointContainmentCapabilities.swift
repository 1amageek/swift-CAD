/// Immutable access to a provider's module-owned preparation witnesses.
public struct FacePointContainmentCapabilities: Sendable {
    let pointCaching: (any FacePointContainmentPreparationCaching)?
    let parameterCaching: (any FaceParameterContainmentPreparationCaching)?

    /// Preserves direct point dispatch for providers without preparation witnesses.
    public init() {
        pointCaching = nil
        parameterCaching = nil
    }

    init(pointCaching: any FacePointContainmentPreparationCaching,
         parameterCaching: any FaceParameterContainmentPreparationCaching) {
        self.pointCaching = pointCaching
        self.parameterCaching = parameterCaching
    }
}
