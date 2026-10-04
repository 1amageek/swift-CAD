import CADCore

/// Exact separability and closed-interval IVT authority on original geometry.
struct OverlapRegularGraphClosedDomainAuthority: Sendable {
    /// Original coefficient identity, independent of source membership or root existence.
    struct TargetIndependence: Sendable {
        enum Dependence: Sendable, Equatable {
            case u, v, constant
        }

        let prepared: PreparedBSplineSurfaceDifferentialEncloser
        private let x: Dependence?
        private let y: Dependence?
        private let z: Dependence?

        private init(prepared: PreparedBSplineSurfaceDifferentialEncloser,
                     x: Dependence?, y: Dependence?, z: Dependence?) {
            self.prepared = prepared
            self.x = x; self.y = y; self.z = z
        }

        static func certificate(prepared: PreparedBSplineSurfaceDifferentialEncloser,
                                budget: inout OverlapProofBudget) throws -> Self? {
            let surface = prepared.surface
            guard !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
            let count = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
            let comparisons = count.partialValue.multipliedReportingOverflow(by: 7)
            let knots = surface.uKnots.count.addingReportingOverflow(surface.vKnots.count)
            let scan = comparisons.partialValue.addingReportingOverflow(knots.partialValue)
            guard !count.overflow, !comparisons.overflow, !knots.overflow, !scan.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: budget.tolerance,
                    message: "Original coordinate independence scan count overflowed.")
            }
            // Two equalities per Cartesian coordinate, one weight check, and both knot vectors.
            // Fixed coordinate metadata is allocated only after its complete scan is paid.
            try budget.work(scan.partialValue)
            guard OverlapRegularGraphClosedDomainAuthority.clamped(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
                  OverlapRegularGraphClosedDomainAuthority.clamped(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount) else { return nil }
            var unit = true
            for row in surface.weights {
                for weight in row {
                    guard weight.isFinite, weight > 0 else { return nil }
                    if weight != 1 { unit = false }
                }
            }
            if !unit {
                try budget.work(count.partialValue)
                for row in 0..<surface.vControlPointCount {
                    for column in 0..<surface.uControlPointCount {
                        guard OverlapRegularGraphClosedDomainAuthority.equalPositiveDyadicProducts(surface.weights[row][column], surface.weights[0][0],
                            surface.weights[0][column], surface.weights[row][0]) else { return nil }
                    }
                }
            }
            func dependence(_ coordinate: Int) -> Dependence? {
                var onlyU = true, onlyV = true
                for row in 0..<surface.vControlPointCount {
                    for column in 0..<surface.uControlPointCount {
                        let value = OverlapRegularGraphCell.coordinate(surface.controlPoints[row][column], coordinate)
                        if value != OverlapRegularGraphCell.coordinate(surface.controlPoints[0][column], coordinate) { onlyU = false }
                        if value != OverlapRegularGraphCell.coordinate(surface.controlPoints[row][0], coordinate) { onlyV = false }
                    }
                }
                if onlyU && onlyV { return .constant }
                if onlyU { return .u }
                if onlyV { return .v }
                return nil
            }
            return Self(prepared: prepared, x: dependence(0), y: dependence(1), z: dependence(2))
        }

        private func dependence(_ coordinate: Int) -> Dependence? {
            switch coordinate { case 0: x; case 1: y; default: z }
        }

        func axis(coordinate: Int, box: SurfaceParameterBox) -> Axis? {
            guard let dependence = dependence(coordinate), dependence != .constant else { return nil }
            let surface = prepared.surface
            let onlyU = dependence == .u
            let lower = OverlapRegularGraphCell.coordinate(surface.controlPoints[0][0], coordinate)
            let upper = OverlapRegularGraphCell.coordinate(onlyU
                ? surface.controlPoints[0][surface.uControlPointCount - 1]
                : surface.controlPoints[surface.vControlPointCount - 1][0], coordinate)
            guard lower.isFinite, upper.isFinite, lower != upper else { return nil }
            return Axis(coordinate: coordinate, variesU: onlyU, parameters: onlyU ? box.u : box.v,
                lowerValue: lower, upperValue: upper)
        }

