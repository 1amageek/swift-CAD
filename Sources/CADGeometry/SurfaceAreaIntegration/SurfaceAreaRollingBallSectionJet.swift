import CADCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// The original constant-radial minor circular section, with native V derivatives.
struct SurfaceAreaRollingBallSectionJet: Sendable {
    private let first: SurfaceIntervalVectorJet
    private let second: SurfaceIntervalVectorJet
    private let weight: SurfaceIntervalJet
    private let inverseWeight: SurfaceIntervalJet
    private let radius: Double

    /// Callers prove the stored control differences are constant on all rails.
    init(blend: RollingBallBlendSurface3D, center: Point3D, first: Point3D, second: Point3D,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }) throws {
        try consumeWork()
        let radius = blend.radius
        self.radius = radius
        let base = Self.exact(center)
        let rawA = Self.exact(first) - base
        let rawB = Self.exact(second) - base
        func admitRadial(_ raw: IntervalVector3DBounds) throws {
            try consumeWork()
            let deviation = max(abs(raw.lengthLowerBound-radius), abs(raw.lengthUpperBound-radius)).nextUp
            guard deviation <= blend.tolerance.distance else {
                throw blend.failure(.intersectionFailure, "Constant blend contact radials exceed the admitted radius deviation.")
            }
        }
        try admitRadial(rawA); try admitRadial(rawB)
        try consumeWork()
        guard let normalizedA = Self.constant(rawA).normalized(),
              let normalizedB = Self.constant(rawB).normalized() else {
            throw blend.failure(.singularSystem, "Constant blend radials have no certified nonzero length.")
        }
        // Exact common displacement makes these functions constant. Arithmetic
        // uncertainty belongs only to their values, never to U derivatives.
        let preparedFirst = Self.constant(Self.values(normalizedA))
        let preparedSecond = Self.constant(Self.values(normalizedB))
        self.first = preparedFirst
        self.second = preparedSecond
        let cross = Self.values(preparedFirst.cross(preparedSecond))
        let threshold = max(sin(min(blend.tolerance.angle, .pi*0.5)), blend.tolerance.relative)
        guard cross.lengthLowerBound > threshold,
              let w = ((Self.constant(.exact(1)) + preparedFirst.dot(preparedSecond)) * Self.constant(.exact(0.5))).squareRoot(),
              let inverse = w.reciprocal() else {
            throw blend.failure(.singularSystem, "Constant blend radials cannot certify a regular minor arc and circular weight.")
        }
        weight = Self.constant(w.value)
        inverseWeight = Self.constant(inverse.value)
    }

    func intervalJet(over v: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }) throws -> SurfaceIntervalVectorJet {
        try consumeWork()
        guard v.lower >= 0, v.upper <= 1 else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
                message:"Rolling-ball section requires its original normalized V chart.")
        }
        let one = Self.constant(.exact(1))
        let t = SurfaceIntervalJet.parameterV(v)
        let s = one-t
        try consumeWork()
        let radial = first*(s*s) + (first+second)*(s*t*inverseWeight) + second*(t*t)
        try consumeWork()
        let raw = s*s + Self.constant(.exact(2))*weight*s*t + t*t
        // The native denominator has Bernstein coefficients [1,w,1], so this
        // hull proves positivity even when independent interval s,t both include zero.
        guard let value = raw.value.intersection(with:.init(lower:min(1,weight.value.lower),upper:max(1,weight.value.upper))) else {
            throw KernelError(phase:.geometry,code:.intersectionFailure,tolerance:tolerance,
                message:"Translated rolling-ball denominator certificates are inconsistent.")
        }
        let denominator = SurfaceIntervalJet(value:value,derivativeU:.exact(0),derivativeV:raw.derivativeV,
            secondDerivativeUU:.exact(0),secondDerivativeUV:.exact(0),secondDerivativeVV:raw.secondDerivativeVV,
            thirdDerivativeUUU:.exact(0),thirdDerivativeUUV:.exact(0),thirdDerivativeUVV:.exact(0),thirdDerivativeVVV:raw.thirdDerivativeVVV)
        try consumeWork()
        guard let inverse = denominator.reciprocal() else {
            throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
                message:"Translated rolling-ball area denominator cannot certify positivity.")
        }
        return radial*(Self.constant(.exact(radius))*inverse)
    }

    private static func exact(_ point: Point3D) -> IntervalVector3DBounds {
        .init(x:.exact(point.x),y:.exact(point.y),z:.exact(point.z))
    }

    private static func values(_ jet: SurfaceIntervalVectorJet) -> IntervalVector3DBounds {
        .init(x:jet.x.value,y:jet.y.value,z:jet.z.value)
    }

    private static func constant(_ value: IntervalVector3DBounds) -> SurfaceIntervalVectorJet {
        .init(x:constant(value.x),y:constant(value.y),z:constant(value.z))
    }

    private static func constant(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        .init(value:value,derivativeU:.exact(0),derivativeV:.exact(0),
            secondDerivativeUU:.exact(0),secondDerivativeUV:.exact(0),secondDerivativeVV:.exact(0),
            thirdDerivativeUUU:.exact(0),thirdDerivativeUUV:.exact(0),thirdDerivativeUVV:.exact(0),thirdDerivativeVVV:.exact(0))
    }
}
