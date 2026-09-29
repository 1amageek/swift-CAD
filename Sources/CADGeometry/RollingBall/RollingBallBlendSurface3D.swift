import CADCore
import Foundation

// FIXME(INCOMPLETE_IMPLEMENTATION): This value evaluates blend geometry but is
// registered in Surface3D but not yet integrated with FeatureEvaluating.
// Its construction callers are RollingBallSectionEvaluator and geometry tests.
// Persistent surface integration, full-domain regularity and trimmed-solid reconstruction must
// succeed before any fillet feature may publish it.
public struct RollingBallBlendSurface3D: Codable, Hashable, Sendable {
    let centerSpine: Curve3D
    public let firstContact: Curve3D
    public let secondContact: Curve3D
    public let radius: Double
    let tolerance: ModelingTolerance

    private enum CodingKeys: String, CodingKey {
        case centerSpine, firstContact, secondContact, radius, tolerance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys(
            [.centerSpine, .firstContact, .secondContact, .radius, .tolerance], in: decoder
        )
        centerSpine = try values.decode(Curve3D.self, forKey: .centerSpine)
        firstContact = try values.decode(Curve3D.self, forKey: .firstContact)
        secondContact = try values.decode(Curve3D.self, forKey: .secondContact)
        radius = try values.decode(Double.self, forKey: .radius)
        tolerance = try values.decode(ModelingTolerance.self, forKey: .tolerance)
        try validate()
    }

    /// Validates stored geometry; does not certify fillet feasibility.
    public func validate() throws {
        try tolerance.validate()
        guard radius.isFinite, radius > tolerance.distance,
              case .closed(0, 1) = centerSpine.parameterDomain,
              case .closed(0, 1) = firstContact.parameterDomain,
              case .closed(0, 1) = secondContact.parameterDomain else {
            throw failure(.invalidInput, "A blend requires a positive radius and normalized center spine.")
        }
        try centerSpine.validate(tolerance: tolerance)
        try firstContact.validate(tolerance: tolerance)
        try secondContact.validate(tolerance: tolerance)
    }

    public var uDomain: ParameterDomain { .closed(0, 1) }
    public var vDomain: ParameterDomain { .closed(0, 1) }

    func contactBoundaryDeviation(onFirst: Bool) throws -> Double? {
        let contact = onFirst ? firstContact : secondContact
        guard case .surfaceLift(let rail) = contact,
              case .offsetSurfaceImage(let image) = rail.parameterCurve,
              image.isPullback, abs(image.offset.distance) == radius,
              case .surfaceLift(let center) = centerSpine else { return nil }
        try image.validate(on: rail.surface, tolerance: tolerance)
        if center.surface == image.sourceSurface,
           center.parameterCurve == image.source { return 0 }
        guard case .certifiedImplicit(let centerParameters) = center.parameterCurve,
              case .certifiedImplicit(let railParameters) = image.source,
              centerParameters.intersection == railParameters.intersection,
              centerParameters.startFraction == railParameters.startFraction,
              centerParameters.endFraction == railParameters.endFraction else { return nil }
        try centerParameters.validate(on: center.surface, tolerance: tolerance)
        try railParameters.validate(on: image.sourceSurface, tolerance: tolerance)
        // |length(C - P) - r| <= length(C - offset(P)).
        return centerParameters.intersection.maximumResidualUpperBound
    }

    /// Proves a nondegenerate tangent frame, not complete fillet feasibility.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Production machining latency and
    // integration remain unverified. Only geometry tests call this entry;
    // actual selected-edge certification must pass before feature admission.
    public func validateRegularity(
        over parameters: SurfaceParameterBox,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int
    ) throws {
        try DefaultSurfaceRegularityValidator(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount
        ).validate(self, over: parameters)
    }

    // The section evaluator owns complete offset/rail correspondence admission.
    init(centerSpine: Curve3D, firstContact: Curve3D,
         secondContact: Curve3D, radius: Double, tolerance: ModelingTolerance) {
        self.centerSpine = centerSpine
        self.firstContact = firstContact
        self.secondContact = secondContact
        self.radius = radius
        self.tolerance = tolerance
    }

    public func point(u: Double, v: Double) throws -> Point3D {
        try validateParameters(u: u, v: v)
        // The immutable rails were admitted by the section evaluator. Validate
        // parameters here without replaying their complete correspondence proof.
        let center = try centerSpine.pointAssumingValid(at: u, tolerance: tolerance)
        let first = try firstContact.pointAssumingValid(at: u, tolerance: tolerance) - center
        let second = try secondContact.pointAssumingValid(at: u, tolerance: tolerance) - center
        try validateRadials(first, second)
        let a = try first.normalized(tolerance: tolerance.distance)
        let b = try second.normalized(tolerance: tolerance.distance)
        let weight = sqrt((1 + a.dot(b)) * 0.5)
        let s = 1 - v
        let denominator = s * s + 2 * weight * s * v + v * v
        let radial = a * (s * s) + (a + b) * (s * v / weight) + b * (v * v)
        let result = center + radial * (radius / denominator)
        try result.validate()
        return result
    }

