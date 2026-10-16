import CADCore

/// A structurally proved affine translation along one native parameter.
/// Equal control differences are proved with exact floating-point expansions,
/// independently of modeling tolerance and sampled derivatives.
package enum SurfaceAreaTranslationCertificate: Sendable, Equatable {
    case u
    case v

    /// Caller-admitted proof on the retained original coefficient buffers.
    static func direction(of surface: Surface3D, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> Self? {
        try execution.consumeWork(1); try CurrentTaskCancellationChecker().checkCancellation()
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original translation source depth is exhausted.")
        }
        func equal(_ first: [Double], _ second: [Double]) throws -> Bool {
            guard first.count == second.count else { return false }
            for index in first.indices { try execution.consumeWork(1); if first[index] != second[index] { return false } }
            return true
        }
        switch surface {
        case .plane, .analytic(.plane), .cylinder, .analytic(.cylinder): return .v
        case .bSpline(let spline):
            if !spline.isVPeriodic, spline.vDegree == 1, spline.controlPoints.count == 2,
                spline.vKnots.count == 4, spline.vKnots[0] == spline.vKnots[1],
                spline.vKnots[2] == spline.vKnots[3],
                try equal(spline.weights[0], spline.weights[1]),
                try translated(spline.controlPoints[0], spline.controlPoints[1],
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) { return .v }
            if !spline.isUPeriodic, spline.uDegree == 1, spline.controlPoints.first?.count == 2,
                spline.uKnots.count == 4, spline.uKnots[0] == spline.uKnots[1],
                spline.uKnots[2] == spline.uKnots[3], let row = spline.controlPoints.first {
                for index in spline.controlPoints.indices {
                    try execution.consumeWork(1)
                    guard spline.weights[index].count == 2, spline.weights[index][0] == spline.weights[index][1],
                        try sameDifference(spline.controlPoints[index][1], spline.controlPoints[index][0],
                            row[1], row[0], maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) else { return nil }
                }
                return .u
            }
            return nil
        case .procedural(.offset(let offset)):
            return try direction(of: offset.source, remainingSourceDepth: remainingSourceDepth - 1,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        case .procedural(.ruled(let ruled)):
            guard case .bSpline(let start) = ruled.startBoundary, case .bSpline(let end) = ruled.endBoundary,
                start.degree == end.degree, start.isPeriodic == end.isPeriodic,
                start.periodicOrigin == end.periodicOrigin, try equal(start.knots, end.knots),
                try equal(start.weights, end.weights), try translated(start.controlPoints, end.controlPoints,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) else { return nil }
            return .v
        case .procedural(.rollingBall(let blend)):
            guard let center = linearControlPair(blend.centerSpine), let first = linearControlPair(blend.firstContact),
                let second = linearControlPair(blend.secondContact),
                try sameDifference(center.1, center.0, first.1, first.0,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution),
                try sameDifference(center.1, center.0, second.1, second.0,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                else { return nil }
            return .u
        default: return nil
        }
    }

    static func translated(_ start: [Point3D], _ end: [Point3D], maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard start.count == end.count, let first = start.first, let last = end.first else { return false }
        for index in start.indices {
            try execution.consumeWork(1)
            guard try sameDifference(end[index], start[index], last, first,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution) else { return false }
        }
        return true
    }

    static func sameDifference<A: ExactScalarAdmission & ~Copyable>(_ a: Point3D, _ b: Point3D,
        _ c: Point3D, _ d: Point3D, maximumAlgebraicDepth: Int?, using execution: inout A) throws -> Bool {
        let maximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: maximum) { execution in
            func equal(_ a: Double, _ b: Double, _ c: Double, _ d: Double,
                using execution: inout A) throws -> Bool {
                let first = try ExactRationalCoefficient.originalDouble(a, usage: &execution)
                    .subtracting(.originalDouble(b, usage: &execution), usage: &execution)
                let second = try ExactRationalCoefficient.originalDouble(c, usage: &execution)
                    .subtracting(.originalDouble(d, usage: &execution), usage: &execution)
                return try first.subtracting(second, usage: &execution).isZero
            }
            return try equal(a.x, b.x, c.x, d.x, using: &execution)
                && equal(a.y, b.y, c.y, d.y, using: &execution)
                && equal(a.z, b.z, c.z, d.z, using: &execution)
        }
    }

    static func linearImageIsExactlyRepresented<A: ExactScalarAdmission & ~Copyable>(origin: Double,
        first: Double, second: Double, fraction: Double, value: Double,
        maximumAlgebraicDepth: Int?, using execution: inout A) throws -> Bool {
        let maximum = try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
        return try execution.withProofScope(maximum: maximum) { execution in
            let a = try ExactRationalCoefficient.originalDouble(first, usage: &execution)
            let delta = try a.subtracting(.originalDouble(second, usage: &execution), usage: &execution)
            let gain = try ExactRationalCoefficient.originalDouble(fraction, usage: &execution)
            let shifted = try delta.multiplied(by: gain, usage: &execution)
                .adding(.originalDouble(origin, usage: &execution), usage: &execution)
            return try shifted.subtracting(.originalDouble(value, usage: &execution), usage: &execution).isZero
        }
    }

    static func fourthDerivativesAreExactlyZero(of surface: Surface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        func polynomialLine(_ curve: Curve3D) throws -> Bool {
            try execution.consumeWork(1)
            guard case .bSpline(let spline) = curve, !spline.isPeriodic,
                spline.degree == 1, spline.controlPoints.count == 2,
                spline.knots.count == 4, spline.knots[0] == spline.knots[1],
                spline.knots[2] == spline.knots[3], spline.weights[0] == spline.weights[1]
                else { return false }
            return true
        }
        switch surface {
        case .plane, .analytic(.plane): return true
        case .bSpline(let spline):
            guard !spline.isUPeriodic, !spline.isVPeriodic, spline.uDegree + spline.vDegree <= 3,
                spline.controlPoints.count == spline.vDegree + 1,
                spline.controlPoints.first?.count == spline.uDegree + 1,
                let weight = spline.weights.first?.first, let uLow = spline.uKnots.first,
                let uHigh = spline.uKnots.last, let vLow = spline.vKnots.first, let vHigh = spline.vKnots.last
                else { return false }
            for row in spline.weights { for value in row { try execution.consumeWork(1); if value != weight { return false } } }
            for index in 0...spline.uDegree {
                try execution.consumeWork(1)
                if spline.uKnots[index] != uLow || spline.uKnots[spline.uKnots.count-1-index] != uHigh { return false }
            }
            for index in 0...spline.vDegree {
                try execution.consumeWork(1)
                if spline.vKnots[index] != vLow || spline.vKnots[spline.vKnots.count-1-index] != vHigh { return false }
            }
            return true
        case .procedural(.ruled(let ruled)):
            return try polynomialLine(ruled.startBoundary) && polynomialLine(ruled.endBoundary)
        default: return false
        }
    }

    private static func linearControlPair(_ curve: Curve3D) -> (Point3D, Point3D)? {
        guard case .bSpline(let spline) = curve, !spline.isPeriodic, spline.degree == 1,
              spline.controlPoints.count == 2, spline.knots.count == 4, spline.knots[0] == 0, spline.knots[1] == 0,
              spline.knots[2] == 1, spline.knots[3] == 1,
              spline.weights.count == 2, spline.weights[0] == spline.weights[1] else { return nil }
        return (spline.controlPoints[0], spline.controlPoints[1])
    }

}
