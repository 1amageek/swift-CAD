#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Authored affine-in-parameter curve coordinates; the direction is never normalized.
public protocol OriginalLinearSourceReading: Sendable {
    func originCoordinate(in axis: Int) -> Double
    func directionCoordinate(in axis: Int) -> Double
}
