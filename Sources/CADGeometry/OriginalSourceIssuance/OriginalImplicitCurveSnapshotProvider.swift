import CADCore

/// Selects a bounded triangular representation; the exact issuer still proves its law.
public struct OriginalImplicitCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    public static func supports(_ input: borrowing Curve3D) -> Bool {
        guard case .implicit(let curve) = copy input, !curve.isClosed, curve.cells.count == 1,
            curve.cells[0].freeParameter == .firstV, curve.cells[0].direction == .forward,
            case .bSpline(let first) = curve.firstSurface,
            case .bSpline(let second) = curve.secondSurface,
            native(first, uDegree: 1), native(second, uDegree: 2) else { return false }
        let p = first.controlPoints, q = second.controlPoints
        guard p[0][0].x != p[0][1].x, p[0][0].y != p[1][0].y,
            q[0][0].y != q[0][2].y, q[0][0].z != q[1][0].z else { return false }
        for row in 0..<2 {
            for column in 0..<2 {
                guard p[row][column].x == p[0][column].x,
                    p[row][column].y == p[row][0].y,
                    p[row][column].z == p[0][0].z else { return false }
            }
            for column in 0..<3 {
                guard q[row][column].x == q[0][column].x,
                    q[row][column].y == q[0][column].y,
                    q[row][column].z == q[row][0].z else { return false }
            }
        }
        // Sterbenz-exact differences select a truly affine quadratic Y net.
        // No rounded midpoint or numerical residual establishes this equality.
        guard let left = exactDifference(q[0][1].y, q[0][0].y),
            let right = exactDifference(q[0][2].y, q[0][1].y), left == right else { return false }
        return true
    }

    private static func exactDifference(_ x: Double, _ y: Double) -> Double? {
        guard x.isFinite, y.isFinite else { return nil }
        if x == 0 || y == 0 { return x - y }
        guard x.sign == y.sign else { return nil }
        let a = x.magnitude, b = y.magnitude
        guard min(a,b) >= max(a,b) / 2 else { return nil }
        return x - y
    }

    private static func native(_ s: BSplineSurface3D, uDegree: Int) -> Bool {
        guard s.uDegree == uDegree, s.vDegree == 1, !s.isUPeriodic, !s.isVPeriodic,
            s.controlPoints.count == 2, s.weights.count == 2,
            s.uKnots.count == 2 * (uDegree + 1), s.vKnots.count == 4,
            s.uKnots[0].isFinite, s.uKnots[uDegree + 1].isFinite,
            s.uKnots[0] < s.uKnots[uDegree + 1],
            s.vKnots[0].isFinite, s.vKnots[2].isFinite, s.vKnots[0] < s.vKnots[2],
            s.weights[0].count == uDegree + 1, let weight = s.weights[0].first,
            weight.isFinite, weight > 0 else { return false }
        for index in 0...uDegree {
            guard s.uKnots[index] == s.uKnots[0],
                s.uKnots[index + uDegree + 1] == s.uKnots[uDegree + 1] else { return false }
        }
        guard s.vKnots[1] == s.vKnots[0], s.vKnots[3] == s.vKnots[2] else { return false }
        for row in 0..<2 {
            guard s.controlPoints[row].count == uDegree + 1, s.weights[row].count == uDegree + 1 else { return false }
            for column in 0...uDegree {
                let p = s.controlPoints[row][column]
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite, s.weights[row][column] == weight else { return false }
            }
        }
        return true
    }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalImplicitCurveSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            try input.validate(tolerance: tolerance)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The live implicit CS source port currently
            // supplies only this single-cell triangular Native representation. General cells,
            // hosts, free coordinates and directions need complete original graph authority.
            guard Self.supports(input), case .implicit(let curve) = copy input,
                case .bSpline(let first) = curve.firstSurface,
                case .bSpline(let second) = curve.secondSurface else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try a.consumeWork(64)
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            let binder = DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance))
            let firstBinding = try binder.bind(first, limits: children, using: &a)
            let secondBinding = try binder.bind(second, limits: children, using: &a)
            let depth = max(firstBinding.sourceDepth,secondBinding.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalImplicitCurveSnapshot.self))
            let result = OriginalImplicitCurveSnapshot(original: curve, first: firstBinding, second: secondBinding)
            try a.checkpoint(); return .init(original: result, sourceDepth: depth.partialValue)
        } catch { throw .init(preserving: error) }
    }
}
