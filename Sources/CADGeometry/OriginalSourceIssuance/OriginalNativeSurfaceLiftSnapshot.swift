import CADCore

public struct OriginalNativeSurfaceLiftSnapshot: OriginalSurfaceLiftSourceReading {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<BSplineSurface3D>
    public let originalPcurve: OriginalSourceBinding<BSplineCurve2D>
    init(original: SurfaceLiftCurve3D, surface: OriginalSourceBinding<BSplineSurface3D>,
        pcurve: OriginalSourceBinding<BSplineCurve2D>) {
        self.original = original; originalSurface = surface; originalPcurve = pcurve
    }
}
