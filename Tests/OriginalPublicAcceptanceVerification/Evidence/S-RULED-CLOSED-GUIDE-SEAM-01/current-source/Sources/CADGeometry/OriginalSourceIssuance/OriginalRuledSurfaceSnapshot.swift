import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.RuledSurface3D
import L0
import SourceIssuer
#endif

/// The original ruled value and the exact two descendant bindings it owns.
public struct OriginalRuledSurfaceSnapshot<First: Sendable, Second: Sendable>: OriginalRuledSourceReading {
    public let original: RuledSurface3D
    public let firstBoundary: OriginalSourceBinding<First>
    public let secondBoundary: OriginalSourceBinding<Second>
    public let originalLowerU: Double
    public let originalUpperU: Double
    init(original: RuledSurface3D, first: OriginalSourceBinding<First>, second: OriginalSourceBinding<Second>,
        lower: Double, upper: Double) {
        self.original = original; firstBoundary = first; secondBoundary = second
        originalLowerU = lower; originalUpperU = upper
    }
}