        func intersecting(_ jet: SurfaceIntervalVectorJet, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
            func component(_ value: SurfaceIntervalJet, coordinate: Int) throws -> SurfaceIntervalJet {
                guard let dependence = dependence(coordinate) else { return value }
                func derivative(_ original: OutwardScalarInterval, owning: Bool) throws -> OutwardScalarInterval {
                    if owning { return original }
                    guard let zero = original.intersection(with: .exact(0)) else {
                        throw Self.failure("An original quotient jet excludes its exact coordinate-independence identity.", tolerance)
                    }
                    return zero
                }
                let u = dependence == .u, v = dependence == .v
                return try SurfaceIntervalJet(value: value.value,
                    derivativeU: derivative(value.derivativeU, owning: u),
                    derivativeV: derivative(value.derivativeV, owning: v),
                    secondDerivativeUU: derivative(value.secondDerivativeUU, owning: u),
                    secondDerivativeUV: derivative(value.secondDerivativeUV, owning: false),
                    secondDerivativeVV: derivative(value.secondDerivativeVV, owning: v),
                    thirdDerivativeUUU: derivative(value.thirdDerivativeUUU, owning: u),
                    thirdDerivativeUUV: derivative(value.thirdDerivativeUUV, owning: false),
                    thirdDerivativeUVV: derivative(value.thirdDerivativeUVV, owning: false),
                    thirdDerivativeVVV: derivative(value.thirdDerivativeVVV, owning: v))
            }
            return try SurfaceIntervalVectorJet(x: component(jet.x, coordinate: 0),
                y: component(jet.y, coordinate: 1), z: component(jet.z, coordinate: 2))
        }

