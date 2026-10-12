#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Family-owned complete original parameter formula. Binary frame entries are
/// the actual primitive's stored/evaluation frame; image equations are not used.
public protocol OriginalAnalyticCoordinateReading: OriginalImageFrameReading {
    var coordinateKind: OriginalAnalyticCoordinateKind { get }
    var firstMagnitude: Double { get }
    var secondMagnitude: Double { get }
    var coneHalfAngle: Double { get }
    func angularMap(axis: Int) -> OriginalSourceAngularMap
    func finiteLowerBound(axis: Int) -> Double?
    func finiteUpperBound(axis: Int) -> Double?
}
