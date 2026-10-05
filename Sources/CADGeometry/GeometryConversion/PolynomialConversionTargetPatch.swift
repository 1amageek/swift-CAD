import CADCore

/// Outward polynomials derived directly from original stored Cartesian controls.
struct PolynomialConversionTargetPatch: Sendable {
    typealias Vector = GeometryConversionCertification.VectorBounds
    let u: ScalarInterval
    let v: ScalarInterval
    let uDegree: Int
    let vDegree: Int
    private let origin: Point3D
    private let coefficients: [Vector]
    private let inverseU: OutwardScalarInterval
    private let inverseV: OutwardScalarInterval

    init(u: ScalarInterval, v: ScalarInterval, uDegree: Int, vDegree: Int,
         point: (Int, Int) -> Point3D) throws {
        self.u = u; self.v = v; self.uDegree = uDegree; self.vDegree = vDegree
        origin = point(0, 0)
        guard let inverseU = OutwardScalarInterval.exact(1).divided(by: .exact(u.upper) - .exact(u.lower)),
              let inverseV = OutwardScalarInterval.exact(1).divided(by: .exact(v.upper) - .exact(v.lower)) else {
            throw GeometryConversionError.invalidInput("Polynomial target spans require positive representable native widths.")
        }
        self.inverseU = inverseU; self.inverseV = inverseV
        var values: [Vector] = []
        values.reserveCapacity((uDegree + 1) * (vDegree + 1))
        for j in 0...vDegree {
            try Task.checkCancellation()
            for i in 0...uDegree {
                var value = Self.zero
                for b in 0...j {
                    for a in 0...i {
                        let stored = point(a, b)
                        let difference = Vector(x: .exact(stored.x) - .exact(origin.x),
                            y: .exact(stored.y) - .exact(origin.y), z: .exact(stored.z) - .exact(origin.z))
                        let integer = Self.binomial(uDegree, i) * Self.binomial(vDegree, j)
                            * Self.binomial(i, a) * Self.binomial(j, b)
                        let factor = (i + j - a - b).isMultiple(of: 2) ? integer : -integer
                        value = value + difference * .exact(Double(factor))
                    }
                }
                values.append(value)
            }
        }
        coefficients = values
    }

    func derivative(uOrder: Int, vOrder: Int, over box: SurfaceParameterBox) throws -> Vector {
        guard uOrder <= uDegree, vOrder <= vDegree else { return Self.zero }
        let localU = (OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper) - .exact(u.lower)) * inverseU
        let localV = (OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper) - .exact(v.lower)) * inverseV
        var value = Self.zero
        for j in stride(from: vDegree, through: vOrder, by: -1) {
            var row = Self.zero
            for i in stride(from: uDegree, through: uOrder, by: -1) {
                let factor = Self.falling(i, uOrder) * Self.falling(j, vOrder)
                row = row * localU + coefficients[j * (uDegree + 1) + i] * .exact(Double(factor))
            }
            value = value * localV + row
        }
        var scale = OutwardScalarInterval.exact(1)
        for _ in 0..<uOrder { scale = scale * inverseU }
        for _ in 0..<vOrder { scale = scale * inverseV }
        value = value * scale
        if uOrder == 0 && vOrder == 0 {
            value = value + Vector(x: .exact(origin.x), y: .exact(origin.y), z: .exact(origin.z))
        }
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Polynomial target evaluation exceeded finite interval arithmetic.")
        }
        return value
    }

    static func coordinates(_ value: Vector) throws -> CoordinateEnclosure3D {
        .init(x: try ScalarInterval(lower: value.x.lower, upper: value.x.upper),
            y: try ScalarInterval(lower: value.y.lower, upper: value.y.upper),
            z: try ScalarInterval(lower: value.z.lower, upper: value.z.upper))
    }

    static func chargePreparation(uDegree: Int, vDegree: Int, patches: Int,
                                 knots: Int, budget: inout GeometryConversionBudget) throws {
        let count = try GeometryConversionBudget.product(uDegree + 1, vDegree + 1)
        let owner = (MemoryLayout<Self>.stride + 7) / 8
        var terms = 0
        for j in 0...vDegree {
            for i in 0...uDegree { terms += (i + 1) * (j + 1) }
        }
        // Per term: three interval products (12 scratch doubles), input subtraction,
        // accumulation, integer factors and loop/index work. Coefficients retain six doubles.
        let scalars = count * 6 + terms * 12 + owner * 4 + 12
        let work = terms * 96 + count * 12 + owner * 4 + knots * 8 + 64
        try budget.charge(scalars: GeometryConversionBudget.product(patches, scalars),
            work: GeometryConversionBudget.product(patches, work))
    }

    static func chargeProbe(uDegree: Int, vDegree: Int, curve: Bool,
                           patches: Int, scans: Int, budget: inout GeometryConversionBudget) throws {
        var scalars = 0, work = 0
        for index in 0..<(curve ? 3 : 6) {
            let uOrder: Int, vOrder: Int
            if curve { uOrder = index; vOrder = 0 }
            else {
                switch index {
                case 0: uOrder = 0; vOrder = 0
                case 1: uOrder = 1; vOrder = 0
                case 2: uOrder = 0; vOrder = 1
                case 3: uOrder = 2; vOrder = 0
                case 4: uOrder = 1; vOrder = 1
                default: uOrder = 0; vOrder = 2
                }
            }
            guard uOrder <= uDegree, vOrder <= vDegree else { continue }
            let rows = vDegree - vOrder + 1
            let terms = rows * (uDegree - uOrder + 1)
            // Two vector products per Horner term, one per row and final scaling;
            // scalar chart/scaling products and the returned/working value payloads.
            let products = terms * 2 + rows + 1
            scalars += products * 12 + (2 + uOrder + vOrder) * 4
                + (MemoryLayout<Vector>.stride * 3 + 7) / 8 + 12
            work += products * 48 + terms * 24 + rows * 12 + 64
        }
        try budget.charge(scalars: GeometryConversionBudget.product(patches, scalars),
            work: GeometryConversionBudget.product(patches, work))
        try budget.charge(work: GeometryConversionBudget.product(scans, 8))
    }

    private static var zero: Vector { .init(x: .exact(0), y: .exact(0), z: .exact(0)) }
    private static func falling(_ n: Int, _ order: Int) -> Int {
        switch order { case 0: 1; case 1: n; default: n * (n - 1) }
    }
    private static func binomial(_ n: Int, _ k: Int) -> Int {
        if k == 0 || k == n { return 1 }
        return switch (n, k) {
        case (2, 1): 2
        case (3, 1), (3, 2): 3
        default: 1
        }
    }
}