        private static func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
            KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance, message: message)
        }
    }

    struct Axis: Sendable {
        let coordinate: Int
        let variesU: Bool
        let parameters: ScalarInterval
        let lowerValue: Double
        let upperValue: Double

        func endpoint(for value: Double) -> Double? {
            if value == lowerValue { return parameters.lower }
            if value == upperValue { return parameters.upper }
            return nil
        }
    }

    let curve: BSplineCurve3D
    let surface: BSplineSurface3D
    let range: ScalarInterval
    let pair: OverlapRegularGraphCell.Pair
    let box: SurfaceParameterBox
    let first: Axis
    let second: Axis

    static func certificate(curve: Curve3D, surface: BSplineSurface3D,
                            range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                            box: SurfaceParameterBox, target: SurfaceIntervalVectorJet,
                            budget: inout OverlapProofBudget) throws -> Self? {
        guard case .bSpline(let source) = curve, !source.isPeriodic,
              !surface.isUPeriodic, !surface.isVPeriodic,
              source.controlPointCount == source.degree + 1,
              source.knots.count == 2 * (source.degree + 1) else { return nil }
        let tensorCount = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
        guard !tensorCount.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: budget.tolerance,
                message: "Closed-domain tensor comparison count overflowed.")
        }
        let scan = source.controlPointCount * 3 + source.knots.count
            + surface.uKnots.count + surface.vKnots.count
            + tensorCount.partialValue * 3
        try budget.work(scan)
        guard clamped(source.knots, degree: source.degree, count: source.controlPointCount),
              clamped(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
              clamped(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount),
              box.u.lower == surface.uKnots[surface.uDegree], box.u.upper == surface.uKnots[surface.uControlPointCount],
              box.v.lower == surface.vKnots[surface.vDegree], box.v.upper == surface.vKnots[surface.vControlPointCount],
              range.lower >= source.knots[0], range.upper <= source.knots[source.knots.count - 1] else { return nil }
        var unitWeights = true
        for row in surface.weights {
            for weight in row {
                guard weight.isFinite, weight > 0 else { return nil }
                if weight != 1 { unitWeights = false }
            }
        }
        if !unitWeights {
            // Charge every bounded exact comparison before inspecting the tensor.
            // Global rank-one original weights factor W=A(U)B(V)/W00 in any
            // tensor B-spline basis. Cartesian row/column independence below
            // then cancels the other positive factor without span replacement.
            try budget.work(tensorCount.partialValue)
            for row in 0..<surface.vControlPointCount {
                for column in 0..<surface.uControlPointCount {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Non-factorable rational target
                    // endpoint coincidence has no closed inverse authority here. The public
                    // regular graph route requires original coordinate independence and
                    // closed existence, membership and owned correspondence before success.
                    guard equalPositiveDyadicProducts(surface.weights[row][column], surface.weights[0][0],
                        surface.weights[0][column], surface.weights[row][0]) else { return nil }
                }
            }
        }
        guard let first = axis(coordinate: pair.first, surface: surface, box: box),
              let second = axis(coordinate: pair.second, surface: surface, box: box),
              first.variesU != second.variesU,
              monotone(first, target: target), monotone(second, target: target) else { return nil }
        return admittedSource(source, surface: surface, range: range, pair: pair, box: box, first: first, second: second)
    }

    static func certificate(curve: Curve3D, independence: TargetIndependence,
                            range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                            box: SurfaceParameterBox, target: SurfaceIntervalVectorJet,
                            budget: inout OverlapProofBudget) throws -> Self? {
        guard case .bSpline(let source) = curve, !source.isPeriodic,
              source.controlPointCount == source.degree + 1,
              source.knots.count == 2 * (source.degree + 1) else { return nil }
        try budget.work(source.controlPointCount * 3 + source.knots.count)
        let surface = independence.prepared.surface
        guard clamped(source.knots, degree: source.degree, count: source.controlPointCount),
              box.u.lower == surface.uKnots[surface.uDegree], box.u.upper == surface.uKnots[surface.uControlPointCount],
              box.v.lower == surface.vKnots[surface.vDegree], box.v.upper == surface.vKnots[surface.vControlPointCount],
              range.lower >= source.knots[0], range.upper <= source.knots[source.knots.count - 1],
              let first = independence.axis(coordinate: pair.first, box: box),
              let second = independence.axis(coordinate: pair.second, box: box), first.variesU != second.variesU,
              monotone(first, target: target), monotone(second, target: target) else { return nil }
        return admittedSource(source, surface: surface, range: range, pair: pair, box: box, first: first, second: second)
    }

    private static func admittedSource(_ source: BSplineCurve3D, surface: BSplineSurface3D,
                                       range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                                       box: SurfaceParameterBox, first: Axis, second: Axis) -> Self? {
        var firstMinimum = Double.infinity, firstMaximum = -Double.infinity
        var secondMinimum = Double.infinity, secondMaximum = -Double.infinity
        for index in 0..<source.controlPointCount {
            guard source.weights[index].isFinite, source.weights[index] > 0 else { return nil }
            let point = source.controlPoints[index]
            let a = OverlapRegularGraphCell.coordinate(point, first.coordinate)
            let b = OverlapRegularGraphCell.coordinate(point, second.coordinate)
            guard a >= min(first.lowerValue, first.upperValue), a <= max(first.lowerValue, first.upperValue),
                  b >= min(second.lowerValue, second.upperValue), b <= max(second.lowerValue, second.upperValue) else { return nil }
            firstMinimum = min(firstMinimum, a); firstMaximum = max(firstMaximum, a)
            secondMinimum = min(secondMinimum, b); secondMaximum = max(secondMaximum, b)
        }
        guard firstMinimum < firstMaximum, secondMinimum < secondMaximum else { return nil }
        return Self(curve: source, surface: surface, range: range, pair: pair, box: box, first: first, second: second)
    }

    func exactEndpoint(at parameter: Double) -> SurfaceParameter? {
        guard parameter >= range.lower, parameter <= range.upper else { return nil }
        let point: Point3D
        if parameter == curve.knots[0] { point = curve.controlPoints[0] }
        else if parameter == curve.knots[curve.knots.count - 1] { point = curve.controlPoints[curve.controlPointCount - 1] }
        else { return nil }
        guard let a = first.endpoint(for: OverlapRegularGraphCell.coordinate(point, first.coordinate)),
              let b = second.endpoint(for: OverlapRegularGraphCell.coordinate(point, second.coordinate)) else { return nil }
        return SurfaceParameter(u: first.variesU ? a : b, v: first.variesU ? b : a)
    }

    /// Compares exact real products of original positive binary64 coefficients.
    /// Each odd product has at most 106 bits; floating overflow or rounding is irrelevant.
    static func equalPositiveDyadicProducts(_ first: Double, _ second: Double,
                                           _ third: Double, _ fourth: Double) -> Bool {
        guard let a = DyadicFactor(first), let b = DyadicFactor(second),
              let c = DyadicFactor(third), let d = DyadicFactor(fourth),
              a.exponent + b.exponent == c.exponent + d.exponent else { return false }
        let left = a.significand.multipliedFullWidth(by: b.significand)
        let right = c.significand.multipliedFullWidth(by: d.significand)
        return left.high == right.high && left.low == right.low
    }

    private struct DyadicFactor {
        let significand: UInt64
        let exponent: Int

        init?(_ value: Double) {
            guard value.isFinite, value > 0 else { return nil }
            let bits = value.bitPattern
            let encodedExponent = (bits >> 52) & 0x7ff
            var significand = bits & ((UInt64(1) << 52) - 1)
            var exponent = -1074
            if encodedExponent != 0 {
                significand |= UInt64(1) << 52
                exponent = Int(encodedExponent) - 1075
            }
            let trailing = significand.trailingZeroBitCount
            self.significand = significand >> trailing
            self.exponent = exponent + trailing
        }
    }

    private static func clamped(_ knots: [Double], degree: Int, count: Int) -> Bool {
        let lower = knots[degree], upper = knots[count]
        guard lower.isFinite, upper.isFinite, lower < upper else { return false }
        for index in 0...degree {
            if knots[index] != lower || knots[knots.count - 1 - index] != upper { return false }
        }
        return true
    }

    private static func axis(coordinate: Int, surface: BSplineSurface3D,
                             box: SurfaceParameterBox) -> Axis? {
        var onlyU = true, onlyV = true
        for row in 0..<surface.vControlPointCount {
            for column in 0..<surface.uControlPointCount {
                let value = OverlapRegularGraphCell.coordinate(surface.controlPoints[row][column], coordinate)
                if value != OverlapRegularGraphCell.coordinate(surface.controlPoints[0][column], coordinate) { onlyU = false }
                if value != OverlapRegularGraphCell.coordinate(surface.controlPoints[row][0], coordinate) { onlyV = false }
            }
        }
        guard onlyU != onlyV else { return nil }
        let lower = OverlapRegularGraphCell.coordinate(surface.controlPoints[0][0], coordinate)
        let upper = OverlapRegularGraphCell.coordinate(onlyU
            ? surface.controlPoints[0][surface.uControlPointCount - 1]
            : surface.controlPoints[surface.vControlPointCount - 1][0], coordinate)
        guard lower != upper, lower.isFinite, upper.isFinite else { return nil }
        return Axis(coordinate: coordinate, variesU: onlyU, parameters: onlyU ? box.u : box.v,
            lowerValue: lower, upperValue: upper)
    }

    private static func monotone(_ axis: Axis, target: SurfaceIntervalVectorJet) -> Bool {
        let component = OverlapRegularGraphCell.component(target, axis.coordinate)
        let derivative = axis.variesU ? component.derivativeU : component.derivativeV
        guard derivative.isFinite else { return false }
        return axis.upperValue > axis.lowerValue ? derivative.lower > 0 : derivative.upper < 0
    }
}
