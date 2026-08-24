import CADCore
import Foundation

private enum SurfaceTaylorJetError: Error, Sendable {
    case invalidOrder(Int)
    case invalidCoefficientIndex(uOrder: Int, vOrder: Int, order: Int)
    case incompatibleOrders(first: Int, second: Int)
}

/// A finite bivariate Taylor expansion whose coefficients include factorial scaling.
///
/// The coefficient at `(uOrder, vOrder)` is the corresponding parameter
/// derivative divided by `uOrder! * vOrder!`. This representation makes product
/// and quotient composition exact up to the requested total order.
struct SurfaceTaylorScalarJet: Sendable {
    let order: Int
    private var coefficients: [Double]

    init(order: Int, repeating value: Double = 0.0) throws {
        guard order >= 0, order <= 16 else {
            throw SurfaceTaylorJetError.invalidOrder(order)
        }
        self.order = order
        coefficients = Array(
            repeating: value,
            count: (order + 1) * (order + 1)
        )
    }

    subscript(uOrder: Int, vOrder: Int) -> Double {
        get {
            guard uOrder >= 0,
                  vOrder >= 0,
                  uOrder + vOrder <= order else {
                return 0.0
            }
            return coefficients[uOrder * (order + 1) + vOrder]
        }
    }

    mutating func setCoefficient(
        _ value: Double,
        uOrder: Int,
        vOrder: Int
    ) throws {
        guard uOrder >= 0,
              vOrder >= 0,
              uOrder + vOrder <= order else {
            throw SurfaceTaylorJetError.invalidCoefficientIndex(
                uOrder: uOrder,
                vOrder: vOrder,
                order: order
            )
        }
        coefficients[uOrder * (order + 1) + vOrder] = value
    }

    var value: Double {
        self[0, 0]
    }

