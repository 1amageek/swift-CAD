#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI
import SourceIssuer
import OriginalCoordinateTransfer
#endif

/// Complete source/domain/solution owners survive independently of the caller's inputs.
public struct OriginalIssuedCurveSurfacePointSet<First: Sendable, FirstSelection: Sendable,
    Second: Sendable, SecondSelection: Sendable>: Sendable {
    public let relation: OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>
    public let coordinates: ExactOriginalScalarTransferReceipt
    public let points: [OriginalIssuedCurveSurfacePoint]
    public let proofDepth: ExactScalarDepth
    public let incidences: [OriginalIssuedCurveSurfacePointIncidence]
    init(relation: OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>,
        coordinates: ExactOriginalScalarTransferReceipt, points: [OriginalIssuedCurveSurfacePoint],
        incidences: [OriginalIssuedCurveSurfacePointIncidence], proofDepth: ExactScalarDepth) {
        self.relation = relation; self.coordinates = coordinates; self.points = points; self.incidences = incidences; self.proofDepth = proofDepth
    }
}
