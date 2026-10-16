import CADCore

/// Original-derived interval coefficients on one shared normalized tensor chart.
struct PolynomialSurfacePositionDifferenceNet {
    typealias Coefficient = IntervalVector3DBounds

    enum Arithmetic {
        static func add(_ a: Int, _ b: Int) throws -> Int {
            let value = a.addingReportingOverflow(b)
            guard a >= 0, b >= 0, !value.overflow else { throw exhausted() }
            return value.partialValue
        }

        static func multiply(_ a: Int, _ b: Int) throws -> Int {
            let value = a.multipliedReportingOverflow(by: b)
            guard a >= 0, b >= 0, !value.overflow else { throw exhausted() }
            return value.partialValue
        }

        static func exhausted() -> GeometryConversionError {
            .resourceLimitExceeded("Polynomial continuation could not resolve finite arithmetic, storage dimensions or certification cells.")
        }
    }

    private static func admitCoefficients(_ count: Int, using execution: inout OriginalQueryExecution) throws {
        try execution.charge(scalars: Arithmetic.multiply(count, 6))
        try OriginalCoefficientAllocation.reserve(count: count, of: Coefficient.self, using: &execution)
    }

    let uCount: Int
    let vCount: Int
    private let values: [Coefficient]

    init(original surface: BSplineSurface3D, origin: Point3D, using execution: inout OriginalQueryExecution) throws {
        uCount = surface.uControlPointCount
        vCount = surface.vControlPointCount
        let count = try Arithmetic.multiply(uCount, vCount)
        try Self.admitCoefficients(count, using: &execution)
        try execution.charge(work: Arithmetic.multiply(count, 3 * 4 + 4))
        var coefficients: [Coefficient] = []
        coefficients.reserveCapacity(count)
        for row in surface.controlPoints {
            try CurrentTaskCancellationChecker().checkCancellation()
            for point in row {
                // Exact common stored weights cancel by partition of unity. These
                // original Cartesian controls define the polynomial, without a new Double net.
                coefficients.append(Coefficient(x: .exact(point.x) - .exact(origin.x),
                    y: .exact(point.y) - .exact(origin.y), z: .exact(point.z) - .exact(origin.z)))
            }
        }
        values = coefficients
    }

    /// Internal original-polynomial producer has paid the exact rectangular storage
    /// and populated every interval coefficient before transferring immutable ownership.
    init(prechargedUCount: Int, vCount: Int, values: [Coefficient]) {
        self.uCount = prechargedUCount
        self.vCount = vCount
        self.values = values
    }

    private init(uCount: Int, vCount: Int, values: [Coefficient]) {
        self.uCount = uCount
        self.vCount = vCount
        self.values = values
    }

    func transformed(uLower: OutwardScalarInterval, uUpper: OutwardScalarInterval,
        vLower: OutwardScalarInterval, vUpper: OutwardScalarInterval,
        using execution: inout OriginalQueryExecution) throws -> Self {
        let alongU = try transformedAxis(u: true, lower: uLower, upper: uUpper, using: &execution)
        return try alongU.transformedAxis(u: false, lower: vLower, upper: vUpper, using: &execution)
    }

    private func transformedAxis(u: Bool, lower: OutwardScalarInterval,
        upper: OutwardScalarInterval, using execution: inout OriginalQueryExecution) throws -> Self {
        let count = try Arithmetic.multiply(uCount, vCount)
        try Self.admitCoefficients(count, using: &execution)
        try execution.charge(work: Arithmetic.multiply(count, 8))
        var output = Array(repeating: Coefficient(x: .exact(0), y: .exact(0), z: .exact(0)), count: count)
        let axisCount = u ? uCount : vCount
        let lines = u ? vCount : uCount
        for line in 0..<lines {
            try CurrentTaskCancellationChecker().checkCancellation()
            for index in 0..<axisCount {
                let coefficient = try blossom(degree: axisCount - 1, index: index,
                    lower: lower, upper: upper, using: &execution) { position in
                    values[u ? line * uCount + position : position * uCount + line]
                }
                output[u ? line * uCount + index : index * uCount + line] = coefficient
            }
        }
        return Self(uCount: uCount, vCount: vCount, values: output)
    }

    func elevated(toUCount targetU: Int, vCount targetV: Int, using execution: inout OriginalQueryExecution) throws -> Self {
        var net = self
        while net.uCount < targetU { net = try net.elevatedAxis(u: true, using: &execution) }
        while net.vCount < targetV { net = try net.elevatedAxis(u: false, using: &execution) }
        return net
    }