    static func constant(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order)
        try result.setCoefficient(value, uOrder: 0, vOrder: 0)
        return result
    }

    static func parameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var result = try constant(value, order: order)
        if order > 0 {
            try result.setCoefficient(1.0, uOrder: 1, vOrder: 0)
        }
        return result
    }

    static func parameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        var result = try constant(value, order: order)
        if order > 0 {
            try result.setCoefficient(1.0, uOrder: 0, vOrder: 1)
        }
        return result
    }

    static func sineOfParameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: true, alongU: true)
    }

    static func cosineOfParameterU(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: false, alongU: true)
    }

    static func sineOfParameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: true, alongU: false)
    }

    static func cosineOfParameterV(
        _ value: Double,
        order: Int
    ) throws -> SurfaceTaylorScalarJet {
        try parameterTrigonometricJet(value: value, order: order, sine: false, alongU: false)
    }

    static func + (
        lhs: SurfaceTaylorScalarJet,
        rhs: SurfaceTaylorScalarJet
    ) throws -> SurfaceTaylorScalarJet {
        guard lhs.order == rhs.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: lhs.order,
                second: rhs.order
            )
        }
        var result = try SurfaceTaylorScalarJet(order: lhs.order)
        for totalOrder in 0...lhs.order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    lhs[uOrder, vOrder] + rhs[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    static func - (
        lhs: SurfaceTaylorScalarJet,
        rhs: SurfaceTaylorScalarJet
    ) throws -> SurfaceTaylorScalarJet {
        try lhs + (-rhs)
    }

    static prefix func - (
        value: SurfaceTaylorScalarJet
    ) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: value.order)
        for totalOrder in 0...value.order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    -value[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    static func * (
        lhs: SurfaceTaylorScalarJet,
        rhs: SurfaceTaylorScalarJet
    ) throws -> SurfaceTaylorScalarJet {
        guard lhs.order == rhs.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: lhs.order,
                second: rhs.order
            )
        }
        var result = try SurfaceTaylorScalarJet(order: lhs.order)
        for totalOrder in 0...lhs.order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                var coefficient = 0.0
                for lhsUOrder in 0...uOrder {
                    for lhsVOrder in 0...vOrder {
                        coefficient += lhs[lhsUOrder, lhsVOrder]
                            * rhs[uOrder - lhsUOrder, vOrder - lhsVOrder]
                    }
                }
                try result.setCoefficient(
                    coefficient,
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    func reciprocal(tolerance: ModelingTolerance) throws -> SurfaceTaylorScalarJet {
        guard value.isFinite, abs(value) > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: value,
                tolerance: tolerance,
                message: "A procedural surface Taylor quotient has a singular denominator."
            )
        }
        var result = try SurfaceTaylorScalarJet(order: order)
        try result.setCoefficient(1.0 / value, uOrder: 0, vOrder: 0)
        if order > 0 {
            for totalOrder in 1...order {
                for uOrder in 0...totalOrder {
                    let vOrder = totalOrder - uOrder
                    var accumulated = 0.0
                    for sourceUOrder in 0...uOrder {
                        for sourceVOrder in 0...vOrder {
                            guard sourceUOrder + sourceVOrder > 0 else {
                                continue
                            }
                            accumulated += self[sourceUOrder, sourceVOrder]
                                * result[
                                    uOrder - sourceUOrder,
                                    vOrder - sourceVOrder
                                ]
                        }
                    }
                    try result.setCoefficient(
                        -accumulated / value,
                        uOrder: uOrder,
                        vOrder: vOrder
                    )
                }
            }
        }
        return result
    }

    func squareRoot(tolerance: ModelingTolerance) throws -> SurfaceTaylorScalarJet {
        guard value.isFinite, value > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: value,
                tolerance: tolerance,
                message: "A procedural surface normal requires a positive finite squared magnitude."
            )
        }
        let root = sqrt(value)
        guard root.isFinite, root > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: root,
                tolerance: tolerance,
                message: "A procedural surface normal is singular at the requested parameter."
            )
        }
        var result = try SurfaceTaylorScalarJet(order: order)
        try result.setCoefficient(root, uOrder: 0, vOrder: 0)
        if order > 0 {
            for totalOrder in 1...order {
                for uOrder in 0...totalOrder {
                    let vOrder = totalOrder - uOrder
                    var nonlinearTerms = 0.0
                    for leftUOrder in 0...uOrder {
                        for leftVOrder in 0...vOrder {
                            let rightUOrder = uOrder - leftUOrder
                            let rightVOrder = vOrder - leftVOrder
                            let leftIsConstant = leftUOrder == 0 && leftVOrder == 0
                            let rightIsConstant = rightUOrder == 0 && rightVOrder == 0
                            guard !leftIsConstant, !rightIsConstant else {
                                continue
                            }
                            nonlinearTerms += result[leftUOrder, leftVOrder]
                                * result[rightUOrder, rightVOrder]
                        }
                    }
                    try result.setCoefficient(
                        (self[uOrder, vOrder] - nonlinearTerms) / (2.0 * root),
                        uOrder: uOrder,
                        vOrder: vOrder
                    )
                }
            }
        }
        return result
    }

    func truncated(to requestedOrder: Int) throws -> SurfaceTaylorScalarJet {
        guard requestedOrder >= 0, requestedOrder <= order else {
            throw SurfaceTaylorJetError.invalidOrder(requestedOrder)
        }
        var result = try SurfaceTaylorScalarJet(order: requestedOrder)
        for totalOrder in 0...requestedOrder {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    self[uOrder, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    func partialU() throws -> SurfaceTaylorScalarJet {
        guard order > 0 else {
            throw SurfaceTaylorJetError.invalidOrder(order - 1)
        }
        var result = try SurfaceTaylorScalarJet(order: order - 1)
        for totalOrder in 0..<order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    Double(uOrder + 1) * self[uOrder + 1, vOrder],
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    func partialV() throws -> SurfaceTaylorScalarJet {
        guard order > 0 else {
            throw SurfaceTaylorJetError.invalidOrder(order - 1)
        }
        var result = try SurfaceTaylorScalarJet(order: order - 1)
        for totalOrder in 0..<order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                try result.setCoefficient(
                    Double(vOrder + 1) * self[uOrder, vOrder + 1],
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return result
    }

    private static func parameterTrigonometricJet(
        value: Double,
        order: Int,
        sine: Bool,
        alongU: Bool
    ) throws -> SurfaceTaylorScalarJet {
        var result = try SurfaceTaylorScalarJet(order: order)
        for derivativeOrder in 0...order {
            let phase = value + Double(derivativeOrder) * Double.pi * 0.5
            let derivative = sine ? sin(phase) : cos(phase)
            let coefficient = derivative / Double(surfaceFactorial(derivativeOrder))
            if alongU {
                try result.setCoefficient(
                    coefficient,
                    uOrder: derivativeOrder,
                    vOrder: 0
                )
            } else {
                try result.setCoefficient(
                    coefficient,
                    uOrder: 0,
                    vOrder: derivativeOrder
                )
            }
        }
        return result
    }
}

struct SurfaceTaylorVectorJet: Sendable {
    let x: SurfaceTaylorScalarJet
    let y: SurfaceTaylorScalarJet
    let z: SurfaceTaylorScalarJet

    init(
        x: SurfaceTaylorScalarJet,
        y: SurfaceTaylorScalarJet,
        z: SurfaceTaylorScalarJet
    ) throws {
        guard x.order == y.order, y.order == z.order else {
            throw SurfaceTaylorJetError.incompatibleOrders(
                first: x.order,
                second: min(y.order, z.order)
            )
        }
        self.x = x
        self.y = y
        self.z = z
    }

    var order: Int {
        x.order
    }

    var value: Vector3D {
        Vector3D(x: x.value, y: y.value, z: z.value)
    }

    static func constant(
        _ point: Point3D,
        order: Int
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: .constant(point.x, order: order),
            y: .constant(point.y, order: order),
            z: .constant(point.z, order: order)
        )
    }

    static func constant(
        _ vector: Vector3D,
        order: Int
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: .constant(vector.x, order: order),
            y: .constant(vector.y, order: order),
            z: .constant(vector.z, order: order)
        )
    }

    static func + (
        lhs: SurfaceTaylorVectorJet,
        rhs: SurfaceTaylorVectorJet
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            z: lhs.z + rhs.z
        )
    }

    static func - (
        lhs: SurfaceTaylorVectorJet,
        rhs: SurfaceTaylorVectorJet
    ) throws -> SurfaceTaylorVectorJet {
        try lhs + (-rhs)
    }

    static prefix func - (
        value: SurfaceTaylorVectorJet
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(x: -value.x, y: -value.y, z: -value.z)
    }

    static func * (
        lhs: SurfaceTaylorVectorJet,
        rhs: SurfaceTaylorScalarJet
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: lhs.x * rhs,
            y: lhs.y * rhs,
            z: lhs.z * rhs
        )
    }

    func dot(
        _ other: SurfaceTaylorVectorJet
    ) throws -> SurfaceTaylorScalarJet {
        try x * other.x + y * other.y + z * other.z
    }

    func cross(
        _ other: SurfaceTaylorVectorJet
    ) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    func normalized(tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        let squaredLength = try dot(self)
        let length = try squaredLength.squareRoot(tolerance: tolerance)
        let reciprocalLength = try length.reciprocal(tolerance: tolerance)
        return try self * reciprocalLength
    }

    func truncated(to requestedOrder: Int) throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.truncated(to: requestedOrder),
            y: y.truncated(to: requestedOrder),
            z: z.truncated(to: requestedOrder)
        )
    }

    func partialU() throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.partialU(),
            y: y.partialU(),
            z: z.partialU()
        )
    }

    func partialV() throws -> SurfaceTaylorVectorJet {
        try SurfaceTaylorVectorJet(
            x: x.partialV(),
            y: y.partialV(),
            z: z.partialV()
        )
    }

    func derivative(uOrder: Int, vOrder: Int) -> Vector3D {
        let scale = Double(surfaceFactorial(uOrder) * surfaceFactorial(vOrder))
        return Vector3D(
            x: x[uOrder, vOrder] * scale,
            y: y[uOrder, vOrder] * scale,
            z: z[uOrder, vOrder] * scale
        )
    }
}

