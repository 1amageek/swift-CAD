import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

// FIXME(INCOMPLETE_IMPLEMENTATION): This value evaluates blend geometry but is
// registered in Surface3D and consumed by ordinary Fillet through the injected
// KernelRollingBallFilletEvaluator composition path. General blend networks,
// all required endpoint/corner domains and whole-solid validity must be established
// before reporting the complete fillet operation.
public struct RollingBallBlendSurface3D: Hashable, Sendable {
    package let centerSpine: Curve3D
    public let firstContact: Curve3D
    public let secondContact: Curve3D
    public let radius: Double
    package let tolerance: ModelingTolerance

    /// Validates stored geometry; does not certify fillet feasibility.
    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try validateConstructionParameters()
        try centerSpine.validate(tolerance: tolerance, using: &execution)
        try firstContact.validate(tolerance: tolerance, using: &execution)
        try secondContact.validate(tolerance: tolerance, using: &execution)
    }

    package func validateConstructionParameters() throws {
        try tolerance.validate()
        guard radius.isFinite, radius > tolerance.distance,
              case .closed(0, 1) = centerSpine.parameterDomain,
              case .closed(0, 1) = firstContact.parameterDomain,
              case .closed(0, 1) = secondContact.parameterDomain else {
            throw failure(.invalidInput, "A blend requires a positive radius and normalized center spine.")
        }
    }

    public var uDomain: ParameterDomain { .closed(0, 1) }
    public var vDomain: ParameterDomain { .closed(0, 1) }

    func contactBoundaryDeviation(onFirst: Bool, using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        let contact = onFirst ? firstContact : secondContact
        guard case .surfaceLift(let rail) = contact,
              case .offsetSurfaceImage(let image) = rail.parameterCurve,
              image.isPullback, abs(image.offset.distance) == radius,
              case .surfaceLift(let center) = centerSpine else { return nil }
        try image.validate(on: rail.surface, tolerance: tolerance, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: center.surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: image.sourceSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: center.parameterCurve, using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: image.source, using: &execution)
        if center.surface == image.sourceSurface,
           center.parameterCurve == image.source { return 0 }
        guard case .certifiedImplicit(let centerParameters) = center.parameterCurve,
              case .certifiedImplicit(let railParameters) = image.source,
              centerParameters.intersection == railParameters.intersection,
              centerParameters.startFraction == railParameters.startFraction,
              centerParameters.endFraction == railParameters.endFraction else { return nil }
        try centerParameters.validate(on: center.surface, tolerance: tolerance, using: &execution)
        try railParameters.validate(on: image.sourceSurface, tolerance: tolerance, using: &execution)
        // |length(C - P) - r| <= length(C - offset(P)).
        return centerParameters.intersection.maximumResidualUpperBound
    }

    /// Proves a nondegenerate tangent frame, not complete fillet feasibility.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Production machining latency and
    // integration remain unverified for the complete mandatory domain. Ordinary
    // kernel fillet composition consumes this geometry; selected-edge certification
    // and whole-solid admission remain required before publication.
    public func validateRegularity(
        over parameters: SurfaceParameterBox,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try DefaultSurfaceRegularityValidator(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount
        ).validate(self, over: parameters, using: &execution)
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

    public func point(u: Double, v: Double, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        try validateParameters(u: u, v: v, using: &execution)
        // The immutable rails were admitted by the section evaluator. Validate
        // parameters here without replaying their complete correspondence proof.
        let center = try centerSpine.pointAssumingValid(at: u, tolerance: tolerance, using: &execution)
        let first = try firstContact.pointAssumingValid(at: u, tolerance: tolerance, using: &execution) - center
        let second = try secondContact.pointAssumingValid(at: u, tolerance: tolerance, using: &execution) - center
        try validateRadials(first, second, using: &execution)
        try execution.consumeWork(2)
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
    func rationalSection(atU u: Double, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try validateParameters(u: u, v: 0, using: &execution)
        let center = try centerSpine.pointAssumingValid(at: u, tolerance: tolerance, using: &execution)
        let first = try firstContact.pointAssumingValid(at: u, tolerance: tolerance, using: &execution) - center
        let second = try secondContact.pointAssumingValid(at: u, tolerance: tolerance, using: &execution) - center
        try validateRadials(first, second, using: &execution)
        try execution.consumeWork(2)
        let a = try first.normalized(tolerance: tolerance.distance)
        let b = try second.normalized(tolerance: tolerance.distance)
        let weight = sqrt((1 + a.dot(b)) * 0.5)
        try execution.retainStorage(count: 9, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Point3D>.stride)
        let result = BSplineCurve3D(
            degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [center + a * radius,
                            center + (a + b) * (radius / (2 * weight * weight)),
                            center + b * radius],
            weights: [1, weight, 1]
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    public func parameterDerivatives(u: Double, v: Double, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives {
        try execution.consumeWork(1)
        let jet = try taylorJet(u: u, v: v, throughOrder: 2, using: &execution)
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
        u: Double, v: Double,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterThirdOrderDerivatives {
        try execution.consumeWork(1)
        let jet = try taylorJet(u: u, v: v, throughOrder: 3, using: &execution)
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

    func taylorJet(u: Double, v: Double, throughOrder order: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        try validateParameters(u: u, v: v, using: &execution)
        guard (0...3).contains(order) else {
            throw failure(.invalidInput, "Blend Taylor derivatives support total orders zero through three.")
        }
        if order == 0 {
            let position = try point(u: u, v: v, using: &execution)
            return try .constant(position, order: 0, using: &execution)
        }
        let center = try curveJet(centerSpine, at: u, order: order, using: &execution)
        let firstJet = try curveJet(firstContact, at: u, order: order, using: &execution)
        let first = try firstJet.subtracting(center, using: &execution)
        let secondJet = try curveJet(secondContact, at: u, order: order, using: &execution)
        let second = try secondJet.subtracting(center, using: &execution)
        try validateRadials(first.value, second.value, using: &execution)
        let a = try first.normalized(tolerance: tolerance, using: &execution)
        let b = try second.normalized(tolerance: tolerance, using: &execution)
        let one = try SurfaceTaylorScalarJet.constant(1, order: order, using: &execution)
        let half = try SurfaceTaylorScalarJet.constant(0.5, order: order, using: &execution)
        let two = try SurfaceTaylorScalarJet.constant(2, order: order, using: &execution)
        let r = try SurfaceTaylorScalarJet.constant(radius, order: order, using: &execution)
        let t = try SurfaceTaylorScalarJet.parameterV(v, order: order, using: &execution)
        let s = try one.subtracting(t, using: &execution)
        let ab = try a.dot(b, using: &execution)
        let onePlusAB = try one.adding(ab, using: &execution)
        let halfOnePlusAB = try onePlusAB.multiplying(half, using: &execution)
        let weight = try halfOnePlusAB.squareRoot(tolerance: tolerance, using: &execution)
        let inverseWeight = try weight.reciprocal(tolerance: tolerance, using: &execution)
        let firstScale = try s.multiplying(s, using: &execution)
        let firstRadial = try a.multiplying(firstScale, using: &execution)
        let aPlusB = try a.adding(b, using: &execution)
        let st = try s.multiplying(t, using: &execution)
        let middleScale = try st.multiplying(inverseWeight, using: &execution)
        let middleRadial = try aPlusB.multiplying(middleScale, using: &execution)
        let firstAndMiddle = try firstRadial.adding(middleRadial, using: &execution)
        let lastScale = try t.multiplying(t, using: &execution)
        let lastRadial = try b.multiplying(lastScale, using: &execution)
        let radial = try firstAndMiddle.adding(lastRadial, using: &execution)
        let denominatorFirst = try s.multiplying(s, using: &execution)
        let twoWeight = try two.multiplying(weight, using: &execution)
        let twoWeightS = try twoWeight.multiplying(s, using: &execution)
        let denominatorMiddle = try twoWeightS.multiplying(t, using: &execution)
        let denominatorFirstAndMiddle = try denominatorFirst.adding(denominatorMiddle, using: &execution)
        let denominatorLast = try t.multiplying(t, using: &execution)
        let denominator = try denominatorFirstAndMiddle.adding(denominatorLast, using: &execution)
        let inverseDenominator = try denominator.reciprocal(tolerance: tolerance, using: &execution)
        let scale = try r.multiplying(inverseDenominator, using: &execution)
        let scaledRadial = try radial.multiplying(scale, using: &execution)
        let result = try center.adding(scaledRadial, using: &execution)
        for total in 0...order {
            for uOrder in 0...total {
                try execution.consumeWork(1)
                guard result.derivative(uOrder: uOrder, vOrder: total - uOrder).isFinite else {
                    throw failure(.singularSystem, "Blend differentiation exceeded the finite numeric range.")
                }
            }
        }
        return result
    }

    private func curveJet(_ curve: Curve3D, at u: Double, order: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
        let derivatives: (Vector3D, Vector3D, Vector3D, Vector3D)
        if order == 3 {
            let value = try curve.parameterDerivativesThroughThirdOrder(at: u, tolerance: tolerance, using: &execution)
            derivatives = (value.position - .origin, value.firstDerivative, value.secondDerivative, value.thirdDerivative)
        } else {
            let value = try curve.differentialGeometryAssumingValid(at: u, tolerance: tolerance, using: &execution)
            derivatives = (value.position - .origin, value.firstDerivative, value.secondDerivative, .zero)
        }
        var x = try SurfaceTaylorScalarJet(order: order, using: &execution)
        var y = try SurfaceTaylorScalarJet(order: order, using: &execution)
        var z = try SurfaceTaylorScalarJet(order: order, using: &execution)
        for index in 0...order {
            try execution.consumeWork(1)
            let derivative: Vector3D
            switch index {
            case 0: derivative = derivatives.0
            case 1: derivative = derivatives.1
            case 2: derivative = derivatives.2
            default: derivative = derivatives.3
            }
            let value = derivative / (index < 2 ? 1 : index == 2 ? 2 : 6)
            try x.setCoefficient(value.x, uOrder: index, vOrder: 0, using: &execution)
            try y.setCoefficient(value.y, uOrder: index, vOrder: 0, using: &execution)
            try z.setCoefficient(value.z, uOrder: index, vOrder: 0, using: &execution)
        }
        return try SurfaceTaylorVectorJet(x: x, y: y, z: z)
    }

    private func validateParameters(u: Double, v: Double, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard u.isFinite, v.isFinite, (0...1).contains(u), (0...1).contains(v) else {
            throw failure(.invalidInput, "Blend evaluation requires normalized U and V parameters.")
        }
    }

    package var originalRadialCrossThreshold: Double {
        max(sin(min(tolerance.angle, .pi * 0.5)), tolerance.relative)
    }

    private func validateRadials(_ first: Vector3D, _ second: Vector3D, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let firstLength = first.length
        let secondLength = second.length
        guard firstLength.isFinite, secondLength.isFinite,
              abs(firstLength - radius) <= tolerance.distance,
              abs(secondLength - radius) <= tolerance.distance else {
            throw failure(.intersectionFailure, "Blend contacts do not lie at the requested radius from the center spine.")
        }
        try execution.consumeWork(2)
        let a = try first.normalized(tolerance: tolerance.distance)
        let b = try second.normalized(tolerance: tolerance.distance)
        guard 1 + a.dot(b) > 0,
              a.cross(b).length > originalRadialCrossThreshold else {
            throw failure(.singularSystem, "Blend contacts do not define a regular minor arc.")
        }
    }

    func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(using: &execution)
    }

    func contactBoundaryDeviation(onFirst: Bool) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try contactBoundaryDeviation(onFirst: onFirst, using: &execution)
    }

    public func validateRegularity(
        over parameters: SurfaceParameterBox,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateRegularity(over: parameters, maximumSubdivisionDepth: maximumSubdivisionDepth, maximumCellCount: maximumCellCount, using: &execution)
    }

    public func point(u: Double, v: Double) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(u: u, v: v, using: &execution)
    }

    func rationalSection(atU u: Double) throws -> BSplineCurve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try rationalSection(atU: u, using: &execution)
    }

    public func parameterDerivatives(u: Double, v: Double) throws -> SurfaceParameterDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivatives(u: u, v: v, using: &execution)
    }

    public func parameterDerivativesThroughThirdOrder(
        u: Double, v: Double
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivativesThroughThirdOrder(u: u, v: v, using: &execution)
    }

    func taylorJet(u: Double, v: Double, throughOrder order: Int) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try taylorJet(u: u, v: v, throughOrder: order, using: &execution)
    }

}

#if !hasFeature(Embedded)
extension RollingBallBlendSurface3D: Codable {
    private enum CodingKeys: String, CodingKey {
        case centerSpine, firstContact, secondContact, radius, tolerance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys(
            [.centerSpine, .firstContact, .secondContact, .radius, .tolerance], in: decoder)
        centerSpine = try values.decode(Curve3D.self, forKey: .centerSpine)
        firstContact = try values.decode(Curve3D.self, forKey: .firstContact)
        secondContact = try values.decode(Curve3D.self, forKey: .secondContact)
        radius = try values.decode(Double.self, forKey: .radius)
        tolerance = try values.decode(ModelingTolerance.self, forKey: .tolerance)
        var execution = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try validate(using: &execution)
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(centerSpine, forKey: .centerSpine)
        try values.encode(firstContact, forKey: .firstContact)
        try values.encode(secondContact, forKey: .secondContact)
        try values.encode(radius, forKey: .radius)
        try values.encode(tolerance, forKey: .tolerance)
    }
}
#endif