    /// Algebraic section in the native V parameter, not an angular refit.
    func rationalSection(atU u: Double) throws -> BSplineCurve3D {
        try validateParameters(u: u, v: 0)
        let center = try centerSpine.pointAssumingValid(at: u, tolerance: tolerance)
        let first = try firstContact.pointAssumingValid(at: u, tolerance: tolerance) - center
        let second = try secondContact.pointAssumingValid(at: u, tolerance: tolerance) - center
        try validateRadials(first, second)
        let a = try first.normalized(tolerance: tolerance.distance)
        let b = try second.normalized(tolerance: tolerance.distance)
        let weight = sqrt((1 + a.dot(b)) * 0.5)
        let result = BSplineCurve3D(
            degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [center + a * radius,
                            center + (a + b) * (radius / (2 * weight * weight)),
                            center + b * radius],
            weights: [1, weight, 1]
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    public func parameterDerivatives(atU u: Double, v: Double) throws -> SurfaceParameterDerivatives {
        let jet = try taylorJet(atU: u, v: v, throughOrder: 2)
        return SurfaceParameterDerivatives(
            position: .origin + jet.value,
            tangentU: jet.derivative(uOrder: 1, vOrder: 0),
            tangentV: jet.derivative(uOrder: 0, vOrder: 1),
            secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
            secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
            secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2)
        )
    }

    public func parameterDerivativesThroughThirdOrder(
        atU u: Double, v: Double
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        let jet = try taylorJet(atU: u, v: v, throughOrder: 3)
        return SurfaceParameterThirdOrderDerivatives(
            position: .origin + jet.value,
            tangentU: jet.derivative(uOrder: 1, vOrder: 0),
            tangentV: jet.derivative(uOrder: 0, vOrder: 1),
            secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
            secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
            secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2),
            thirdDerivativeUUU: jet.derivative(uOrder: 3, vOrder: 0),
            thirdDerivativeUUV: jet.derivative(uOrder: 2, vOrder: 1),
            thirdDerivativeUVV: jet.derivative(uOrder: 1, vOrder: 2),
            thirdDerivativeVVV: jet.derivative(uOrder: 0, vOrder: 3)
        )
    }

    func taylorJet(atU u: Double, v: Double, throughOrder order: Int) throws -> SurfaceTaylorVectorJet {
        try validateParameters(u: u, v: v)
        guard (0...3).contains(order) else {
            throw failure(.invalidInput, "Blend Taylor derivatives support total orders zero through three.")
        }
        if order == 0 { return try .constant(point(u: u, v: v), order: 0) }
        let center = try curveJet(centerSpine, at: u, order: order)
        let first = try curveJet(firstContact, at: u, order: order) - center
        let second = try curveJet(secondContact, at: u, order: order) - center
        try validateRadials(first.value, second.value)
        let a = try first.normalized(tolerance: tolerance)
        let b = try second.normalized(tolerance: tolerance)
        let one = try SurfaceTaylorScalarJet.constant(1, order: order)
        let half = try SurfaceTaylorScalarJet.constant(0.5, order: order)
        let two = try SurfaceTaylorScalarJet.constant(2, order: order)
        let r = try SurfaceTaylorScalarJet.constant(radius, order: order)
        let t = try SurfaceTaylorScalarJet.parameterV(v, order: order)
        let s = try one - t
        let weight = try ((one + a.dot(b)) * half).squareRoot(tolerance: tolerance)
        let inverseWeight = try weight.reciprocal(tolerance: tolerance)
        let radial = try a * (s * s) + (a + b) * (s * t * inverseWeight) + b * (t * t)
        let denominator = try s * s + two * weight * s * t + t * t
        let result = try center + radial * (r * denominator.reciprocal(tolerance: tolerance))
        for total in 0...order {
            for uOrder in 0...total {
                guard result.derivative(uOrder: uOrder, vOrder: total - uOrder).isFinite else {
                    throw failure(.singularSystem, "Blend differentiation exceeded the finite numeric range.")
                }
            }
        }
        return result
    }

    private func curveJet(_ curve: Curve3D, at u: Double, order: Int) throws -> SurfaceTaylorVectorJet {
        let derivatives: [Vector3D]
        if order == 3 {
            let value = try curve.parameterDerivativesThroughThirdOrder(at: u, tolerance: tolerance)
            derivatives = [value.position - .origin, value.firstDerivative, value.secondDerivative, value.thirdDerivative]
        } else {
            let value = try curve.differentialGeometryAssumingValid(at: u, tolerance: tolerance)
            derivatives = [value.position - .origin, value.firstDerivative, value.secondDerivative]
        }
        var x = try SurfaceTaylorScalarJet(order: order)
        var y = try SurfaceTaylorScalarJet(order: order)
        var z = try SurfaceTaylorScalarJet(order: order)
        let factorials = [1.0, 1.0, 2.0, 6.0]
        for index in 0...order {
            let value = derivatives[index] / factorials[index]
            try x.setCoefficient(value.x, uOrder: index, vOrder: 0)
            try y.setCoefficient(value.y, uOrder: index, vOrder: 0)
            try z.setCoefficient(value.z, uOrder: index, vOrder: 0)
        }
        return try SurfaceTaylorVectorJet(x: x, y: y, z: z)
    }

    private func validateParameters(u: Double, v: Double) throws {
        guard u.isFinite, v.isFinite, (0...1).contains(u), (0...1).contains(v) else {
            throw failure(.invalidInput, "Blend evaluation requires normalized U and V parameters.")
        }
    }

    private func validateRadials(_ first: Vector3D, _ second: Vector3D) throws {
        let firstLength = first.length
        let secondLength = second.length
        guard firstLength.isFinite, secondLength.isFinite,
              abs(firstLength - radius) <= tolerance.distance,
              abs(secondLength - radius) <= tolerance.distance else {
            throw failure(.intersectionFailure, "Blend contacts do not lie at the requested radius from the center spine.")
        }
        let a = try first.normalized(tolerance: tolerance.distance)
        let b = try second.normalized(tolerance: tolerance.distance)
        guard 1 + a.dot(b) > 0,
              a.cross(b).length > max(sin(min(tolerance.angle, .pi * 0.5)), tolerance.relative) else {
            throw failure(.singularSystem, "Blend contacts do not define a regular minor arc.")
        }
    }

    func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
