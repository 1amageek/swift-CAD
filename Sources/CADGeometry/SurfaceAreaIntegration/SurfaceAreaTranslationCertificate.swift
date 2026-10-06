import CADCore

/// A structurally proved affine translation along one native parameter.
/// Equal control differences are proved with exact floating-point expansions,
/// independently of modeling tolerance and sampled derivatives.
package enum SurfaceAreaTranslationCertificate: Sendable, Equatable {
    case u
    case v

    static func direction(of surface: Surface3D) -> Self? {
        switch surface {
        case .plane, .analytic(.plane), .cylinder, .analytic(.cylinder): return .v
        case .bSpline(let spline):
            if !spline.isVPeriodic, spline.vDegree == 1, spline.controlPoints.count == 2,
               spline.vKnots.count == 4, spline.vKnots[0] == spline.vKnots[1],
               spline.vKnots[2] == spline.vKnots[3],
               spline.weights[0] == spline.weights[1],
               translated(spline.controlPoints[0], spline.controlPoints[1]) { return .v }
            if !spline.isUPeriodic, spline.uDegree == 1, spline.controlPoints.first?.count == 2,
               spline.uKnots.count == 4, spline.uKnots[0] == spline.uKnots[1],
               spline.uKnots[2] == spline.uKnots[3],
               spline.weights.allSatisfy({ $0[0] == $0[1] }),
               translated(spline.controlPoints.map { $0[0] }, spline.controlPoints.map { $0[1] }) { return .u }
            return nil
        case .procedural(.offset(let offset)): return direction(of: offset.source)
        case .procedural(.ruled(let ruled)):
            guard case .bSpline(let start) = ruled.startBoundary,
                  case .bSpline(let end) = ruled.endBoundary,
                  start.degree == end.degree, start.knots == end.knots, start.weights == end.weights,
                  start.isPeriodic == end.isPeriodic, start.periodicOrigin == end.periodicOrigin, translated(start.controlPoints, end.controlPoints) else { return nil }
            return .v
        case .procedural(.rollingBall(let blend)):
            guard let center = linearControlPair(blend.centerSpine),
                  let first = linearControlPair(blend.firstContact),
                  let second = linearControlPair(blend.secondContact),
                  sameDifference(center.1, center.0, first.1, first.0),
                  sameDifference(center.1, center.0, second.1, second.0) else { return nil }
            return .u
        default: return nil
        }
    }

    /// Caller-admitted proof on the retained original coefficient buffers.
    static func direction(of surface: Surface3D, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self? {
        try consumeWork(); try CurrentTaskCancellationChecker().checkCancellation()
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original translation source depth is exhausted.")
        }
        func equal(_ first: [Double], _ second: [Double]) throws -> Bool {
            guard first.count == second.count else { return false }
            for index in first.indices { try consumeWork(); if first[index] != second[index] { return false } }
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
                    maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork,
                    consumeStorage: consumeStorage) { return .v }
            if !spline.isUPeriodic, spline.uDegree == 1, spline.controlPoints.first?.count == 2,
                spline.uKnots.count == 4, spline.uKnots[0] == spline.uKnots[1],
                spline.uKnots[2] == spline.uKnots[3], let row = spline.controlPoints.first {
                for index in spline.controlPoints.indices {
                    try consumeWork()
                    guard spline.weights[index].count == 2, spline.weights[index][0] == spline.weights[index][1],
                        try sameDifference(spline.controlPoints[index][1], spline.controlPoints[index][0],
                            row[1], row[0], maximumAlgebraicDepth: maximumAlgebraicDepth,
                            consumeWork: consumeWork, consumeStorage: consumeStorage) else { return nil }
                }
                return .u
            }
            return nil
        case .procedural(.offset(let offset)):
            return try direction(of: offset.source, remainingSourceDepth: remainingSourceDepth - 1,
                maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .procedural(.ruled(let ruled)):
            guard case .bSpline(let start) = ruled.startBoundary, case .bSpline(let end) = ruled.endBoundary,
                start.degree == end.degree, start.isPeriodic == end.isPeriodic,
                start.periodicOrigin == end.periodicOrigin, try equal(start.knots, end.knots),
                try equal(start.weights, end.weights), try translated(start.controlPoints, end.controlPoints,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork,
                    consumeStorage: consumeStorage) else { return nil }
            return .v
        case .procedural(.rollingBall(let blend)):
            guard let center = linearControlPair(blend.centerSpine), let first = linearControlPair(blend.firstContact),
                let second = linearControlPair(blend.secondContact),
                try sameDifference(center.1, center.0, first.1, first.0,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork, consumeStorage: consumeStorage),
                try sameDifference(center.1, center.0, second.1, second.0,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
                else { return nil }
            return .u
        default: return nil
        }
    }

    static func translated(_ start: [Point3D], _ end: [Point3D], maximumAlgebraicDepth: Int?,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Bool {
        guard start.count == end.count, let first = start.first, let last = end.first else { return false }
        for index in start.indices {
            try consumeWork()
            guard try sameDifference(end[index], start[index], last, first,
                maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage) else { return false }
        }
        return true
    }

    static func sameDifference(_ a: Point3D, _ b: Point3D, _ c: Point3D, _ d: Point3D,
        maximumAlgebraicDepth: Int?, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> Bool {
        try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() },
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            func equal(_ a: Double, _ b: Double, _ c: Double, _ d: Double) throws -> Bool {
                let first = try ExactRationalCoefficient.originalDouble(a, usage: &usage)
                    .subtracting(.originalDouble(b, usage: &usage), usage: &usage)
                let second = try ExactRationalCoefficient.originalDouble(c, usage: &usage)
                    .subtracting(.originalDouble(d, usage: &usage), usage: &usage)
                return try first.subtracting(second, usage: &usage).isZero
            }
            return try equal(a.x, b.x, c.x, d.x) && equal(a.y, b.y, c.y, d.y) && equal(a.z, b.z, c.z, d.z)
        }
    }

    static func linearImageIsExactlyRepresented(origin: Double, first: Double, second: Double,
        fraction: Double, value: Double, maximumAlgebraicDepth: Int?,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Bool {
        try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork:{ _ in try work() },
                consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
            let a = try ExactRationalCoefficient.originalDouble(first,usage:&usage)
            let delta = try a.subtracting(.originalDouble(second,usage:&usage),usage:&usage)
            let gain = try ExactRationalCoefficient.originalDouble(fraction,usage:&usage)
            let shifted = try delta.multiplied(by:gain,usage:&usage)
                .adding(.originalDouble(origin,usage:&usage),usage:&usage)
            return try shifted.subtracting(.originalDouble(value,usage:&usage),usage:&usage).isZero
        }
    }

    /// Exact fourth derivatives of these globally smooth polynomial supports vanish.
    static func fourthDerivativesAreExactlyZero(of surface: Surface3D) -> Bool {
        func polynomialLine(_ curve: Curve3D) -> Bool {
            guard case .bSpline(let spline) = curve, !spline.isPeriodic,
                  spline.degree == 1, spline.controlPoints.count == 2,
                  spline.knots.count == 4, spline.knots[0] == spline.knots[1],
                  spline.knots[2] == spline.knots[3], spline.weights[0] == spline.weights[1] else { return false }
            return true
        }
        switch surface {
        case .plane, .analytic(.plane): return true
        case .bSpline(let spline):
            guard !spline.isUPeriodic, !spline.isVPeriodic,
                  spline.uDegree + spline.vDegree <= 3,
                  spline.controlPoints.count == spline.vDegree + 1,
                  spline.controlPoints.first?.count == spline.uDegree + 1,
                  let weight = spline.weights.first?.first,
                  spline.weights.allSatisfy({ $0.allSatisfy { $0 == weight } }),
                  let uLow = spline.uKnots.first, let uHigh = spline.uKnots.last,
                  let vLow = spline.vKnots.first, let vHigh = spline.vKnots.last else { return false }
            return spline.uKnots.prefix(spline.uDegree + 1).allSatisfy { $0 == uLow }
                && spline.uKnots.suffix(spline.uDegree + 1).allSatisfy { $0 == uHigh }
                && spline.vKnots.prefix(spline.vDegree + 1).allSatisfy { $0 == vLow }
                && spline.vKnots.suffix(spline.vDegree + 1).allSatisfy { $0 == vHigh }
        case .procedural(.ruled(let ruled)):
            return polynomialLine(ruled.startBoundary) && polynomialLine(ruled.endBoundary)
        default: return false
        }
    }

    static func fourthDerivativesAreExactlyZero(of surface: Surface3D,
        consumeWork: () throws -> Void) throws -> Bool {
        try consumeWork()
        func polynomialLine(_ curve: Curve3D) throws -> Bool {
            try consumeWork()
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
            for row in spline.weights { for value in row { try consumeWork(); if value != weight { return false } } }
            for index in 0...spline.uDegree {
                try consumeWork()
                if spline.uKnots[index] != uLow || spline.uKnots[spline.uKnots.count-1-index] != uHigh { return false }
            }
            for index in 0...spline.vDegree {
                try consumeWork()
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

    private static func translated(_ start: [Point3D], _ end: [Point3D]) -> Bool {
        guard start.count == end.count, let a = start.first, let b = end.first else { return false }
        return start.indices.allSatisfy { sameDifference(end[$0], start[$0], b, a) }
    }

    private static func sameDifference(_ a: Point3D, _ b: Point3D, _ c: Point3D, _ d: Point3D) -> Bool {
        for (av, bv, cv, dv) in [(a.x,b.x,c.x,d.x),(a.y,b.y,c.y,d.y),(a.z,b.z,c.z,d.z)] {
            let first = FloatingPointExpansion.difference(av, bv)
            let second = FloatingPointExpansion.difference(cv, dv)
            if FloatingPointExpansion.sign(FloatingPointExpansion.subtract(first, second)) != .zero { return false }
        }
        return true
    }
}
