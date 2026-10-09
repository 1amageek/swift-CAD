#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Rejects positive or mixed selected relations before exposing isolated output.
public struct DefaultOriginalIssuedRelationResolver<First: Sendable, FirstSelection: Sendable,
    Second: Sendable, SecondSelection: Sendable>: OriginalIssuedRelationResolving {
    public init() {}
    public func resolve<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing OriginalIssuedMapPreparation<First, FirstSelection>,
        second: borrowing OriginalIssuedMapPreparation<Second, SecondSelection>,
        maximumPairs: Int, maximumIsolatedCells: Int, requireDiscrete: Bool,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection> {
        do {
            try admission.checkpoint()
            guard maximumPairs >= 0, maximumIsolatedCells >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            // Enforce the same coefficient policy even when one complete cover excludes all input.
            _ = try first.field.importing(second.field.integer(0, using: &admission), using: &admission)
            let product = first.maps.count.multipliedReportingOverflow(by: second.maps.count)
            guard !product.overflow else { throw ExactScalarFailure.countOverflow }
            guard product.partialValue <= maximumPairs else { throw NativeExactRelationFailure.domain(.chartLimit) }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: product.partialValue, of: OriginalIssuedRelationPair.self))
            var pairs: [OriginalIssuedRelationPair] = []; pairs.reserveCapacity(product.partialValue)
            typealias Cells = ExactRealCellDomain<OriginalExactScalarDomain>
            let domain = ExactParametricRelationDomain<OriginalExactScalarDomain, Cells, ExactRealTopology<OriginalExactScalarDomain>>(
                cells: Cells.self, topology: .init(cells: Cells.self))
            var count = 0, coverage = 0, positive = false
            for i in first.maps.indices {
                for j in second.maps.indices {
                    try admission.consumeWork(1)
                    let source = try domain.compile(kind: kind, first: first.maps[i].map, second: second.maps[j].map, using: &admission)
                    let relation = try domain.resolve(source, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
                    for cell in relation.selection.cells {
                        try admission.consumeWork(1)
                        if cell.dimension > 0 { positive = true }
                        else {
                            let next = count.addingReportingOverflow(1)
                            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                            guard next.partialValue <= maximumIsolatedCells else { throw NativeExactRelationFailure.resultLimit }
                            count = next.partialValue
                        }
                    }
                    let nextCoverage = coverage.addingReportingOverflow(relation.selection.partition.storedCellCount)
                    guard !nextCoverage.overflow else { throw ExactScalarFailure.countOverflow }
                    coverage = nextCoverage.partialValue
                    pairs.append(.init(firstMapIndex: i, secondMapIndex: j, relation: relation))
                }
            }
            guard !requireDiscrete || !positive else { throw NativeExactRelationFailure.nonDiscreteIntersection }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedRelation<First, FirstSelection, Second, SecondSelection>.self))
            let result = OriginalIssuedRelation(kind: kind, first: copy first, second: copy second, pairs: pairs,
                isolatedCellCount: count, coverageCellCount: coverage, hasPositiveDimensionalSolutions: positive)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
