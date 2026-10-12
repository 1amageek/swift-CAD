import CADCore

/// Retains whole-host exclusion authority without selecting a positive curve graph.
public struct OriginalImplicitHostExclusionSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    public static func supports(_ input: borrowing Curve3D) -> Bool {
        guard case .implicit(let curve) = copy input, !curve.cells.isEmpty,
            case .bSpline(let first) = curve.firstSurface,
            case .bSpline(let second) = curve.secondSurface,
            !first.isUPeriodic, !first.isVPeriodic,
            !second.isUPeriodic, !second.isVPeriodic,
            second.uDegree == 1, second.vDegree == 1,
            second.controlPoints.count == 2, second.weights.count == 2,
            second.controlPoints[0].count == 2, second.controlPoints[1].count == 2,
            second.weights[0].count == 2, second.weights[1].count == 2 else { return false }
        let height = second.controlPoints[0][0].z
        guard height.isFinite else { return false }
        for row in 0..<2 {
            for column in 0..<2 {
                let point = second.controlPoints[row][column]
                let weight = second.weights[row][column]
                guard point.x.isFinite, point.y.isFinite, point.z == height,
                    weight.isFinite, weight > 0 else { return false }
            }
        }
        return true
    }

    public static func supports(curve: borrowing Curve3D, plane: borrowing Surface3D) -> Bool {
        guard supports(curve), case .implicit(let original) = copy curve,
            case .bSpline(let host) = original.secondSurface,
            case .analytic(.plane(let origin, let normal)) = copy plane else { return false }
        return origin.x.isFinite && origin.y.isFinite && origin.z.isFinite
            && normal.x == 0 && normal.y == 0 && normal.z == 1
            && origin.z != host.controlPoints[0][0].z
    }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalImplicitCurveSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(64)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary implicit exclusion route
            // admits only this constant-Z bilinear second Native host and unit-Z plane.
            // Other source profiles require whole-host exclusion authority before success.
            guard Self.supports(input), case .implicit(let curve) = copy input,
                case .bSpline(let first) = curve.firstSurface,
                case .bSpline(let second) = curve.secondSurface else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try curve.validateCertificationContract(tolerance: tolerance)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            let binder = DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance))
            let firstBinding = try binder.bind(first, limits: children, using: &a)
            let secondBinding = try binder.bind(second, limits: children, using: &a)
            try Self.validateCells(curve, first: first, second: second, using: &a)
            let depth = max(firstBinding.sourceDepth, secondBinding.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalImplicitCurveSnapshot.self))
            let result = OriginalImplicitCurveSnapshot(original: curve, first: firstBinding, second: secondBinding)
            try a.checkpoint(); return .init(original: result, sourceDepth: depth.partialValue)
        } catch { throw .init(preserving: error) }
    }

    static func validateCells<A: ExactScalarAdmission & ~Copyable>(
        _ curve: borrowing CertifiedImplicitIntersectionCurve,
        first: borrowing BSplineSurface3D, second: borrowing BSplineSurface3D,
        using a: inout A
    ) throws {
        func contains(_ interval: ScalarInterval, _ domain: ParameterDomain) -> Bool {
            guard case .closed(let lower, let upper) = domain else { return false }
            return interval.lower.isFinite && interval.upper.isFinite
                && lower <= interval.lower && interval.lower < interval.upper && interval.upper <= upper
        }
        for cell in curve.cells {
            try a.checkpoint(); try a.consumeWork(32)
            let box = cell.parameterBox
            guard contains(box.firstU, first.uDomain), contains(box.firstV, first.vDomain),
                contains(box.secondU, second.uDomain), contains(box.secondV, second.vDomain) else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
        }
    }
}
