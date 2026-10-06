import CADCore

/// Exact arbitrary-order endpoint factor of an original owning rational tensor.
package struct OriginalExactBSplinePoleNormal: Sendable {
    package let surface: BSplineSurface3D
    package let span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let direction: OriginalBSplinePoleNormal.Direction
    package let factorOrder: Int
    package let coefficients: [ExactBivariatePolynomial]
    private let derivativesU: [ExactBivariatePolynomial]
    private let derivativesV: [ExactBivariatePolynomial]
    private let tolerance: ModelingTolerance

    init<B:RationalAlgebraAdmitting>(original:OriginalRationalSurfacePolynomial,
        span:PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        direction:OriginalBSplinePoleNormal.Direction,boundary:Double,inwardSign:Double,
        tolerance:ModelingTolerance,usage:inout B) throws {
        let alongU = direction == .constantU
        let station = try ExactRationalCoefficient.originalDouble(boundary,usage:&usage)
        var multiplicity:Int?
        for value in original.normalNumerators where !value.isZero {
            let divided = try value.dividedByBoundaryFactor(alongU:alongU,boundary:station,usage:&usage)
            multiplicity = min(multiplicity ?? divided.multiplicity,divided.multiplicity)
        }
        guard let order = multiplicity,order > 0 else {
            throw KernelError(phase:.geometry,code:.singularGeometry,tolerance:tolerance,
                message:"Original tensor normal has no nonzero finite boundary factor authority.")
        }
        let factor = try ExactBivariatePolynomial.coordinate(alongU:alongU,usage:&usage)
            .subtracting(.constant(station,usage:&usage),usage:&usage)
        var power = try ExactBivariatePolynomial.constant(.one,usage:&usage)
        for _ in 0..<order { power = try power.multiplied(by:factor,usage:&usage) }
        let sign = try ExactRationalCoefficient.originalDouble(inwardSign < 0 && order & 1 == 1 ? -1 : 1,usage:&usage)
        var values:[ExactBivariatePolynomial] = [],u:[ExactBivariatePolynomial] = [],v:[ExactBivariatePolynomial] = []
        for originalValue in original.normalNumerators {
            try usage.retainExactStorage(3)
            let value = try originalValue.dividedExactly(by:power,usage:&usage).scaled(by:sign,usage:&usage)
            values.append(value);u.append(try value.differentiated(alongU:true,usage:&usage))
            v.append(try value.differentiated(alongU:false,usage:&usage))
        }
        surface = original.source;self.span = span;self.direction = direction
        factorOrder = order;coefficients = values;derivativesU = u;derivativesV = v;self.tolerance = tolerance
    }

    /// Removes another exact original inward boundary factor from this gauge.
    func removingBoundaryFactor<B: RationalAlgebraAdmitting>(direction: OriginalBSplinePoleNormal.Direction,
        boundary: Double, inwardSign: Double, usage: inout B) throws -> Self {
        let alongU = direction == .constantU
        let station = try ExactRationalCoefficient.originalDouble(boundary, usage: &usage)
        var multiplicity: Int?
        for value in coefficients where !value.isZero {
            let divided = try value.dividedByBoundaryFactor(alongU: alongU, boundary: station, usage: &usage)
            multiplicity = min(multiplicity ?? divided.multiplicity, divided.multiplicity)
        }
        guard let order = multiplicity, order > 0 else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "Original collapsed boundary has no common nonzero normal factor.")
        }
        let factor = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            .subtracting(.constant(station, usage: &usage), usage: &usage)
        var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for _ in 0..<order { power = try power.multiplied(by: factor, usage: &usage) }
        let sign = try ExactRationalCoefficient.originalDouble(inwardSign < 0 && order & 1 == 1 ? -1 : 1, usage: &usage)
        var values: [ExactBivariatePolynomial] = [], u: [ExactBivariatePolynomial] = [], v: [ExactBivariatePolynomial] = []
        for originalValue in coefficients {
            try usage.retainExactStorage(3)
            let value = try originalValue.dividedExactly(by: power, usage: &usage).scaled(by: sign, usage: &usage)
            values.append(value)
            u.append(try value.differentiated(alongU: true, usage: &usage))
            v.append(try value.differentiated(alongU: false, usage: &usage))
        }
        return Self(surface: surface, span: span, direction: self.direction, factorOrder: factorOrder,
            coefficients: values, derivativesU: u, derivativesV: v, tolerance: tolerance)
    }

    private init(surface: BSplineSurface3D,
        span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        direction: OriginalBSplinePoleNormal.Direction, factorOrder: Int,
        coefficients: [ExactBivariatePolynomial], derivativesU: [ExactBivariatePolynomial],
        derivativesV: [ExactBivariatePolynomial], tolerance: ModelingTolerance) {
        self.surface = surface; self.span = span; self.direction = direction; self.factorOrder = factorOrder
        self.coefficients = coefficients; self.derivativesU = derivativesU; self.derivativesV = derivativesV
        self.tolerance = tolerance
    }

    package func panelBounds<B:RationalAlgebraAdmitting>(over box:SurfaceParameterBox,
        tolerance:ModelingTolerance,usage:inout B) throws -> OriginalBSplinePoleNormalPanel {
        guard tolerance == self.tolerance else {
            throw GeometryConversionError.invalidInput("Original exact normal factor requires its preparation tolerance.")
        }
        try span.validate(on:surface,over:box,tolerance:tolerance,consumeWork:{ try usage.consumeExactWork(1) })
        func vector(_ polys:[ExactBivariatePolynomial]) throws -> IntervalVector3DBounds {
            try .init(x:polys[0].enclosure(over:box,usage:&usage),y:polys[1].enclosure(over:box,usage:&usage),z:polys[2].enclosure(over:box,usage:&usage))
        }
        let field = try vector(coefficients),u = try vector(derivativesU),v = try vector(derivativesV)
        let lower = field.lengthLowerBound
        guard lower.isFinite,lower > 0 else {
            throw KernelError(phase:.geometry,code:.singularGeometry,tolerance:tolerance,
                message:"Exact original normal factor is not certified nonzero on this whole owning panel.")
        }
        try usage.consumeExactWork(1)
        let jet = try span.intervalJet(overClosedBox:box,on:surface,tolerance:tolerance,consumeWork:{ try usage.consumeExactWork(1) })
        func position(_ key:(SurfaceIntervalJet) -> OutwardScalarInterval)->Double {
            IntervalVector3DBounds(x:key(jet.x),y:key(jet.y),z:key(jet.z)).lengthUpperBound
        }
        let fields = [position({ $0.derivativeU }),position({ $0.derivativeV }),position({ $0.secondDerivativeUU }),position({ $0.secondDerivativeUV }),position({ $0.secondDerivativeVV }),
            (u.lengthUpperBound/lower).nextUp,(v.lengthUpperBound/lower).nextUp]
        guard fields.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw GeometryConversionError.resourceLimitExceeded("Exact original normal factor derivative arithmetic is nonfinite.")
        }
        return .init(surface:surface,parameters:box,span:span,direction:direction,factorBounds:field,tolerance:tolerance,
            differentialBounds:.init(tangentUMagnitudeUpperBound:fields[0],tangentVMagnitudeUpperBound:fields[1],secondDerivativeUUMagnitudeUpperBound:fields[2],
                secondDerivativeUVMagnitudeUpperBound:fields[3],secondDerivativeVVMagnitudeUpperBound:fields[4],unitNormalDerivativeUMagnitudeUpperBound:fields[5],unitNormalDerivativeVMagnitudeUpperBound:fields[6]))
    }
}
