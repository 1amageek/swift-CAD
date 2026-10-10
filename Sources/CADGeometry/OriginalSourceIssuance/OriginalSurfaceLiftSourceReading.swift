#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retained Native children with original pcurve coordinates, not an XYZ image.
public protocol OriginalSurfaceLiftSourceReading: Sendable {
    associatedtype Surface: OriginalBSplineSourceReading
    associatedtype Pcurve: OriginalBSplineSourceReading
    var originalSurface: OriginalSourceBinding<Surface> { get }
    var originalPcurve: OriginalSourceBinding<Pcurve> { get }
}
