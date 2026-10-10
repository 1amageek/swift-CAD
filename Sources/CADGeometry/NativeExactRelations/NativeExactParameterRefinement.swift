#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Complete refinement retaining original L5 cells and their exact L4 correspondence.
public struct NativeExactParameterRefinement: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let raw: ExactParametricRelation<ExactRationalScalarDomain>
    public let pullback: ExactRealCellPullback<ExactRationalScalarDomain>
    init(raw: ExactParametricRelation<ExactRationalScalarDomain>,pullback: ExactRealCellPullback<ExactRationalScalarDomain>) {
        self.raw = raw; self.pullback = pullback
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(localCoordinates: [Field.Value], queryField: Field? = nil,
        rootLimits: ExactRealRootLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: raw.components.depth.value, coefficient: raw.components.depth.coefficient)
            let region = pullback.region
            try admission.admitDepth(value: region.depth.value, coefficient: region.depth.coefficient)
            let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:region.partition.source,using:&admission)
            let field: Field
            if let queryField { field = queryField }
            else { field = try cells.coefficientField(of:region.partition.source,using:&admission) }
            let point = try cells.point(field:field,coordinates:localCoordinates,using:&admission)
            guard let cell = try cells.locate(point,in:region.partition,limits:rootLimits,using:&admission) else { try admission.checkpoint();return false }
            for index in region.cells.indices {
                try admission.consumeWork(1)
                if region.cells[index] == cell {
                    let included = region.included[index]
                    try admission.checkpoint()
                    return included
                }
            }
            throw NativeExactRelationFailure.invalidDomain
        } catch { throw .preserving(error) }
    }
}
