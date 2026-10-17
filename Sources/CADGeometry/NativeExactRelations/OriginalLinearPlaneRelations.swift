import CADCore

/// Complete finite authored line / whole selected plane product.
struct OriginalLinearPlaneRelations: OriginalIssuedGraphRelationOwning {
    typealias Base = OriginalExactScalarDomain
    typealias Line = OriginalLinearCurveSnapshot
    typealias Law = OriginalRationalChartReceipt<Line, OriginalLinearChartSelection, Base>
    typealias Cover = OriginalIssuedDomainCover<Line, OriginalLinearChartSelection, Base>
    typealias Family = OriginalIssuedGraphFamily<Line, Law, Cover>

    let first: Family
    let firstGraphs: [OriginalIssuedGraphPreparation<Line, Law>]
    let firstRestrictions: [OriginalLinearPlaneParameterRestriction]
    let second: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>
    let pairs: [OriginalIssuedGraphRelationPair]
    var kind: ExactParametricRelationKind { .curveSurface }
    private let preparation: OriginalGeometryPreparationReceipt

    private init(first: Family, firstGraphs: [OriginalIssuedGraphPreparation<Line, Law>],
        firstRestrictions: [OriginalLinearPlaneParameterRestriction], second: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>,
        pairs: [OriginalIssuedGraphRelationPair], preparation: OriginalGeometryPreparationReceipt) {
        self.first = first; self.firstGraphs = firstGraphs; self.firstRestrictions = firstRestrictions
        self.second = second; self.pairs = pairs; self.preparation = preparation
    }

    static func prepare(first: Family, second: OriginalIssuedPlaneGraph<OriginalPlaneSnapshot>,
        limits: OriginalDomainIdentityLimits, geometryLimits: ExactGeometricRelationLimits,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution) throws -> Self {
        let observed = try a.withPreparationScope { a in
        try a.admitSourceDepth(first.source.sourceDepth)
        try a.admitSourceDepth(second.original.source.sourceDepth)
        try first.admitProof(limits: limits, using: &a)
        try second.admitProof(limits: limits, using: &a)
        guard first.parameterCount == 1, second.graph.parameterCount == 2 else {
            throw NativeExactRelationFailure.invalidDomain
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: first.graphs.count,
            of: OriginalIssuedGraphRelationPair.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: first.graphs.count,
            of: OriginalIssuedGraphPreparation<Line, Law>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: first.graphs.count,
            of: OriginalLinearPlaneParameterRestriction.self))
        var pairs: [OriginalIssuedGraphRelationPair] = []; pairs.reserveCapacity(first.graphs.count)
        var graphs: [OriginalIssuedGraphPreparation<Line, Law>] = []; graphs.reserveCapacity(first.graphs.count)
        var restrictions: [OriginalLinearPlaneParameterRestriction] = []; restrictions.reserveCapacity(first.graphs.count)
        typealias Cells = ExactRealCellDomain<Base>
        let solver = ExactParametricRelationDomain<Base, Cells, ExactRealTopology<Base>>(
            cells: Cells.self, topology: .init(cells: Cells.self))
        for index in first.graphs.indices {
            try a.consumeWork(1)
            let original = first.graphs[index]
            let restriction = try OriginalLinearPlaneParameterRestriction.prepare(original.original,
                plane: second, limits: limits, using: &a)
            let selected: OriginalIssuedGraphPreparation<Line, Law>
            if case .unchanged = restriction.kind { selected = original }
            else {
                selected = try DefaultOriginalIssuedGraphCompiler().compile(binding: restriction.selected,
                    field: second.field, limits: limits, using: &a)
            }
            restrictions.append(restriction); graphs.append(selected)
            if restriction.selected.request.isEmpty || restriction.selectedPlane.original.effective.isEmpty { continue }
            let input = try solver.compile(kind: .curveSurface,
                first: selected.graph, second: restriction.selectedPlane.graph, using: &a)
            let relation = try solver.resolve(input, cellLimits: geometryLimits.cells,
                topologyLimits: geometryLimits.topology, using: &a)
            pairs.append(try .solved(firstGraphIndex: index, secondGraphIndex: 0,
                relation: relation, using: &a))
        }
        try a.checkpoint()
        return (graphs: graphs, restrictions: restrictions, pairs: pairs)
        }
        let preparation = try OriginalGeometryPreparationReceipt(tolerance: tolerance, depth: observed.depth, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        try a.checkpoint()
        return .init(first: first, firstGraphs: observed.result.graphs,
            firstRestrictions: observed.result.restrictions, second: second,
            pairs: observed.result.pairs, preparation: preparation)
    }

    func admitProof(limits: OriginalDomainIdentityLimits,
        using a: inout OriginalQueryExecution) throws {
        try a.checkpoint()
        try a.admitSourceDepth(preparation.depth.sourceDepth)
        try a.admitDepth(value: preparation.depth.scalar.value, coefficient: preparation.depth.scalar.coefficient)
        try a.admitGeometricDepth(preparation.depth.geometricDepth)
        try a.admitTransportDepth(preparation.depth.transportDepth)
        try preparation.withContributionScopes(using: &a) { a in
        try preparation.admit(tolerance: preparation.tolerance, using: &a)
        try first.source.require(limits.source); try second.original.source.require(limits.source)
        try a.admitSourceDepth(first.source.sourceDepth)
        try a.admitSourceDepth(second.original.source.sourceDepth)
        try first.admitProof(limits: limits, using: &a)
        try second.admitProof(limits: limits, using: &a)
        guard firstGraphs.count == first.graphs.count, firstRestrictions.count == first.graphs.count else {
            throw NativeExactRelationFailure.invalidDomain
        }
        for index in firstGraphs.indices {
            try a.consumeWork(1)
            try firstRestrictions[index].admitProof(limits: limits, using: &a)
            try firstGraphs[index].admitProof(limits: limits, using: &a)
        }
        for pair in pairs { try a.consumeWork(1); try pair.relation.admitProof(using: &a) }
        try a.checkpoint()
        }
    }
}