extension Surface3D {
    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        guard order >= 0, order <= 16 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(order),
                tolerance: tolerance,
                message: "Surface Taylor evaluation supports total derivative order zero through sixteen."
            )
        }
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            let basis = try circleOrthonormalBasis(
                plane.normal,
                tolerance: tolerance
            )
            let origin = try SurfaceTaylorVectorJet.constant(plane.origin, order: order)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let parameterU = try SurfaceTaylorScalarJet.parameterU(u, order: order)
            let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order)
            return try origin + uDirection * parameterU + vDirection * parameterV
        case let .cylinder(cylinder):
            let basis = try circleOrthonormalBasis(
                cylinder.axis,
                tolerance: tolerance
            )
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let cosineU = try SurfaceTaylorScalarJet.cosineOfParameterU(u, order: order)
            let sineU = try SurfaceTaylorScalarJet.sineOfParameterU(u, order: order)
            let radial = try uDirection * cosineU + vDirection * sineU
            let origin = try SurfaceTaylorVectorJet.constant(cylinder.origin, order: order)
            let radius = try SurfaceTaylorScalarJet.constant(cylinder.radius, order: order)
            let axis = try SurfaceTaylorVectorJet.constant(cylinder.axis, order: order)
            let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order)
            return try origin + radial * radius + axis * parameterV
        case let .analytic(surface):
            return try surface.taylorJet(
                atU: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            )
        case let .bSpline(surface):
            return try surface.taylorJet(
                atU: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            )
        case let .procedural(surface):
            return try surface.taylorJet(
                atU: u,
                v: v,
                throughOrder: order,
                tolerance: tolerance
            )
        }
    }
}

