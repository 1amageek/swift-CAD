import CADCore

public enum KernelCapabilities {
    public static let current = KernelCapabilityCatalog(
        capabilities: geometryCapabilities
            + topologyCapabilities
            + modelingFoundationCapabilities
            + modelingBooleanCapabilities
            + modelingSurfaceFoundationCapabilities
            + modelingEditCapabilities
            + modelingCurveSurfaceCapabilities
            + apiCapabilities
            + exchangeCapabilities
    )
}
