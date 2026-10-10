#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct DefaultExactGeometricGraphRelationResolver<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: ExactGeometricGraphRelationResolving where Base.Source == Base.Value {
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Topology = ExactRealTopology<Base>
    public init() {}

    func prefix(_ cell: ExactRealCellID<Base>, through axis: Int, _ a: inout some ExactScalarAdmission & ~Copyable) throws -> ExactRealCellID<Base> {
        var result = cell
        while result.axis != axis {
            try a.consumeWork(1)
            guard let parent = result.parent else { throw ExactGeometricRelationFailure.invalidCoverage }
            result = parent
        }
        guard result.axis == axis else { throw ExactGeometricRelationFailure.invalidCoverage }
        return result
    }

    public func resolve<A: ExactScalarAdmission & ~Copyable>(_ relation: borrowing ExactParametricGraphRelation<Base>,
        limits: ExactGeometricRelationLimits, using a: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphRelation<Base> {
        do {
            try relation.admitProof(using: &a)
            let original = relation.original, selection = relation.selection
            let count = selection.cells.count, parameters = original.parameterCount
            guard parameters == (original.kind == .curveSurface ? 3 : 4),
                relation.projection.coordinateCount == parameters else { throw ExactGeometricRelationFailure.invalidSourceBinding }
            guard relation.components.count <= limits.topology.maximumComponents else { throw ExactGeometricRelationFailure.resultLimit }
            try ExactGeometryAccess.storage(count, Int.self, &a)
            var components = Array(repeating: -1, count: count)
            var isolated = true
            for i in selection.cells.indices {
                try a.consumeWork(1)
                if selection.cells[i].dimension != 0 { isolated = false }
                for c in relation.components.memberRanges.indices {
                    for m in relation.components.memberRanges[c] {
                        try a.consumeWork(1)
                        if selection.cells[i] == relation.components.members[m] {
                            guard components[i] == -1 else { throw ExactGeometricRelationFailure.invalidCoverage }
                            components[i] = c
                        }
                    }
                }
                guard components[i] >= 0 else { throw ExactGeometricRelationFailure.invalidCoverage }
            }
            var records: [ExactGeometricStratumRecord] = [], ordinals: [Int] = []
            var prefixes: [ExactRealCellID<Base>] = [], proofs: [Polynomial] = []
            var graph: ExactRealCellPullback<Base>?
            var kind: ExactGeometricEvidenceKind = count == 0 ? .empty : .isolatedParameters
            let cells = try Cells(retaining: original.predicate.source, using: &a)
            let field = try cells.coefficientField(of: original.predicate.source, using: &a)
            var curveConstant: Bool? = nil
            var finite = false, constant = false
            if !isolated {
                let first = try mapEvidence(original.first, &a)
                let second = try mapEvidence(original.second, &a)
                let proofCount = try ExactGeometryAccess.add(first.proofs.count, second.proofs.count)
                try ExactGeometryAccess.storage(proofCount, Polynomial.self, &a)
                proofs.reserveCapacity(proofCount)
                for proof in first.proofs { try a.consumeWork(1); proofs.append(proof) }
                for proof in second.proofs { try a.consumeWork(1); proofs.append(proof) }
                constant = first.constant || second.constant
                finite = first.finite && second.finite
                if original.kind == .curveSurface && first.finite { curveConstant = false }
            }
            let affine = !isolated && !constant && !finite && curveConstant == nil
                ? try affineStrata(copy relation, components: components, limits: limits, &a) : nil
            if isolated || constant || finite || curveConstant != nil {
                guard count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                try ExactGeometryAccess.storage(count, ExactGeometricStratumRecord.self, &a)
                try ExactGeometryAccess.storage(count, Int.self, &a)
                records.reserveCapacity(count); ordinals.reserveCapacity(count)
                if !isolated { kind = constant ? .constantImage : finite ? .finiteFiberMaps : .originalCurveImage }
                for i in selection.cells.indices {
                    let cell = selection.cells[i]
                    let image = isolated || constant ? 0 : finite ? cell.dimension : try prefix(cell, through: 0, &a).dimension
                    guard image <= cell.dimension else { throw ExactGeometricRelationFailure.invalidCoverage }
                    records.append(.init(ordinal: records.count, sourceComponentOrdinal: components[i], parameterDimension: cell.dimension,
                        imageDimension: image, fiberDimension: cell.dimension - image))
                    ordinals.append(i)
                }
            } else if let affine {
                kind = .affineRelation; records = affine.records
                try ExactGeometryAccess.storage(records.count, Int.self, &a)
                ordinals.reserveCapacity(records.count)
                for i in selection.cells.indices { try a.consumeWork(1); ordinals.append(i) }
            } else {
                kind = .originalGraph
                let firstPosition = try parameterPosition(original.first, &a)
                let secondPosition = try parameterPosition(original.second, &a)
                let parameterOnly = firstPosition || secondPosition
                let lifted = parameterOnly ? selection : relation.projection.original
                let predicate = try graphPredicate(copy relation, parameterOnly: parameterOnly, second: !firstPosition && secondPosition, field: field, &a)
                let n = lifted.partition.source.variableCount
                try ExactGeometryAccess.storage(n, Int.self, &a)
                var map: [Int] = []; map.reserveCapacity(n)
                for i in 0..<n { try a.consumeWork(1); map.append(i + 3) }
                let pullback = try Topology(cells: Cells.self).refinePullback(of: lifted, onto: predicate, coordinateMap: map,
                    cellLimits: limits.cells, topologyLimits: limits.topology, using: &a)
                graph = pullback
                try ExactGeometryAccess.storage(lifted.cells.count, Int.self, &a)
                var liftParameters = Array(repeating: -1, count: lifted.cells.count)
                if parameterOnly {
                    for i in selection.cells.indices { try a.consumeWork(1); liftParameters[i] = i }
                } else {
                for i in selection.cells.indices {
                    guard let witnesses = relation.projection.liftedCells(forProjectedOrdinal: i) else { throw ExactGeometricRelationFailure.invalidCoverage }
                    for witness in witnesses {
                        for j in lifted.cells.indices {
                            try a.consumeWork(1)
                            if witness == lifted.cells[j] {
                                let previous = liftParameters[j]
                                guard previous < 0 || components[previous] == components[i] else { throw ExactGeometricRelationFailure.invalidCoverage }
                                liftParameters[j] = i
                            }
                        }
                    }
                }
                }
                try ExactGeometryAccess.storage(lifted.cells.count, Bool.self, &a)
                var covered = Array(repeating: false, count: lifted.cells.count)
                for i in pullback.region.cells.indices where pullback.region.included[i] {
                    try a.consumeWork(1)
                    let source = pullback.sourceCellOrdinals[i]
                    guard source >= 0, source < liftParameters.count, liftParameters[source] >= 0 else { throw ExactGeometricRelationFailure.invalidCoverage }
                    covered[source] = true
                    let parameter = liftParameters[source]
                    let parameterPrefix = try prefix(pullback.region.cells[i], through: parameters + 2, &a)
                    var previous: Int? = nil
                    for j in prefixes.indices { try a.consumeWork(1); if prefixes[j] == parameterPrefix { previous = j; break } }
                    if let previous {
                        guard records[previous].sourceComponentOrdinal == components[parameter] else { throw ExactGeometricRelationFailure.invalidCoverage }
                        continue
                    }
                    guard records.count < limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                    let image = try prefix(parameterPrefix, through: 2, &a).dimension
                    guard image <= parameterPrefix.dimension else { throw ExactGeometricRelationFailure.invalidCoverage }
                    try ExactGeometryAccess.storage(1, ExactGeometricStratumRecord.self, &a)
                    try ExactGeometryAccess.storage(1, Int.self, &a)
                    try ExactGeometryAccess.storage(1, ExactRealCellID<Base>.self, &a)
                    records.append(.init(ordinal: records.count, sourceComponentOrdinal: components[parameter],
                        parameterDimension: parameterPrefix.dimension, imageDimension: image,
                        fiberDimension: parameterPrefix.dimension - image))
                    ordinals.append(parameter); prefixes.append(parameterPrefix)
                }
                for present in covered { try a.consumeWork(1); guard present else { throw ExactGeometricRelationFailure.invalidCoverage } }
            }
            let reached = graph?.region.depth ?? affine?.depth ?? relation.depth
            var depth = try ExactScalarDepth(value: max(relation.depth.value, reached.value), coefficient: max(relation.depth.coefficient, reached.coefficient))
            for proof in proofs {
                try a.consumeWork(1)
                depth = try .init(value: max(depth.value, proof.depth.value), coefficient: max(depth.coefficient, proof.depth.coefficient))
            }
            try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try ExactGeometryAccess.storage(1, ExactGeometricGraphRelation<Base>.self, &a)
            let result = ExactGeometricGraphRelation(original: copy relation, evidenceKind: kind, strata: records, graph: graph,
                depth: depth, proofs: proofs, parameterOrdinals: ordinals, graphPrefixes: prefixes)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
