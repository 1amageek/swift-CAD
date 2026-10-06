import CADCore

/// Integral-local preparation under the exact common linear-rail displacement proof.
struct SurfaceAreaTranslatedRollingBallJet: Sendable {
    private let origin: IntervalVector3DBounds
    private let displacement: IntervalVector3DBounds
    private let section: SurfaceAreaRollingBallSectionJet

    init?(_ blend: RollingBallBlendSurface3D, maximumSubdivisionDepth: Int? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int? = nil,
        consumeWork: () throws -> Void = { try Task.checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil) throws {
        guard try SurfaceAreaTranslationCertificate.direction(of: .procedural(.rollingBall(blend)),
                remainingSourceDepth:remainingSourceDepth,maximumAlgebraicDepth:maximumAlgebraicDepth,
                consumeWork:consumeWork,consumeStorage:consumeStorage) == .u,
              case .bSpline(let center) = blend.centerSpine,
              case .bSpline(let a) = blend.firstContact,
              case .bSpline(let b) = blend.secondContact else { return nil }
        if let maximumSubdivisionDepth {
            try Surface3D.procedural(.rollingBall(blend)).validateOriginalSource(tolerance:blend.tolerance,
                remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
                consumeWork:{ _ in try consumeWork() },consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        } else { try blend.validate() }
        origin = Self.exact(center.controlPoints[0])
        displacement = Self.exact(center.controlPoints[1]) - origin
        section = try SurfaceAreaRollingBallSectionJet(blend:blend,center:center.controlPoints[0],
            first:a.controlPoints[0],second:b.controlPoints[0],consumeWork:consumeWork)
    }

    func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try Task.checkCancellation() }) throws -> SurfaceIntervalVectorJet {
        guard !Task.isCancelled else {
            throw KernelError(phase:.geometry,code:.cancelled,tolerance:tolerance,
                message:"Translated rolling-ball area enclosure was cancelled.")
        }
        guard box.u.lower >= 0, box.u.upper <= 1 else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
                message:"Translated rolling-ball area enclosures require the original normalized chart.")
        }
        let section = try section.intervalJet(over:box.v,tolerance:tolerance,consumeWork:consumeWork)
        let u = OutwardScalarInterval(lower:box.u.lower,upper:box.u.upper)
        func coordinate(_ origin: OutwardScalarInterval, _ delta: OutwardScalarInterval,
                        _ section: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
            let position = origin+delta*u+section.value
            try consumeWork()
            guard position.isFinite, delta.isFinite, section.derivativeV.isFinite,
                section.secondDerivativeVV.isFinite, section.thirdDerivativeVVV.isFinite else {
                throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                    message:"Translated rolling-ball area derivatives exceeded finite arithmetic.")
            }
            return SurfaceIntervalJet(value:position,derivativeU:delta,derivativeV:section.derivativeV,
                secondDerivativeUU:.exact(0),secondDerivativeUV:.exact(0),secondDerivativeVV:section.secondDerivativeVV,
                thirdDerivativeUUU:.exact(0),thirdDerivativeUUV:.exact(0),thirdDerivativeUVV:.exact(0),thirdDerivativeVVV:section.thirdDerivativeVVV)
        }
        return try SurfaceIntervalVectorJet(x:coordinate(origin.x,displacement.x,section.x),
            y:coordinate(origin.y,displacement.y,section.y),z:coordinate(origin.z,displacement.z,section.z))
    }

    private static func exact(_ point: Point3D) -> IntervalVector3DBounds {
        .init(x:.exact(point.x),y:.exact(point.y),z:.exact(point.z))
    }
}