private extension AnalyticSurface3D {
    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        let parameterU = try SurfaceTaylorScalarJet.parameterU(u, order: order)
        let parameterV = try SurfaceTaylorScalarJet.parameterV(v, order: order)
        let sineU = try SurfaceTaylorScalarJet.sineOfParameterU(u, order: order)
        let cosineU = try SurfaceTaylorScalarJet.cosineOfParameterU(u, order: order)
        let sineV = try SurfaceTaylorScalarJet.sineOfParameterV(v, order: order)
        let cosineV = try SurfaceTaylorScalarJet.cosineOfParameterV(v, order: order)
        switch self {
        case let .plane(origin, normal):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            let originJet = try SurfaceTaylorVectorJet.constant(origin, order: order)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            return try originJet + uDirection * parameterU + vDirection * parameterV
        case let .cylinder(origin, axis, radius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let radial = try uDirection * cosineU + vDirection * sineU
            let originJet = try SurfaceTaylorVectorJet.constant(origin, order: order)
            let radiusJet = try SurfaceTaylorScalarJet.constant(radius, order: order)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order)
            return try originJet + radial * radiusJet + axisJet * parameterV
        case let .cone(apex, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let radial = try uDirection * cosineU + vDirection * sineU
            let apexJet = try SurfaceTaylorVectorJet.constant(apex, order: order)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order)
            let axialScale = try parameterV
                * SurfaceTaylorScalarJet.constant(cos(halfAngle), order: order)
            let radialScale = try parameterV
                * SurfaceTaylorScalarJet.constant(sin(halfAngle), order: order)
            return try apexJet + axisJet * axialScale + radial * radialScale
        case let .sphere(center, radius):
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let radial = try uDirection * cosineU + vDirection * sineU
            let vertical = try SurfaceTaylorVectorJet.constant(.unitZ, order: order)
            let direction = try radial * cosineV + vertical * sineV
            let centerJet = try SurfaceTaylorVectorJet.constant(center, order: order)
            let radiusJet = try SurfaceTaylorScalarJet.constant(radius, order: order)
            return try centerJet + direction * radiusJet
        case let .torus(center, axis, majorRadius, minorRadius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let uDirection = try SurfaceTaylorVectorJet.constant(basis.u, order: order)
            let vDirection = try SurfaceTaylorVectorJet.constant(basis.v, order: order)
            let radial = try uDirection * cosineU + vDirection * sineU
            let majorRadiusJet = try SurfaceTaylorScalarJet.constant(
                majorRadius,
                order: order
            )
            let minorRadiusJet = try SurfaceTaylorScalarJet.constant(
                minorRadius,
                order: order
            )
            let radialDistance = try majorRadiusJet + minorRadiusJet * cosineV
            let centerJet = try SurfaceTaylorVectorJet.constant(center, order: order)
            let axisJet = try SurfaceTaylorVectorJet.constant(axis, order: order)
            return try centerJet + radial * radialDistance
                + axisJet * (minorRadiusJet * sineV)
        }
    }
}

