import CADCore
import Foundation

/// Persistent original surface with foreign UV units and a preserved spatial frame.
public struct OriginalImageSurface3D: Hashable, Sendable {
    public let source: Surface3D
    public let uParameterGain: OriginalParameterGain
    public let vParameterGain: OriginalParameterGain
    public var uGain: Double { uParameterGain.value }
    public var vGain: Double { vParameterGain.value }
    public let uOffset: Double
    public let vOffset: Double
    public let transform: AffineTransform3D
    public let swapAxes: Bool

    private init(validatedSource: Surface3D, uParameterGain: OriginalParameterGain,
        vParameterGain: OriginalParameterGain, uOffset: Double, vOffset: Double,
        transform: AffineTransform3D, swapAxes: Bool) {
        source = validatedSource; self.uParameterGain = uParameterGain; self.vParameterGain = vParameterGain
        self.uOffset = uOffset; self.vOffset = vOffset; self.transform = transform; self.swapAxes = swapAxes
    }

    /// Requires the caller's already admitted replacement source and chart.
    package func replacingSourceKeepingChart(with validatedSource: Surface3D) -> Self {
        .init(validatedSource: validatedSource, uParameterGain: uParameterGain,
            vParameterGain: vParameterGain, uOffset: uOffset, vOffset: vOffset,
            transform: transform, swapAxes: swapAxes)
    }

    public init(source: Surface3D, uGain: Double = 1, vGain: Double = 1,
        uOffset: Double = 0, vOffset: Double = 0,
        transform: AffineTransform3D, swapAxes: Bool = false, tolerance: ModelingTolerance) throws {
        try self.init(source: source, uParameterGain: .binary(uGain), vParameterGain: .binary(vGain),
            uOffset: uOffset, vOffset: vOffset, transform: transform, swapAxes: swapAxes, tolerance: tolerance)
    }

    public init(source: Surface3D, uParameterGain: OriginalParameterGain,
        vParameterGain: OriginalParameterGain, uOffset: Double = 0, vOffset: Double = 0,
        transform: AffineTransform3D, swapAxes: Bool = false, tolerance: ModelingTolerance) throws {
        self.source = source; self.uParameterGain = uParameterGain; self.vParameterGain = vParameterGain
        self.uOffset = uOffset; self.vOffset = vOffset; self.transform = transform; self.swapAxes = swapAxes
        try validate(tolerance: tolerance)
    }

    /// Caller-admitted original image construction without legacy recursive validation.
    public init(source: Surface3D, uGain: Double = 1, vGain: Double = 1,
        uOffset: Double = 0, vOffset: Double = 0, transform: AffineTransform3D,
        swapAxes: Bool = false, tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws {
        try self.init(source: source, uParameterGain: .binary(uGain), vParameterGain: .binary(vGain),
            uOffset: uOffset, vOffset: vOffset, transform: transform, swapAxes: swapAxes,
            tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork)
    }

    public init(source: Surface3D, uParameterGain: OriginalParameterGain,
        vParameterGain: OriginalParameterGain, uOffset: Double = 0, vOffset: Double = 0,
        transform: AffineTransform3D, swapAxes: Bool = false, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
        consumeWork: () throws -> Void) throws {
        self.source = source; self.uParameterGain = uParameterGain; self.vParameterGain = vParameterGain
        self.uOffset = uOffset; self.vOffset = vOffset; self.transform = transform; self.swapAxes = swapAxes
        try Surface3D.parameterImage(self).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { _ in try consumeWork() })
    }

    public var uDomain: ParameterDomain {
        OriginalParameterImageMap.domain(swapAxes ? source.vDomain : source.uDomain, gain: uParameterGain, offset: uOffset)
    }
    public var vDomain: ParameterDomain {
        OriginalParameterImageMap.domain(swapAxes ? source.uDomain : source.vDomain, gain: vParameterGain, offset: vOffset)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try OriginalParameterImageMap.validate(gain: uParameterGain, offset: uOffset)
        try OriginalParameterImageMap.validate(gain: vParameterGain, offset: vOffset)
        try transform.validate(); try source.validate(tolerance: tolerance)
        try uDomain.validate(tolerance: tolerance); try vDomain.validate(tolerance: tolerance)
    }

    public func nativeParameter(u: Double, v: Double) throws -> SurfaceParameter {
        let mappedU = try OriginalParameterImageMap.parameter(u, gain: uParameterGain, offset: uOffset)
        let mappedV = try OriginalParameterImageMap.parameter(v, gain: vParameterGain, offset: vOffset)
        return SurfaceParameter(u: swapAxes ? mappedV : mappedU, v: swapAxes ? mappedU : mappedV)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let native = try nativeParameter(u: u, v: v)
        return transform.applying(to: try source.pointAssumingValid(u: native.u,
            v: native.v, tolerance: tolerance))
    }

