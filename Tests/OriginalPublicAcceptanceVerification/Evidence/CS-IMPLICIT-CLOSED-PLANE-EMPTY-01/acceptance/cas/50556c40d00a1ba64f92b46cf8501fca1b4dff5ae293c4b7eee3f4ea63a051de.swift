import CADCore

/// Transfers constant-height Native host authority to the original implicit relation.
public struct DefaultOriginalImplicitHostPlaneSeparationIssuer: OriginalImplicitHostPlaneSeparationIssuing {
    public init() {}

    public func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<OriginalImplicitCurveSnapshot>,
        plane: borrowing OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, OriginalExactScalarDomain>,
        maximumCells: Int, limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalImplicitHostPlaneSeparationReceipt {
        do {
            let source = copy source, plane = copy plane
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
                try a.checkpoint(); try a.consumeWork(64)
                try source.require(limits); try plane.source.require(limits)
                try source.original.first.require(limits); try source.original.second.require(limits)
                guard !source.original.original.cells.isEmpty,
                    source.original.original.cells.count <= maximumCells else {
                    throw OriginalSourceIssuanceFailure.chartLimit
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public implicit exclusion currently
                // proves only a constant-Z bilinear second Native host against unit Z.
                // Other whole-host separation laws must be issued before admitting success.
                guard OriginalImplicitHostExclusionSnapshotProvider.supports(
                    .implicit(source.original.original)),
                    case .bSpline(let first) = source.original.original.firstSurface,
                    case .bSpline(let second) = source.original.original.secondSurface else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                try OriginalImplicitHostExclusionSnapshotProvider.validateCells(
                    source.original.original, first: first, second: second, using: &a)
                let f = plane.field
                let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
                // FIXME(INCOMPLETE_IMPLEMENTATION): This source exclusion has an
                // authored analytic unit-Z target; other plane laws remain unsupported.
                guard case .analytic(.plane(_, _)) = plane.source.original.original,
                    plane.origin.count == 3, plane.normal.count == 3,
                    try f.compare(plane.normal[0], zero, using: &a) == .equal,
                    try f.compare(plane.normal[1], zero, using: &a) == .equal,
                    try f.compare(plane.normal[2], one, using: &a) == .equal else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                func admitPlane(_ values: [OriginalExactScalar],
                    _ a: inout OriginalSourceProofAdmission<A>) throws {
                    for value in values {
                        try a.consumeWork(1); _ = try f.importing(value, using: &a)
                    }
                }
                try admitPlane(plane.origin, &a); try admitPlane(plane.normal, &a)
                try admitPlane(plane.u, &a); try admitPlane(plane.v, &a)
                let host = source.original.second.original
                guard case .closed(let uLower, let uUpper) = host.uDomain,
                    case .closed(let vLower, let vUpper) = host.vDomain else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                let height = try f.binary64(exactly: host.controlPoints[0][0].z, using: &a)
                let planeHeight = try f.importing(plane.origin[2], using: &a)
                let gap = try f.subtracting(height, planeHeight, using: &a)
                guard try f.sign(of: gap, using: &a) != .zero else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: OriginalExactScalar.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: OriginalExactScalar.self))
                var weights: [OriginalExactScalar] = [], homogeneousZ: [OriginalExactScalar] = []
                weights.reserveCapacity(4); homogeneousZ.reserveCapacity(4)
                for row in 0..<2 {
                    for column in 0..<2 {
                        try a.checkpoint(); try a.consumeWork(1)
                        let weight = try f.binary64(exactly: host.weights[row][column], using: &a)
                        let z = try f.binary64(exactly: host.controlPoints[row][column].z, using: &a)
                        guard try f.sign(of: weight, using: &a) == .positive,
                            try f.compare(z, height, using: &a) == .equal else {
                            throw OriginalSourceIssuanceFailure.invalidSource
                        }
                        let weightedZ = try f.multiplying(z, weight, using: &a)
                        guard try f.compare(weightedZ, f.multiplying(height, weight, using: &a), using: &a) == .equal else {
                            throw OriginalSourceIssuanceFailure.unresolvedAuthority
                        }
                        weights.append(weight); homogeneousZ.append(weightedZ)
                    }
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2,
                    of: OriginalSourceParameterInterval<OriginalExactScalar>.self))
                let hostSupport = [OriginalSourceParameterInterval(
                    lower: try f.binary64(exactly: uLower, using: &a),
                    upper: try f.binary64(exactly: uUpper, using: &a)),
                    OriginalSourceParameterInterval(
                    lower: try f.binary64(exactly: vLower, using: &a),
                    upper: try f.binary64(exactly: vUpper, using: &a))]
                let depth = try a.depth
                try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                    of: OriginalImplicitHostPlaneSeparationReceipt.self))
                let result = OriginalImplicitHostPlaneSeparationReceipt(source: source, plane: plane,
                    field: f, support: .init(lower: zero, upper: one), hostSupport: hostSupport,
                    hostWeights: weights, hostHomogeneousZ: homogeneousZ, hostHeight: height,
                    planeHeight: planeHeight, signedGap: gap, proofDepth: depth)
                try a.checkpoint(); return result
            }
        } catch { throw .init(preserving: error) }
    }
}
