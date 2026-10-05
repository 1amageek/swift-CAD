import CADCore
import CADGeometry
import CADIR

/// Original native knot endpoints; they are not rounded normalized source endpoints.
public struct OriginalSurfaceTrimSpanGeometry: Sendable, Hashable {
    public let reference: SurfaceTrimSpanReference
    public let trim: ResolvedOriginalSurfaceTrim
    public let lowerParameter: Double
    public let upperParameter: Double
    public let nativeDomain: ParameterDomain

    package init(reference: SurfaceTrimSpanReference, trim: ResolvedOriginalSurfaceTrim,
        lowerParameter: Double, upperParameter: Double, nativeDomain: ParameterDomain) {
        self.reference = reference; self.trim = trim
        self.lowerParameter = lowerParameter; self.upperParameter = upperParameter
        self.nativeDomain = nativeDomain
    }
}