    public func parameterDerivatives(u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterDerivatives {
        let native = try nativeParameter(u: u, v: v)
        let jet = try source.parameterDerivativesAssumingValid(u: native.u, v: native.v,
            tolerance: tolerance)
        return .init(position: transform.applying(to: jet.position),
            tangentU: transform.applying(to: swapAxes ? jet.tangentV : jet.tangentU) * uGain,
            tangentV: transform.applying(to: swapAxes ? jet.tangentU : jet.tangentV) * vGain,
            secondDerivativeUU: transform.applying(to: swapAxes ? jet.secondDerivativeVV : jet.secondDerivativeUU) * (uGain * uGain),
            secondDerivativeUV: transform.applying(to: jet.secondDerivativeUV) * (uGain * vGain),
            secondDerivativeVV: transform.applying(to: swapAxes ? jet.secondDerivativeUU : jet.secondDerivativeVV) * (vGain * vGain))
    }

    public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
        let native = try nativeParameter(u: u, v: v)
        let jet = try source.parameterDerivativesThroughThirdOrder(u: native.u,
            v: native.v, tolerance: tolerance)
        func vector(_ value: Vector3D, _ a: Int, _ b: Int) -> Vector3D {
            transform.applying(to: value) * (pow(uGain, Double(a)) * pow(vGain, Double(b)))
        }
        return .init(position: transform.applying(to: jet.position),
            tangentU: vector(swapAxes ? jet.tangentV : jet.tangentU, 1, 0),
            tangentV: vector(swapAxes ? jet.tangentU : jet.tangentV, 0, 1),
            secondDerivativeUU: vector(swapAxes ? jet.secondDerivativeVV : jet.secondDerivativeUU, 2, 0),
            secondDerivativeUV: vector(jet.secondDerivativeUV, 1, 1),
            secondDerivativeVV: vector(swapAxes ? jet.secondDerivativeUU : jet.secondDerivativeVV, 0, 2),
            thirdDerivativeUUU: vector(swapAxes ? jet.thirdDerivativeVVV : jet.thirdDerivativeUUU, 3, 0),
            thirdDerivativeUUV: vector(swapAxes ? jet.thirdDerivativeUVV : jet.thirdDerivativeUUV, 2, 1),
            thirdDerivativeUVV: vector(swapAxes ? jet.thirdDerivativeUUV : jet.thirdDerivativeUVV, 1, 2),
            thirdDerivativeVVV: vector(swapAxes ? jet.thirdDerivativeUUU : jet.thirdDerivativeVVV, 0, 3))
    }

    /// Original native image bounds; exact boundary singleton identities retain zero width.
    public func sourceParameterBounds(over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = {}) throws -> SurfaceParameterBox {
        try validate(tolerance: tolerance)
        return try nativeBox(box, consumeWork:consumeWork)
    }

    func nativeBox(_ box: SurfaceParameterBox, consumeWork: () throws -> Void = {}) throws -> SurfaceParameterBox {
        let u = try OriginalParameterImageMap.interval(box.u, gain: uParameterGain,
            offset: uOffset, sourceDomain: swapAxes ? source.vDomain : source.uDomain, consumeWork:consumeWork)
        let v = try OriginalParameterImageMap.interval(box.v, gain: vParameterGain,
            offset: vOffset, sourceDomain: swapAxes ? source.uDomain : source.vDomain, consumeWork:consumeWork)
        return SurfaceParameterBox(u: swapAxes ? v : u, v: swapAxes ? u : v)
    }

    package func nativeBox<B: RationalAlgebraAdmitting>(_ box: SurfaceParameterBox,
        usage: inout B) throws -> SurfaceParameterBox {
        let u = try OriginalParameterImageMap.interval(box.u, gain: uParameterGain,
            offset: uOffset, sourceDomain: swapAxes ? source.vDomain : source.uDomain, usage: &usage)
        let v = try OriginalParameterImageMap.interval(box.v, gain: vParameterGain,
            offset: vOffset, sourceDomain: swapAxes ? source.uDomain : source.vDomain, usage: &usage)
        return SurfaceParameterBox(u: swapAxes ? v : u, v: swapAxes ? u : v)
    }

