import CADCore

/// Complete guard authority and original nonlinear witnesses of a rational lift law.
public struct OriginalPolynomialNativeLiftChart: Sendable {
    public let family: OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>
    public let reduction: OriginalPolynomialSurfaceLiftGraphReduction<OriginalNativeSurfaceLiftSnapshot>
    init(family: OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>,
        reduction: OriginalPolynomialSurfaceLiftGraphReduction<OriginalNativeSurfaceLiftSnapshot>) {
        self.family = family
        self.reduction = reduction
    }
}
