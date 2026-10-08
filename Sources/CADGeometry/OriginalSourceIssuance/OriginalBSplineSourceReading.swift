#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Read-only native data from a validated immutable original snapshot.
/// Accessors are constant-time; control storage is U-fastest for tensor surfaces.
/// Providers establish finite controls/knots, positive weights and degree, exact
/// counts/layout, nondecreasing knots and a nonempty native interval. Interior
/// multiplicity is at most degree, so each positive span has a closed continuous
/// local law. These are conformance obligations, not consequences of Sendable.
public protocol OriginalBSplineSourceReading: Sendable {
    var parameterCount: Int { get }
    func degree(in axis: Int) -> Int
    func controlCount(in axis: Int) -> Int
    func knotCount(in axis: Int) -> Int
    func isPeriodic(in axis: Int) -> Bool
    func knot(at index: Int, in axis: Int) -> Double
    func coordinate(ofControl index: Int, in axis: Int) -> Double
    func weight(ofControl index: Int) -> Double
}
