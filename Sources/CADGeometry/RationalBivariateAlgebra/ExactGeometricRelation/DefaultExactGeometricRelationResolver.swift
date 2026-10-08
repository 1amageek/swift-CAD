#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct DefaultExactGeometricRelationResolver<
    Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,
    Cells: ExactRealCellPreparing & ExactRealCellProducing & ExactRealCellSelecting & ExactRealCellQuerying & ExactRealCellDescribing & ExactRealCellTraversing,
    Topology: ExactRealCellPullbackResolving & ExactRealIncidenceProducing & ExactRealComponentsProducing
>: ExactGeometricRelationResolving, Sendable
where Base.Source == Base.Value, Cells.Base == Base, Topology.Base == Base {
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    let topology: Topology
    public init(cells: Cells.Type, topology: Topology) { self.topology = topology }

    func isolatedSelection<A: ExactScalarAdmission & ~Copyable>(
        _ relation: borrowing ExactParametricRelation<Base>, _ admission: inout A
    ) throws -> Bool {
        for cell in relation.selection.cells {
            try admission.consumeWork(1)
            if cell.dimension != 0 { return false }
        }
        return true
    }

    public func resolve<A: ExactScalarAdmission & ~Copyable>(_ relation: borrowing ExactParametricRelation<Base>,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricRelation<Base> {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: relation.components.depth.value, coefficient: relation.components.depth.coefficient)
            let original = relation.original
            let expected = original.kind == .curveSurface ? 3 : 4
            guard original.predicate.source.variableCount == expected,
                original.first.parameterCount == (original.kind == .curveSurface ? 1 : 2),
                original.second.parameterCount == 2,
                original.first.parameterCount + original.second.parameterCount == expected else {
                throw ExactGeometricRelationFailure.invalidSourceBinding
            }
            let raw = try Cells(retaining: original.predicate.source, using: &admission)
            let field = try raw.coefficientField(of: original.predicate.source, using: &admission)
            guard relation.components.count <= limits.topology.maximumComponents else { throw ExactGeometricRelationFailure.resultLimit }
            try ExactGeometryAccess.storage(relation.selection.cells.count, Int.self, &admission)
            var componentOrdinals = Array(repeating: -1, count: relation.selection.cells.count)
            for i in relation.selection.cells.indices {
                for component in relation.components.memberRanges.indices {
                    for member in relation.components.memberRanges[component] {
                        try admission.consumeWork(1)
                        if relation.selection.cells[i] == relation.components.members[member] {
                            guard componentOrdinals[i] == -1 else { throw ExactGeometricRelationFailure.invalidCoverage }
                            componentOrdinals[i] = component
                        }
                    }
                }
                guard componentOrdinals[i] >= 0 else { throw ExactGeometricRelationFailure.invalidCoverage }
            }
            var kind: ExactGeometricEvidenceKind = .empty
            var proofs: [Polynomial] = []
            var pullback: ExactRealCellPullback<Base>? = nil
            var records: [ExactGeometricStratumRecord] = []
            var sourceOrdinals: [Int] = [], regionOrdinals: [Int] = []
            if !relation.selection.cells.isEmpty {
                if original.kind == .curveSurface {
                    let curve = try constantMap(original.first, &admission)
                    proofs = curve.proofs; kind = .originalCurveImage
                    let count = relation.selection.cells.count
                    guard count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                    try ExactGeometryAccess.storage(count, ExactGeometricStratumRecord.self, &admission)
                    try ExactGeometryAccess.storage(count, Int.self, &admission)
                    records.reserveCapacity(count); sourceOrdinals.reserveCapacity(count)
                    for i in relation.selection.cells.indices {
                        try admission.consumeWork(1)
                        let cell = relation.selection.cells[i]
                        var prefix = cell
                        while prefix.axis != 0 {
                            try admission.consumeWork(1)
                            guard let parent = prefix.parent else { throw ExactGeometricRelationFailure.invalidCoverage }
                            prefix = parent
                        }
                        let image = curve.constant ? 0 : prefix.dimension
                        guard cell.dimension >= image else { throw ExactGeometricRelationFailure.invalidCoverage }
                        records.append(.init(ordinal: i, sourceComponentOrdinal: componentOrdinals[i],
                            parameterDimension: cell.dimension, imageDimension: image, fiberDimension: cell.dimension - image))
                        sourceOrdinals.append(i)
                    }
                } else if try isolatedSelection(relation, &admission) {
                    // The complete finite parameter set has point images and
                    // zero-dimensional fibers under the retained guarded maps.
                    // Equal XYZ values do not identify different source tuples.
                    kind = .isolatedParameters
                    let count = relation.selection.cells.count
                    guard count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                    try ExactGeometryAccess.storage(count, ExactGeometricStratumRecord.self, &admission)
                    try ExactGeometryAccess.storage(count, Int.self, &admission)
                    records.reserveCapacity(count); sourceOrdinals.reserveCapacity(count)
                    for i in relation.selection.cells.indices {
                        try admission.consumeWork(1)
                        records.append(.init(ordinal: i, sourceComponentOrdinal: componentOrdinals[i],
                            parameterDimension: 0, imageDimension: 0, fiberDimension: 0))
                        sourceOrdinals.append(i)
                    }
                } else {
                    let firstConstant = try constantMap(original.first, &admission)
                    let secondConstant = try constantMap(original.second, &admission)
                    let firstInjection = try affineInjection(original.first, &admission)
                    let secondInjection = try affineInjection(original.second, &admission)
                    let firstFinite = try finiteFiberMap(original.first, &admission)
                    let secondFinite = try finiteFiberMap(original.second, &admission)
                    let curveImage = try firstParameterCurve(original.first, &admission)
                    let constant = firstConstant.constant || secondConstant.constant
                    let injection = firstInjection != nil && secondInjection != nil
                    let finite = firstFinite != nil && secondFinite != nil
                    if constant || injection || finite || curveImage != nil {
                        if constant {
                            kind = .constantImage
                            proofs = firstConstant.constant ? firstConstant.proofs : secondConstant.proofs
                        } else if injection {
                            kind = .affineInjection
                            try ExactGeometryAccess.storage(2, Polynomial.self, &admission)
                            proofs = [firstInjection!, secondInjection!]
                        } else if finite {
                            kind = .finiteFiberMaps
                            try ExactGeometryAccess.storage(4, Polynomial.self, &admission)
                            proofs = firstFinite! + secondFinite!
                        } else {
                            kind = .firstParameterCurve; proofs = curveImage!
                        }
                        let count = relation.selection.cells.count
                        guard count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                        try ExactGeometryAccess.storage(count, ExactGeometricStratumRecord.self, &admission)
                        try ExactGeometryAccess.storage(count, Int.self, &admission)
                        records.reserveCapacity(count); sourceOrdinals.reserveCapacity(count)
                        for i in relation.selection.cells.indices {
                            try admission.consumeWork(1)
                            let cell = relation.selection.cells[i], dimension = cell.dimension
                            var image = constant ? 0 : dimension
                            if kind == .firstParameterCurve {
                                var prefix = cell
                                while prefix.axis != 0 {
                                    try admission.consumeWork(1)
                                    guard let parent = prefix.parent else { throw ExactGeometricRelationFailure.invalidCoverage }
                                    prefix = parent
                                }
                                image = prefix.dimension
                            }
                            guard image <= dimension else { throw ExactGeometricRelationFailure.invalidCoverage }
                            records.append(.init(ordinal: i, sourceComponentOrdinal: componentOrdinals[i],
                                parameterDimension: dimension, imageDimension: image, fiberDimension: dimension - image))
                            sourceOrdinals.append(i)
                        }
                    } else {
                        kind = .originalGraph
                        let graph = try graphPredicate(original, field: field, &admission)
                        try ExactGeometryAccess.storage(expected, Int.self, &admission)
                        var map: [Int] = []; map.reserveCapacity(expected)
                        for i in 0..<expected { try admission.consumeWork(1); map.append(i + 3) }
                        let p = try topology.refinePullback(of: relation.selection, onto: graph, coordinateMap: map,
                            cellLimits: limits.cells, topologyLimits: limits.topology, using: &admission)
                        pullback = p
                        var count = 0
                        for included in p.region.included { try admission.consumeWork(1); if included { count = try ExactGeometryAccess.add(count, 1) } }
                        guard count <= limits.maximumStrata else { throw ExactGeometricRelationFailure.resultLimit }
                        try ExactGeometryAccess.storage(count, ExactGeometricStratumRecord.self, &admission)
                        try ExactGeometryAccess.storage(count, Int.self, &admission)
                        try ExactGeometryAccess.storage(count, Int.self, &admission)
                        records.reserveCapacity(count); sourceOrdinals.reserveCapacity(count); regionOrdinals.reserveCapacity(count)
                        try ExactGeometryAccess.storage(componentOrdinals.count, Bool.self, &admission)
                        var covered = Array(repeating: false, count: componentOrdinals.count)
                        for i in p.region.cells.indices where p.region.included[i] {
                            try admission.consumeWork(1)
                            let cell = p.region.cells[i]
                            guard cell.axis == expected + 2 else { throw ExactGeometricRelationFailure.invalidCoverage }
                            var prefix = cell
                            while prefix.axis != 2 {
                                try admission.consumeWork(1)
                                guard let parent = prefix.parent else { throw ExactGeometricRelationFailure.invalidCoverage }
                                prefix = parent
                            }
                            let source = p.sourceCellOrdinals[i]
                            guard source >= 0, source < componentOrdinals.count, cell.dimension >= prefix.dimension else { throw ExactGeometricRelationFailure.invalidCoverage }
                            records.append(.init(ordinal: records.count, sourceComponentOrdinal: componentOrdinals[source],
                                parameterDimension: cell.dimension, imageDimension: prefix.dimension,
                                fiberDimension: cell.dimension - prefix.dimension))
                            covered[source] = true
                            sourceOrdinals.append(source); regionOrdinals.append(i)
                        }
                        for present in covered { try admission.consumeWork(1); guard present else { throw ExactGeometricRelationFailure.invalidCoverage } }
                    }
                }
            }
            let spans = original.kind == .curveSurface
                ? try curveCoverage(relation, cells: raw, limits: limits, &admission) : []
            var depth = pullback?.region.depth ?? relation.components.depth
            for proof in proofs {
                try admission.consumeWork(1)
                depth = try .init(value: max(depth.value, proof.depth.value), coefficient: max(depth.coefficient, proof.depth.coefficient))
            }
            for span in spans {
                for side in 0..<2 {
                    try admission.consumeWork(1)
                    let boundary = side == 0 ? span.lower : span.upper
                    if case .root(let root) = boundary {
                        depth = try .init(value: max(depth.value, root.depth.value), coefficient: max(depth.coefficient, root.depth.coefficient))
                    }
                }
            }
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try ExactGeometryAccess.storage(1, ExactGeometricRelationPayload<Base>.self, &admission)
            // Account the immutable class header separately from typed payload storage.
            try ExactGeometryAccess.storage(2, Int.self, &admission)
            let payload = ExactGeometricRelationPayload(original: copy relation, kind: kind, proofs: proofs,
                pullback: pullback, records: records, sourceOrdinals: sourceOrdinals,
                regionOrdinals: regionOrdinals, spans: spans, depth: depth)
            let result = ExactGeometricRelation(owner: ExactGeometricRelationStorage(payload))
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