    package func nativeBox(_ box: SurfaceParameterBox, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil)
        throws -> SurfaceParameterBox {
        try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() },
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            return try nativeBox(box, usage: &usage)
        }
    }

    func mappedJet(_ jet: SurfaceIntervalVectorJet) throws -> SurfaceIntervalVectorJet {
        let u = try uParameterGain.interval(), v = try vParameterGain.interval()
        func coordinate(_ source: SurfaceIntervalJet) -> SurfaceIntervalJet {
            .init(value: source.value, derivativeU: (swapAxes ? source.derivativeV : source.derivativeU) * u,
                derivativeV: (swapAxes ? source.derivativeU : source.derivativeV) * v,
                secondDerivativeUU: (swapAxes ? source.secondDerivativeVV : source.secondDerivativeUU) * u * u,
                secondDerivativeUV: source.secondDerivativeUV * u * v,
                secondDerivativeVV: (swapAxes ? source.secondDerivativeUU : source.secondDerivativeVV) * v * v,
                thirdDerivativeUUU: (swapAxes ? source.thirdDerivativeVVV : source.thirdDerivativeUUU) * u * u * u,
                thirdDerivativeUUV: (swapAxes ? source.thirdDerivativeUVV : source.thirdDerivativeUUV) * u * u * v,
                thirdDerivativeUVV: (swapAxes ? source.thirdDerivativeUUV : source.thirdDerivativeUVV) * u * v * v,
                thirdDerivativeVVV: (swapAxes ? source.thirdDerivativeUUU : source.thirdDerivativeVVV) * v * v * v)
        }
        let mapped = SurfaceIntervalVectorJet(x: coordinate(jet.x), y: coordinate(jet.y),
            z: coordinate(jet.z))
        return .constant(transform.translation)
            + .constant(transform.basisX) * mapped.x
            + .constant(transform.basisY) * mapped.y
            + .constant(transform.basisZ) * mapped.z
    }

    func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        let prepared = try PreparedSurfaceDifferentialEncloser(surface: source, tolerance: tolerance)
        return try mappedJet(try prepared.intervalJet(overClosedBox: nativeBox(box), tolerance: tolerance))
    }

    func taylorJet(u: Double, v: Double, throughOrder order: Int,
        tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        let native = try nativeParameter(u: u, v: v)
        let original = try source.taylorJet(u: native.u, v: native.v, throughOrder: order,
            tolerance: tolerance)
        var x = try SurfaceTaylorScalarJet(order: order)
        var y = try SurfaceTaylorScalarJet(order: order)
        var z = try SurfaceTaylorScalarJet(order: order)
        for total in 0...order {
            for a in 0...total {
                try Task.checkCancellation()
                let b = total - a
                let coefficient = transform.applying(to: Vector3D(x: original.x[swapAxes ? b : a, swapAxes ? a : b],
                    y: original.y[swapAxes ? b : a, swapAxes ? a : b],
                    z: original.z[swapAxes ? b : a, swapAxes ? a : b]))
                    * (pow(uGain, Double(a)) * pow(vGain, Double(b)))
                let value = total == 0 ? coefficient + transform.translation : coefficient
                guard value.isFinite else {
                    throw GeometryConversionError.invalidInput("Original surface image Taylor coefficients are nonfinite.")
                }
                try x.setCoefficient(value.x, uOrder: a, vOrder: b)
                try y.setCoefficient(value.y, uOrder: a, vOrder: b)
                try z.setCoefficient(value.z, uOrder: a, vOrder: b)
            }
        }
        return try .init(x: x, y: y, z: z)
    }
}

public extension Surface3D {
    static func parameterImage(_ image: OriginalImageSurface3D) -> Surface3D {
        .procedural(.originalImage(image))
    }
    static func affineImage(_ image: OriginalImageSurface3D) -> Surface3D {
        .procedural(.originalImage(image))
    }
}

#if !hasFeature(Embedded)
extension OriginalImageSurface3D: Codable {
    private enum CodingKeys: String, CodingKey { case source, uParameterGain, vParameterGain, uOffset, vOffset, transform, swapAxes }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .uParameterGain, .vParameterGain, .uOffset, .vOffset, .transform, .swapAxes], in: decoder)
        source = try container.decode(Surface3D.self, forKey: .source)
        uParameterGain = try container.decode(OriginalParameterGain.self, forKey: .uParameterGain)
        vParameterGain = try container.decode(OriginalParameterGain.self, forKey: .vParameterGain)
        uOffset = try container.decode(Double.self, forKey: .uOffset)
        vOffset = try container.decode(Double.self, forKey: .vOffset)
        transform = try container.decode(AffineTransform3D.self, forKey: .transform)
        swapAxes = try container.decode(Bool.self, forKey: .swapAxes)
        try OriginalParameterImageMap.validate(gain: uParameterGain, offset: uOffset)
        try OriginalParameterImageMap.validate(gain: vParameterGain, offset: vOffset)
        try transform.validate()
    }
}
#endif
