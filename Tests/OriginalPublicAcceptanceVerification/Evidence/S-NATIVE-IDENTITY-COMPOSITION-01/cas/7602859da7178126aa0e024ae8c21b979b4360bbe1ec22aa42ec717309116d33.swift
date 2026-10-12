#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original intrinsic revolution of the retained normalized generator, v in [0,1].
public protocol OriginalRevolutionSourceReading: Sendable {
    associatedtype Generator: Sendable
    var originalGenerator: OriginalSourceBinding<Generator> { get }
    var originalLowerU: Double { get }
    var originalUpperU: Double { get }
    func axisOriginCoordinate(in axis: Int) -> Double
    func axisDirectionCoordinate(in axis: Int) -> Double
}
