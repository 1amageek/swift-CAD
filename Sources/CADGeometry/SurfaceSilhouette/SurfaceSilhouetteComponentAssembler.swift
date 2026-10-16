import CADCore

/// Assembles only endpoint identities proved from the original normal field.
struct SurfaceSilhouetteComponentAssembler {
    private struct Endpoint {
        let curve: Int
        let upper: Bool
        let station: Double?
        let periodicKey: Double?
        let point: ExactMonotoneGraphPoint?
    }

    static func components(curves: [OriginalSurfaceSilhouetteCurve],
                           usage: inout OriginalQueryExecution) throws -> [SurfaceSilhouetteComponent] {
        guard !curves.isEmpty else { return [] }
        try RationalAlgebraStorage.retain(curves.count, of: Int.self, usage: &usage)
        var parents = Array(0..<curves.count)
        var endpoints: [Endpoint] = []
        var joins: [SurfaceSilhouetteComponent.Join] = []
        var endpointDegree: [Int: Int] = [:]
        var crossingEndpoints: Set<Int> = []
        func representative(_ value: Int, parents: inout [Int], usage: inout OriginalQueryExecution) throws -> Int {
            var root = value
            while parents[root] != root { try usage.consumeWork(1); root = parents[root] }
            var current = value
            while parents[current] != current {
                try usage.consumeWork(1)
                let next = parents[current]; parents[current] = root; current = next
            }
            return root
        }
        for (index, curve) in curves.enumerated() {
            for side in 0..<2 {
                let upper = side == 1
                let boundary = try curve.boundaryKey(atUpperEnd: upper, usage: &usage)
                let endpoint = Endpoint(curve: index, upper: upper, station: boundary.station,
                    periodicKey: boundary.periodicKey,
                    point: try curve.boundaryPoint(atUpperEnd: upper, usage: &usage))
                for prior in endpoints {
                    try usage.consumeWork(1)
                    guard prior.curve != index || prior.upper != upper else { continue }
                    let previous = curves[prior.curve]
                    let originalPeriodic = try previous.boundaryOriginalAtlasPeriodicIsSame(as: curve,
                        atUpperEnd: prior.upper, otherAtUpperEnd: upper, usage: &usage)
                    let periodic = originalPeriodic || prior.periodicKey != nil && prior.periodicKey == endpoint.periodicKey
                        && prior.station != endpoint.station && previous.freeCoordinate == curve.freeCoordinate
                    if !periodic {
                        guard previous.chart.u.intersects(curve.chart.u),
                              previous.chart.v.intersects(curve.chart.v) else { continue }
                    }
                    if !previous.usesOriginalAtlas, !curve.usesOriginalAtlas,
                        !previous.usesPolynomialCuspParameter, !curve.usesPolynomialCuspParameter,
                        previous.freeCoordinate == curve.freeCoordinate, prior.upper == upper,
                        previous.quadraticBranchOrdinal == curve.quadraticBranchOrdinal { continue }
                    let same = originalPeriodic ? true : try previous.boundaryRootIsSame(as: curve,
                        atUpperEnd: prior.upper, otherAtUpperEnd: upper, periodic: periodic,
                        firstPoint: prior.point, secondPoint: endpoint.point, usage: &usage)
                    guard same else { continue }
                    let firstKey = prior.curve.multipliedReportingOverflow(by: 2)
                    let secondKey = index.multipliedReportingOverflow(by: 2)
                    guard !firstKey.overflow, !secondKey.overflow,
                          firstKey.partialValue < Int.max, secondKey.partialValue < Int.max else {
                        throw failure("Original silhouette endpoint indices overflow.")
                    }
                    let first = firstKey.partialValue + (prior.upper ? 1 : 0)
                    let second = secondKey.partialValue + (upper ? 1 : 0)
                    let crossing = try previous.boundaryCrossingIsCertified(as: curve,
                        point: prior.point, usage: &usage)
                    let tangentOrder = try previous.boundaryTangentContactOrder(as: curve, point: prior.point, usage: &usage)
                    let intersectionMultiplicity = try previous.boundaryBinomialIntersectionMultiplicity(as: curve,
                        atUpperEnd: prior.upper, otherAtUpperEnd: upper, firstPoint: prior.point,
                        secondPoint: endpoint.point, usage: &usage)
                    let originalAtlasStation = try previous.boundaryAtlasStationIsCertified(as: curve,
                        atUpperEnd: prior.upper, otherAtUpperEnd: upper, usage: &usage)
                    let originalAtlasSingular = originalAtlasStation
                        ? try previous.boundaryAtlasIsSingular(atUpperEnd: prior.upper, usage: &usage) : false
                    if endpointDegree[first, default: 0] > 0 || endpointDegree[second, default: 0] > 0 {
                        guard originalAtlasStation || crossing || tangentOrder != nil || intersectionMultiplicity != nil || crossingEndpoints.contains(first) || crossingEndpoints.contains(second) else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Tangent/cusp and
                            // non-coordinate singular vertices still require a
                            // complete original critical branch incidence atlas.
                            throw KernelError(phase: .geometry, code: .intersectionFailure,
                                tolerance: curve.certificationTolerance,
                                message: "Original silhouette multiple endpoint lacks a transverse source crossing certificate.")
                        }
                    }
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteComponent.Join.self, usage: &usage)
                    if originalAtlasStation || crossing || tangentOrder != nil || intersectionMultiplicity != nil {
                        if !crossingEndpoints.contains(first) {
                            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                            crossingEndpoints.insert(first)
                        }
                        if !crossingEndpoints.contains(second) {
                            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                            crossingEndpoints.insert(second)
                        }
                    }
                    if endpointDegree[first] == nil {
                        try RationalAlgebraStorage.retain(1, of: (Int, Int).self, usage: &usage)
                    }
                    if endpointDegree[second] == nil {
                        try RationalAlgebraStorage.retain(1, of: (Int, Int).self, usage: &usage)
                    }
                    guard endpointDegree[first, default: 0] < Int.max,
                          endpointDegree[second, default: 0] < Int.max else { throw failure("Original endpoint valence overflows.") }
                    endpointDegree[first, default: 0] += 1; endpointDegree[second, default: 0] += 1
                    let cusp = try previous.boundaryCuspIsCertified(as: curve, atUpperEnd: prior.upper, usage: &usage)
                    joins.append(.init(kind: crossing ? .transverseCrossing : tangentOrder != nil ? .tangentContact : originalAtlasSingular || intersectionMultiplicity != nil ? .singularIntersection : cusp ? .cusp : .continuation,
                        firstCurve: prior.curve, firstAtUpperEnd: prior.upper,
                        secondCurve: index, secondAtUpperEnd: upper, periodic: periodic, branchContactOrder: tangentOrder, originalIntersectionMultiplicity: intersectionMultiplicity))
                    let a = try representative(prior.curve, parents: &parents, usage: &usage)
                    let b = try representative(index, parents: &parents, usage: &usage)
                    parents[b] = a
                }
                try RationalAlgebraStorage.retain(1, of: Endpoint.self, usage: &usage)
                endpoints.append(endpoint)
            }
        }
        var roots: [Int] = []
        var groups: [Int: [Int]] = [:]
        for index in curves.indices {
            let root = try representative(index, parents: &parents, usage: &usage)
            if groups[root] == nil {
                try RationalAlgebraStorage.retain(1, of: (Int, [Int]).self, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                roots.append(root)
            }
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            groups[root, default: []].append(index)
        }
        var groupedJoins: [Int: [SurfaceSilhouetteComponent.Join]] = [:]
        for join in joins {
            let root = try representative(join.firstCurve, parents: &parents, usage: &usage)
            if groupedJoins[root] == nil {
                try RationalAlgebraStorage.retain(1, of: (Int, [SurfaceSilhouetteComponent.Join]).self, usage: &usage)
            }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteComponent.Join.self, usage: &usage)
            groupedJoins[root, default: []].append(join)
        }
        var result: [SurfaceSilhouetteComponent] = []
        for root in roots {
            let indices = groups[root, default: []]
            var closed = true
            for index in indices {
                try usage.consumeWork(1)
                guard index < Int.max / 2 else { throw failure("Original silhouette component indices overflow.") }
                if endpointDegree[index * 2, default: 0] == 0 || endpointDegree[index * 2 + 1, default: 0] == 0 {
                    closed = false
                }
            }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteComponent.self, usage: &usage)
            result.append(SurfaceSilhouetteComponent(curveIndices: indices,
                joins: groupedJoins[root, default: []], isClosed: closed))
        }
        return result
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: message)
    }
}
