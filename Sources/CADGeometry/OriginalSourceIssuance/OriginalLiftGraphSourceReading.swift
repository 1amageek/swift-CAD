#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original lift child bindings and chart roles, independent of host representation.
public protocol OriginalLiftGraphSourceReading: Sendable {
    associatedtype Surface: Sendable
    associatedtype SurfaceSelection: Sendable
    associatedtype Pcurve: Sendable
    associatedtype PcurveSelection: Sendable
    var originalSurface: OriginalSourceBinding<Surface> { get }
    var originalPcurve: OriginalSourceBinding<Pcurve> { get }
}
