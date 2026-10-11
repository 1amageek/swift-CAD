#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI
#endif

/// Owns source/DI authority and the correspondence to every raw lifted cell.
public struct OriginalIssuedGraphParameterRefinement<S: Sendable,E: Sendable,C: Sendable,T: Sendable,F: Sendable,D: Sendable>: Sendable {
    public let raw: OriginalIssuedGraphRelations<S,E,C,T,F,D>
    public let pairOrdinal: Int
    public let pullback: ExactRealCellPullback<OriginalExactScalarDomain>

    init(raw: OriginalIssuedGraphRelations<S,E,C,T,F,D>, pairOrdinal: Int,
         pullback: ExactRealCellPullback<OriginalExactScalarDomain>) {
        self.raw = raw
        self.pairOrdinal = pairOrdinal
        self.pullback = pullback
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(
        liftedCoordinates: [ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value],
        queryField: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>? = nil,
        limits: OriginalDomainIdentityLimits, rootLimits: ExactRealRootLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            try raw.admitProof(limits: limits, using: &admission)
            let region = pullback.region
            try admission.admitDepth(value: region.depth.value, coefficient: region.depth.coefficient)
            let cells = try ExactRealCellDomain<OriginalExactScalarDomain>(retaining: region.partition.source, using: &admission)
            let field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
            if let queryField { field = queryField }
            else { field = try cells.coefficientField(of: region.partition.source, using: &admission) }
            let point = try cells.point(field: field, coordinates: liftedCoordinates, using: &admission)
            guard let cell = try cells.locate(point, in: region.partition, limits: rootLimits, using: &admission) else {
                try admission.checkpoint()
                return false
            }
            for index in region.cells.indices {
                try admission.consumeWork(1)
                if region.cells[index] == cell {
                    let included = region.included[index]
                    try admission.checkpoint()
                    return included
                }
            }
            throw NativeExactRelationFailure.invalidDomain
        } catch let failure as NativeExactRelationFailure { throw failure }
        catch { throw .preserving(error) }
    }
}
