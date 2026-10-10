#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original children and chart roles shared by Native and retained pcurve lifts.
public protocol OriginalLiftSourceReading: Sendable {
    associatedtype Surface: OriginalBSplineSourceReading
    associatedtype Pcurve: Sendable
    associatedtype PcurveSelection: Sendable
    var originalSurface: OriginalSourceBinding<Surface> { get }
    var originalPcurve: OriginalSourceBinding<Pcurve> { get }
}
