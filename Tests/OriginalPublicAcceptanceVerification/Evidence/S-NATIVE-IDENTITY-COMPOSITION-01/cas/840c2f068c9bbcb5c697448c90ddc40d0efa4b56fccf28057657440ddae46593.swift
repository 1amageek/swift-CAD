#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

extension ExactParametricRelationDomain: ExactParametricRelationResolving {
    public func resolve<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactParametricRelationSource<Base>,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricRelation<Base> {
        do {
            try admission.checkpoint()
            let cells = try Cells(retaining: source.predicate.source, using: &admission)
            let partition = try cells.decompose(source.predicate.source, limits: cellLimits, using: &admission)
            let selection = try cells.select(partition, matching: source.predicate, using: &admission)
            let incidence = try topology.incidence(of: selection, strategy: .automatic, limits: topologyLimits, using: &admission)
            let components = try topology.components(of: incidence, limits: topologyLimits, using: &admission)
            try storage(1, ExactParametricRelation<Base>.self, &admission)
            let result = ExactParametricRelation(original: copy source, components: components)
            try admission.checkpoint()
            return result
        } catch { throw .init(error) }
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>,
        in relation: borrowing ExactParametricRelation<Base>, rootLimits: ExactRealRootLimits,
        using admission: inout A) throws(ExactParametricRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: relation.components.depth.value, coefficient: relation.components.depth.coefficient)
            let selection = relation.selection
            let cells = try Cells(retaining: selection.partition.source, using: &admission)
            let located = try cells.locate(point, in: selection.partition, limits: rootLimits, using: &admission)
            var found = false
            if let located {
                for cell in selection.cells {
                    try admission.consumeWork(1)
                    if cell == located { found = true; break }
                }
            }
            try admission.checkpoint()
            return found
        } catch { throw .init(error) }
    }
}
