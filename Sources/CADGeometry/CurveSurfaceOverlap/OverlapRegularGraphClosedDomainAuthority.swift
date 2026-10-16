import CADCore

/// Original separable or triangular closed-domain existence authority.
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
                                policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
            let surface = prepared.surface
            guard !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
            let count = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
            let comparisons = count.partialValue.multipliedReportingOverflow(by: 7)
            let knots = surface.uKnots.count.addingReportingOverflow(surface.vKnots.count)
            let scan = comparisons.partialValue.addingReportingOverflow(knots.partialValue)
            guard !count.overflow, !comparisons.overflow, !knots.overflow, !scan.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: policy.tolerance,
                    message: "Original coordinate independence scan count overflowed.")
            }
            // Two equalities per Cartesian coordinate, one weight check, and both knot vectors.
            // Fixed coordinate metadata is allocated only after its complete scan is paid.
            try policy.work(scan.partialValue, using: &execution)
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
                try policy.work(count.partialValue, using: &execution)
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
        let constantParameter: Double?

        init(coordinate: Int, variesU: Bool, parameters: ScalarInterval,
             lowerValue: Double, upperValue: Double, constantParameter: Double? = nil) {
            self.coordinate = coordinate; self.variesU = variesU; self.parameters = parameters
            self.lowerValue = lowerValue; self.upperValue = upperValue
            self.constantParameter = constantParameter
        }

        func endpoint(for value: Double) -> Double? {
            // This axis belongs to a complete constant original-source identity.
            if let constantParameter { return constantParameter }
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
    enum Mapping: Sendable {
        case separable(Axis, Axis)
        case triangular(Triangular)
        case rectangle(OverlapClosedRectangleRootAuthority)

        var separableAxes: (Axis, Axis)? {
            if case let .separable(first, second) = self { return (first, second) }
            return nil
        }
    }

    struct Triangular: Sendable {
        let primaryCoordinate: Int
        let secondaryCoordinate: Int
        let primaryVariesU: Bool
        let primaryDiagonal: [Double]
        let shear: [Double]
        let secondaryDiagonal: [Double]
        let start: SurfaceParameter?
        let end: SurfaceParameter?
    }

    let mapping: Mapping

    var stationaryParameters: (u: Double?, v: Double?) {
        guard let axes = mapping.separableAxes else { return (nil, nil) }
        return axes.0.variesU
            ? (axes.0.constantParameter, axes.1.constantParameter)
            : (axes.1.constantParameter, axes.0.constantParameter)
    }

    static func certificate(curve: Curve3D, surface: BSplineSurface3D,
                            range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                            box: SurfaceParameterBox, target: SurfaceIntervalVectorJet,
                            policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
        guard case .bSpline(let source) = curve, !source.isPeriodic,
              !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
        let tensorCount = surface.uControlPointCount.multipliedReportingOverflow(by: surface.vControlPointCount)
        guard !tensorCount.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: policy.tolerance,
                message: "Closed-domain tensor comparison count overflowed.")
        }
        let scan = source.controlPointCount * 3 + source.knots.count
            + surface.uKnots.count + surface.vKnots.count
            + tensorCount.partialValue * 3
        try policy.work(scan, using: &execution)
        guard originalSourceAtlas(source),
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
            try policy.work(tensorCount.partialValue, using: &execution)
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
        if let first = axis(coordinate: pair.first, surface: surface, box: box),
           let second = axis(coordinate: pair.second, surface: surface, box: box),
           first.variesU != second.variesU,
           monotone(first, target: target), monotone(second, target: target) {
            return try admittedSource(source, surface: surface, range: range, pair: pair, box: box,
                first: first, second: second, policy: policy, using: &execution)
        }
        return try admittedTriangular(source, surface: surface, range: range, pair: pair, box: box, policy: policy, using: &execution)
    }

    static func certificate(curve: Curve3D, independence: TargetIndependence,
                            range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                            box: SurfaceParameterBox, target: SurfaceIntervalVectorJet,
                            policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
        guard case .bSpline(let source) = curve, !source.isPeriodic else { return nil }
        try policy.work(source.controlPointCount * 3 + source.knots.count, using: &execution)
        let surface = independence.prepared.surface
        guard originalSourceAtlas(source),
              box.u.lower == surface.uKnots[surface.uDegree], box.u.upper == surface.uKnots[surface.uControlPointCount],
              box.v.lower == surface.vKnots[surface.vDegree], box.v.upper == surface.vKnots[surface.vControlPointCount],
              range.lower >= source.knots[0], range.upper <= source.knots[source.knots.count - 1] else { return nil }
        if let first = independence.axis(coordinate: pair.first, box: box),
           let second = independence.axis(coordinate: pair.second, box: box), first.variesU != second.variesU,
           monotone(first, target: target), monotone(second, target: target) {
            return try admittedSource(source, surface: surface, range: range, pair: pair, box: box,
                first: first, second: second, policy: policy, using: &execution)
        }
        return try admittedTriangular(source, surface: surface, range: range, pair: pair, box: box, policy: policy, using: &execution)
    }

    /// The caller has paid the complete original knot scan before this check.
    /// Degree-fold spans use original control slices, sharing one endpoint.
    private static func originalSourceAtlas(_ source: BSplineCurve3D) -> Bool {
        let degree = source.degree, count = source.controlPointCount
        let sum = count.addingReportingOverflow(degree)
        let length = sum.partialValue.addingReportingOverflow(1)
        guard degree >= 0, count > degree, !sum.overflow, !length.overflow,
              source.knots.count == length.partialValue,
              clamped(source.knots, degree: degree, count: count) else { return false }
        if count == degree + 1 { return true }
        guard degree >= 1 else { return false }
        let lower = source.knots[degree], upper = source.knots[count]
        var index = degree + 1
        while index < count {
            let knot = source.knots[index]
            var end = index + 1
            while end < count, source.knots[end] == knot { end += 1 }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Other original source multiplicities
            // still require directed original extraction authority. The public regular
            // graph endpoint path must not admit their rounded extracted nets before
            // complete original-span membership, root joins and correspondence are proved.
            guard knot > lower, knot < upper, end - index == degree else { return false }
            index = end
        }
        return index == count
    }

    private static func admittedSource(_ source: BSplineCurve3D, surface: BSplineSurface3D,
                                       range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                                       box: SurfaceParameterBox, first: Axis, second: Axis,
                                       policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
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
        guard firstMinimum < firstMaximum || secondMinimum < secondMaximum else { return nil }
        func retained(_ axis: Axis, minimum: Double, maximum: Double) throws -> Axis? {
            if minimum < maximum { return axis }
            let knots = axis.variesU ? surface.uKnots : surface.vKnots
            let degree = axis.variesU ? surface.uDegree : surface.vDegree
            let count = axis.variesU ? surface.uControlPointCount : surface.vControlPointCount
            let fee = knots.count.addingReportingOverflow(4)
            guard !fee.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: policy.tolerance,
                    message: "An original stationary-axis scan count overflowed.")
            }
            try policy.work(fee.partialValue, using: &execution)
            let parameter: Double?
            if minimum == axis.lowerValue { parameter = axis.parameters.lower }
            else if minimum == axis.upperValue { parameter = axis.parameters.upper }
            else {
                var found: Double?
                var index = degree + 1
                while index < count {
                    let knot = knots[index]
                    var end = index + 1
                    while end < count, knots[end] == knot { end += 1 }
                    if end - index == degree {
                        // At an original degree-fold knot the native basis selects
                        // original control index (first knot index - 1) exactly.
                        // Rank-one weights cancel their positive non-owning factor.
                        let control = axis.variesU ? surface.controlPoints[0][index - 1]
                            : surface.controlPoints[index - 1][0]
                        if OverlapRegularGraphCell.coordinate(control, axis.coordinate) == minimum {
                            found = knot; break
                        }
                    }
                    index = end
                }
                parameter = found
            }
            guard let parameter else { return nil }
            return Axis(coordinate: axis.coordinate, variesU: axis.variesU, parameters: axis.parameters,
                lowerValue: axis.lowerValue, upperValue: axis.upperValue, constantParameter: parameter)
        }
        guard let retainedFirst = try retained(first, minimum: firstMinimum, maximum: firstMaximum),
              let retainedSecond = try retained(second, minimum: secondMinimum, maximum: secondMaximum) else { return nil }
        return Self(curve: source, surface: surface, range: range, pair: pair, box: box,
            mapping: .separable(retainedFirst, retainedSecond))
    }

    func exactEndpoint(at parameter: Double) -> SurfaceParameter? {
        guard parameter >= range.lower, parameter <= range.upper else { return nil }
        let point: Point3D
        if parameter == curve.knots[0] { point = curve.controlPoints[0] }
        else if parameter == curve.knots[curve.knots.count - 1] { point = curve.controlPoints[curve.controlPointCount - 1] }
        else { return nil }
        switch mapping {
        case let .separable(first, second):
            guard let a = first.endpoint(for: OverlapRegularGraphCell.coordinate(point, first.coordinate)),
                  let b = second.endpoint(for: OverlapRegularGraphCell.coordinate(point, second.coordinate)) else { return nil }
            return SurfaceParameter(u: first.variesU ? a : b, v: first.variesU ? b : a)
        case let .triangular(chart):
            // Exact endpoint cofactors were already proved and paid at minting.
            return parameter == curve.knots[0] ? chart.start : chart.end
        case let .rectangle(chart):
            // Original clamped face identities prove these actual corner values.
            return parameter == curve.knots[0] ? chart.start : chart.end
        }
    }

    private static func admittedTriangular(_ source: BSplineCurve3D, surface: BSplineSurface3D,
                                          range: ScalarInterval, pair: OverlapRegularGraphCell.Pair,
                                          box: SurfaceParameterBox, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self? {
        guard surface.uDegree == 1, surface.vDegree == 1,
              surface.uControlPointCount == 2, surface.vControlPointCount == 2,
              surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) else { return nil }
        // These scans belong to the already charged original tensor admission.
        for primary in [pair.first, pair.second] {
            let secondary = primary == pair.first ? pair.second : pair.first
            for variesU in [true, false] {
                // Seven bounded exact coefficient operations, including the diagonal product.
                try policy.work(7, using: &execution)
                func coordinate(_ row: Int, _ column: Int, _ axis: Int) -> Double {
                    OverlapRegularGraphCell.coordinate(surface.controlPoints[row][column], axis)
                }
                let p00 = coordinate(0, 0, primary), p10 = coordinate(0, 1, primary)
                let p01 = coordinate(1, 0, primary), p11 = coordinate(1, 1, primary)
                guard variesU ? (p00 == p01 && p10 == p11) : (p00 == p10 && p01 == p11) else { continue }
                let q00 = coordinate(0, 0, secondary), q10 = coordinate(0, 1, secondary)
                let q01 = coordinate(1, 0, secondary), q11 = coordinate(1, 1, secondary)
                let mixed = try Exact.subtract(Exact.difference(q11, q10, policy.tolerance, using: &execution),
                    Exact.difference(q01, q00, policy.tolerance, using: &execution), policy.tolerance, using: &execution)
                guard try FloatingPointExpansion.sign(mixed, using: &execution) == .zero else { continue }
                let a = try Exact.difference(variesU ? p10 : p01, p00, policy.tolerance, using: &execution)
                let b = try Exact.difference(variesU ? q10 : q01, q00, policy.tolerance, using: &execution)
                let c = try Exact.difference(variesU ? q01 : q10, q00, policy.tolerance, using: &execution)
                let determinant = try Exact.product(a, c, policy.tolerance, using: &execution)
                let sign = try FloatingPointExpansion.sign(determinant, using: &execution)
                guard sign == .positive || sign == .negative else { continue }
                let fee = source.controlPointCount.multipliedReportingOverflow(by: 8)
                guard !fee.overflow else { throw Exact.failure(policy.tolerance) }
                // Complete pullback comparisons are paid before coefficient arrays grow.
                try policy.work(fee.partialValue, using: &execution)
                var start: SurfaceParameter?, end: SurfaceParameter?
                for index in 0..<source.controlPointCount {
                    guard source.weights[index].isFinite, source.weights[index] > 0 else { return nil }
                    let point = source.controlPoints[index]
                    let p = try Exact.difference(OverlapRegularGraphCell.coordinate(point, primary), p00, policy.tolerance, using: &execution)
                    let q = try Exact.difference(OverlapRegularGraphCell.coordinate(point, secondary), q00, policy.tolerance, using: &execution)
                    let first = try Exact.product(p, c, policy.tolerance, using: &execution)
                    let second = try Exact.subtract(Exact.product(a, q, policy.tolerance, using: &execution),
                        Exact.product(b, p, policy.tolerance, using: &execution), policy.tolerance, using: &execution)
                    let firstUpper = try Exact.subtract(first, determinant, policy.tolerance, using: &execution)
                    let secondUpper = try Exact.subtract(second, determinant, policy.tolerance, using: &execution)
                    func inside(_ value: [Double], _ upper: [Double]) throws -> Bool {
                        let lowerSign = try FloatingPointExpansion.sign(value, using: &execution)
                        let upperSign = try FloatingPointExpansion.sign(upper, using: &execution)
                        return sign == .positive ? lowerSign != .negative && upperSign != .positive
                            : lowerSign != .positive && upperSign != .negative
                    }
                    guard try inside(first, firstUpper), try inside(second, secondUpper) else { return nil }
                    func endpoint(_ value: [Double], _ upper: [Double], _ axis: ScalarInterval) throws -> Double? {
                        if try FloatingPointExpansion.sign(value, using: &execution) == .zero { return axis.lower }
                        if try FloatingPointExpansion.sign(upper, using: &execution) == .zero { return axis.upper }
                        return nil
                    }
                    if let firstEnd = try endpoint(first, firstUpper, variesU ? box.u : box.v),
                       let secondEnd = try endpoint(second, secondUpper, variesU ? box.v : box.u) {
                        let uv = SurfaceParameter(u: variesU ? firstEnd : secondEnd, v: variesU ? secondEnd : firstEnd)
                        if index == 0 { start = uv }
                        if index == source.controlPointCount - 1 { end = uv }
                    }
                }
                return Self(curve: source, surface: surface, range: range, pair: pair, box: box,
                    mapping: .triangular(Triangular(primaryCoordinate: primary, secondaryCoordinate: secondary,
                        primaryVariesU: variesU, primaryDiagonal: a, shear: b, secondaryDiagonal: c, start: start, end: end)))
            }
        }
        return nil
    }

    /// A fixed-size expansion certificate. Every product's least original bit
    /// must be representable; finite rounded zero never supplies exact equality.
    private enum Exact {
        // Two differences have at most two components each; cofactor products
        // and their comparisons contain at most 24 components. This fixed 64
        // capacity also bounds all transient accumulation, without a new allowance.
        static let maximumComponents = 64
        static let safeMagnitude = Double.greatestFiniteMagnitude / 128

        static func failure(_ tolerance: ModelingTolerance) -> KernelError {
            KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original triangular-chart arithmetic has no bounded exact finite expansion.")
        }

        static func checked(_ value: [Double], _ tolerance: ModelingTolerance) throws -> [Double] {
            guard value.count <= maximumComponents,
                  value.allSatisfy({ $0.isFinite && abs($0) <= safeMagnitude }) else { throw failure(tolerance) }
            return value
        }

        static func difference(_ first: Double, _ second: Double,
                               _ tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Double] {
            guard first.isFinite, second.isFinite, abs(first) <= safeMagnitude,
                  abs(second) <= safeMagnitude else { throw failure(tolerance) }
            return try checked(FloatingPointExpansion.difference(first, second, using: &execution), tolerance)
        }

        static func subtract(_ first: [Double], _ second: [Double],
                             _ tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Double] {
            _ = try checked(first, tolerance); _ = try checked(second, tolerance)
            guard first.count + second.count <= maximumComponents else { throw failure(tolerance) }
            return try checked(FloatingPointExpansion.subtract(first, second, using: &execution), tolerance)
        }

        static func product(_ first: [Double], _ second: [Double],
                            _ tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Double] {
            _ = try checked(first, tolerance); _ = try checked(second, tolerance)
            guard first.count * second.count * 2 <= maximumComponents else { throw failure(tolerance) }
            for a in first where a != 0 {
                for b in second where b != 0 {
                    guard let left = DyadicFactor(abs(a)), let right = DyadicFactor(abs(b)),
                          left.exponent + right.exponent >= -1074,
                          (a * 134_217_729).isFinite, (b * 134_217_729).isFinite,
                          (a * b).isFinite, abs(a * b) <= safeMagnitude else { throw failure(tolerance) }
                }
            }
            return try checked(FloatingPointExpansion.product(first, second, using: &execution), tolerance)
        }
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