    private func elevatedAxis(u: Bool, using execution: inout OriginalQueryExecution) throws -> Self {
        let oldCount = u ? uCount : vCount
        let newCount = try Arithmetic.add(oldCount, 1)
        let lines = u ? vCount : uCount
        let count = try Arithmetic.multiply(newCount, lines)
        let interpolations = try Arithmetic.multiply(oldCount - 1, lines)
        try Self.admitCoefficients(count, using: &execution)
        // Each internal elevated coefficient forms one interval ratio (six scratch
        // doubles), one complement and three two-product coordinate interpolations.
        try execution.charge(scalars: Arithmetic.multiply(interpolations, 6 + 24),
            work: Arithmetic.add(Arithmetic.multiply(interpolations, 20 + 4 + 84 + 8),
                Arithmetic.add(Arithmetic.multiply(lines, 4), Arithmetic.multiply(count, 8))))
        var output = Array(repeating: Coefficient(x: .exact(0), y: .exact(0), z: .exact(0)), count: count)
        let outputU = u ? newCount : uCount
        func input(_ index: Int, _ line: Int) -> Coefficient {
            values[u ? line * uCount + index : index * uCount + line]
        }
        for line in 0..<lines {
            try CurrentTaskCancellationChecker().checkCancellation()
            for index in 0..<newCount {
                let coefficient: Coefficient
                if index == 0 { coefficient = input(0, line) }
                else if index == newCount - 1 { coefficient = input(oldCount - 1, line) }
                else {
                    guard let numerator = Double(exactly: index), let denominator = Double(exactly: oldCount),
                          let ratio = OutwardScalarInterval.exact(numerator).divided(by: .exact(denominator)) else {
                        throw Arithmetic.exhausted()
                    }
                    coefficient = Self.interpolate(input(index, line), input(index - 1, line),
                        ratio: ratio, complement: .exact(1) - ratio)
                }
                output[u ? line * outputU + index : index * outputU + line] = coefficient
            }
        }
        return Self(uCount: outputU, vCount: u ? vCount : newCount, values: output)
    }

    func subtracting(_ other: Self, using execution: inout OriginalQueryExecution) throws -> Self {
        guard uCount == other.uCount, vCount == other.vCount else { throw Arithmetic.exhausted() }
        try Self.admitCoefficients(values.count, using: &execution)
        try execution.charge(work: Arithmetic.multiply(values.count, 3 * 4 + 4))
        var result: [Coefficient] = []
        result.reserveCapacity(values.count)
        for index in values.indices {
            try CurrentTaskCancellationChecker().checkCancellation()
            result.append(values[index] - other.values[index])
        }
        return Self(uCount: uCount, vCount: vCount, values: result)
    }

    func maximumCoefficientNorm(using execution: inout OriginalQueryExecution) throws -> Double {
        // Finite checks, absolute bounds, outward scalar squares/sums and sqrt.
        // Scalar norm operations do not allocate interval multiply scratch arrays.
        try execution.charge(work: Arithmetic.multiply(values.count, 48))
        var maximum = 0.0
        for coefficient in values {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard coefficient.x.isFinite, coefficient.y.isFinite, coefficient.z.isFinite else { throw Arithmetic.exhausted() }
            let upper = coefficient.lengthUpperBound
            guard upper.isFinite else { throw Arithmetic.exhausted() }
            maximum = max(maximum, upper)
        }
        return maximum
    }

    func centerNormLowerBound(using execution: inout OriginalQueryExecution) throws -> Double {
        try Self.admitCoefficients(vCount, using: &execution)
        var rows: [Coefficient] = []
        rows.reserveCapacity(vCount)
        for row in 0..<vCount {
            rows.append(try blossom(degree: uCount - 1, index: 0, lower: .exact(0.5),
                upper: .exact(0.5), using: &execution) { values[row * uCount + $0] })
        }
        let center = try blossom(degree: vCount - 1, index: 0, lower: .exact(0.5),
            upper: .exact(0.5), using: &execution) { rows[$0] }
        try execution.charge(work: 48)
        guard center.x.isFinite, center.y.isFinite, center.z.isFinite else { throw Arithmetic.exhausted() }
        let lower = center.lengthLowerBound
        guard lower.isFinite else { throw Arithmetic.exhausted() }
        return lower
    }

    func subdivided(u: Bool, using execution: inout OriginalQueryExecution) throws -> (Self, Self) {
        // Both children are transforms of this same original-derived residual tensor.
        // Source/candidate laws are not re-sampled or prepared independently again.
        if u {
            return (try transformedAxis(u: true, lower: .exact(0), upper: .exact(0.5), using: &execution),
                try transformedAxis(u: true, lower: .exact(0.5), upper: .exact(1), using: &execution))
        }
        return (try transformedAxis(u: false, lower: .exact(0), upper: .exact(0.5), using: &execution),
            try transformedAxis(u: false, lower: .exact(0.5), upper: .exact(1), using: &execution))
    }

    private func blossom(degree: Int, index: Int, lower: OutwardScalarInterval,
        upper: OutwardScalarInterval, using execution: inout OriginalQueryExecution,
        read: (Int) -> Coefficient) throws -> Coefficient {
        var level: [Coefficient]?
        for depth in 0..<degree {
            let count = degree - depth
            // One output coefficient has six scalar fields; two interval products per
            // coordinate generate four-product scratch arrays (24 additional scalars).
            try execution.charge(scalars: Arithmetic.multiply(count, 6 + 24),
                work: Arithmetic.add(Arithmetic.multiply(count, 84 + 8), 4))
            let ratio = depth < degree - index ? lower : upper
            let complement = OutwardScalarInterval.exact(1) - ratio
            var next: [Coefficient] = []
            next.reserveCapacity(count)
            for position in 0..<count {
                let a = level?[position] ?? read(position)
                let b = level?[position + 1] ?? read(position + 1)
                next.append(Self.interpolate(a, b, ratio: ratio, complement: complement))
            }
            level = next
        }
        guard let value = level?.first else { throw Arithmetic.exhausted() }
        return value
    }

    private static func interpolate(_ a: Coefficient, _ b: Coefficient,
        ratio: OutwardScalarInterval, complement: OutwardScalarInterval) -> Coefficient {
        Coefficient(x: a.x * complement + b.x * ratio,
            y: a.y * complement + b.y * ratio, z: a.z * complement + b.z * ratio)
    }
}
