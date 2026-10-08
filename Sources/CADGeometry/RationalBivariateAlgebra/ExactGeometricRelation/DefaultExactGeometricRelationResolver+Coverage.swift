#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricRelationResolver {
    func curveCoverage<A: ExactScalarAdmission & ~Copyable>(_ relation: borrowing ExactParametricRelation<Base>,
        cells: Cells, limits: ExactGeometricRelationLimits, _ a: inout A) throws -> [ExactCurveParameterSpan<Base>] {
        if relation.selection.cells.isEmpty { return [] }
        guard let root = try cells.root(in: relation.selection.partition, using: &a) else {
            throw ExactGeometricRelationFailure.invalidCoverage
        }
        let prefixes = try cells.children(of: root, in: relation.selection.partition, using: &a)
        let capacity = min(limits.maximumProjectionSpans, try ExactGeometryAccess.multiply(prefixes.count, relation.components.count))
        try ExactGeometryAccess.storage(capacity, ExactCurveParameterSpan<Base>.self, &a)
        var spans: [ExactCurveParameterSpan<Base>] = []; spans.reserveCapacity(capacity)
        try ExactGeometryAccess.storage(prefixes.count, Bool.self, &a)
        var selected = Array(repeating: false, count: prefixes.count)
        for component in relation.components.memberRanges.indices {
            for i in selected.indices { try a.consumeWork(1); selected[i] = false }
            for member in relation.components.memberRanges[component] {
                var cell = relation.components.members[member]
                while cell.axis != 0 {
                    try a.consumeWork(1)
                    guard let parent = cell.parent else { throw ExactGeometricRelationFailure.invalidCoverage }
                    cell = parent
                }
                var found = false
                for i in prefixes.indices { try a.consumeWork(1); if prefixes[i] == cell { selected[i] = true; found = true; break } }
                guard found else { throw ExactGeometricRelationFailure.invalidCoverage }
            }
            var index = 0
            while index < selected.count {
                try a.consumeWork(1)
                if !selected[index] { index += 1; continue }
                let first = index
                while index + 1 < selected.count && selected[index + 1] { try a.consumeWork(1); index += 1 }
                let last = index
                guard spans.count < limits.maximumProjectionSpans else { throw ExactGeometricRelationFailure.resultLimit }
                let lo = try cells.definition(of: prefixes[first], in: relation.selection.partition, using: &a)
                let hi = try cells.definition(of: prefixes[last], in: relation.selection.partition, using: &a)
                guard let l = lo.steps.first, let u = hi.steps.first else { throw ExactGeometricRelationFailure.invalidCoverage }
                let lower: ExactCurveParameterBoundary<Base>
                let upper: ExactCurveParameterBoundary<Base>
                let includesLower: Bool, includesUpper: Bool
                if let section = l.section { lower = .root(section); includesLower = true }
                else if let root = l.lower { lower = .root(root); includesLower = false }
                else { lower = .domain(relation.original.predicate.source.domains[0].lower); includesLower = relation.original.predicate.source.domains[0].includesLower }
                if let section = u.section { upper = .root(section); includesUpper = true }
                else if let root = u.upper { upper = .root(root); includesUpper = false }
                else { upper = .domain(relation.original.predicate.source.domains[0].upper); includesUpper = relation.original.predicate.source.domains[0].includesUpper }
                spans.append(.init(sourceComponentOrdinal: component, lower: lower, upper: upper,
                    includesLower: includesLower, includesUpper: includesUpper, firstPrefix: prefixes[first], lastPrefix: prefixes[last]))
                index += 1
            }
        }
        return spans
    }
}
