#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Defined functions in the original parametric law, not independent unknowns.
public enum OriginalSourceCoordinateFunction<Value: Sendable>: Sendable {
    case authoredCoordinate(axis: Int)
    case intrinsicCosine(axis: Int)
    case intrinsicSine(axis: Int)
    case physicalCosine(axis: Int,gain: Value,offset: Value)
    case physicalSine(axis: Int,gain: Value,offset: Value)
    case hyperbolicCosine(axis: Int)
    case hyperbolicSine(axis: Int)
    case physicalConstantCosine(radians: Double)
    case physicalConstantSine(radians: Double)
}
