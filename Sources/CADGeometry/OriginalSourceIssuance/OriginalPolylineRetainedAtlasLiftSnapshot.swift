import CADCore

/// Retains the original atlas host and the already-prepared Euclidean pcurve.
public struct OriginalPolylineRetainedAtlasLiftSnapshot<H: OriginalRetainedSurfaceSourceReading>: OriginalRetainedAtlasLiftSourceReading
    where H.Field == OriginalExactScalarDomain {
    public let original: SurfaceLiftCurve3D
    public let originalSurface: OriginalSourceBinding<H>
    public let originalPcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>
    init(original: SurfaceLiftCurve3D,surface: OriginalSourceBinding<H>,pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>) {
        self.original=original;originalSurface=surface;originalPcurve=pcurve
    }
}