private extension BSplineSurface3D {
    struct TaylorHomogeneousDerivative {
        let vector: Vector3D
        let weight: Double
    }

    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        let clampedU = BSplineBasis.clampedParameter(
            u,
            knots: uKnots,
            degree: uDegree
        )
        let clampedV = BSplineBasis.clampedParameter(
            v,
            knots: vKnots,
            degree: vDegree
        )
        let uBasis = (0...order).map { derivativeOrder in
            BSplineBasis.derivativeValues(
                parameter: clampedU,
                degree: uDegree,
                derivativeOrder: derivativeOrder,
                knots: uKnots,
                count: uControlPointCount
            )
        }
        let vBasis = (0...order).map { derivativeOrder in
            BSplineBasis.derivativeValues(
                parameter: clampedV,
                degree: vDegree,
                derivativeOrder: derivativeOrder,
                knots: vKnots,
                count: vControlPointCount
            )
        }
        let dimension = order + 1
        func key(_ uOrder: Int, _ vOrder: Int) -> Int {
            uOrder * dimension + vOrder
        }
        var homogeneous: [Int: TaylorHomogeneousDerivative] = [:]
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                var vector = Vector3D.zero
                var weight = 0.0
                for vIndex in 0..<vControlPointCount {
                    for uIndex in 0..<uControlPointCount {
                        let basisValue = uBasis[uOrder][uIndex]
                            * vBasis[vOrder][vIndex]
                        guard basisValue != 0.0 else {
                            continue
                        }
                        let controlWeight = weights[vIndex][uIndex]
                        let coefficient = basisValue * controlWeight
                        let point = controlPoints[vIndex][uIndex]
                        vector = vector + Vector3D(
                            x: point.x,
                            y: point.y,
                            z: point.z
                        ) * coefficient
                        weight += coefficient
                    }
                }
                homogeneous[key(uOrder, vOrder)] = TaylorHomogeneousDerivative(
                    vector: vector,
                    weight: weight
                )
            }
        }
        guard let base = homogeneous[key(0, 0)],
              base.weight.isFinite,
              base.weight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: homogeneous[key(0, 0)]?.weight,
                tolerance: tolerance,
                message: "Rational B-spline Taylor evaluation requires a positive finite weight."
            )
        }
        var euclidean: [Int: Vector3D] = [:]
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                guard let source = homogeneous[key(uOrder, vOrder)] else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "A required homogeneous Taylor derivative is missing."
                    )
                }
                var numerator = source.vector
                for weightUOrder in 0...uOrder {
                    for weightVOrder in 0...vOrder {
                        guard weightUOrder + weightVOrder > 0 else {
                            continue
                        }
                        guard let weightDerivative = homogeneous[
                            key(weightUOrder, weightVOrder)
                        ]?.weight,
                        let lowerDerivative = euclidean[
                            key(
                                uOrder - weightUOrder,
                                vOrder - weightVOrder
                            )
                        ] else {
                            throw KernelError(
                                phase: .geometry,
                                code: .invalidInput,
                                tolerance: tolerance,
                                message: "Rational Taylor derivative recurrence is incomplete."
                            )
                        }
                        let coefficient = Double(
                            surfaceBinomial(uOrder, weightUOrder)
                                * surfaceBinomial(vOrder, weightVOrder)
                        )
                        numerator = numerator
                            - lowerDerivative * (coefficient * weightDerivative)
                    }
                }
                let derivative = numerator / base.weight
                guard derivative.isFinite else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Rational B-spline Taylor evaluation exceeded the finite numeric range."
                    )
                }
                euclidean[key(uOrder, vOrder)] = derivative
            }
        }

        var x = try SurfaceTaylorScalarJet(order: order)
        var y = try SurfaceTaylorScalarJet(order: order)
        var z = try SurfaceTaylorScalarJet(order: order)
        for totalOrder in 0...order {
            for uOrder in 0...totalOrder {
                let vOrder = totalOrder - uOrder
                guard let derivative = euclidean[key(uOrder, vOrder)] else {
                    continue
                }
                let scale = Double(
                    surfaceFactorial(uOrder) * surfaceFactorial(vOrder)
                )
                try x.setCoefficient(
                    derivative.x / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                )
                try y.setCoefficient(
                    derivative.y / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                )
                try z.setCoefficient(
                    derivative.z / scale,
                    uOrder: uOrder,
                    vOrder: vOrder
                )
            }
        }
        return try SurfaceTaylorVectorJet(x: x, y: y, z: z)
    }
}

private func surfaceFactorial(_ value: Int) -> Int {
    guard value > 1 else {
        return 1
    }
    return (2...value).reduce(1, *)
}

private func surfaceBinomial(_ n: Int, _ k: Int) -> Int {
    guard k >= 0, k <= n else {
        return 0
    }
    let effectiveK = min(k, n - k)
    guard effectiveK > 0 else {
        return 1
    }
    var result = 1
    for index in 1...effectiveK {
        result = result * (n - effectiveK + index) / index
    }
    return result
}
