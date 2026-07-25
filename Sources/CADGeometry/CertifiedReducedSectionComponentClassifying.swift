import CADCore

protocol CertifiedReducedSectionComponentClassifying: Sendable {
    func classification(
        of section: SurfaceSurfaceIntersectionCurve,
        relativeTo curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedReducedSectionComponentClassification
}
