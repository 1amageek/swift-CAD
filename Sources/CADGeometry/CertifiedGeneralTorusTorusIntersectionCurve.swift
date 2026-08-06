import CADCore
import Foundation
import Synchronization

public struct CertifiedGeneralTorusTorusIntersectionCurve: Codable, Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Certificate: Hashable, Sendable {
        let trace: GeneralTorusTorusSurfaceIntersector.RootTrace
        let cycles: [[Int]]
        let meridianRootCompleteness:
            GeneralTorusTorusSurfaceIntersector
                .MeridianRootCompletenessCertificate
        let branchSpatialDifferential:
            GeneralTorusTorusSurfaceIntersector
                .BranchSpatialDifferentialCertificate
    }

    private struct CertificateCacheKey: Hashable, Sendable {
        let parameterizedSurface: Surface3D
        let referenceSurface: Surface3D
        let options: SurfaceSurfaceIntersectionOptions
        let tolerance: ModelingTolerance
    }

    // Certificate derivation traces the full meridian-quartic root system,
    // and decoding rebuilds the same certificate for identical surfaces on
    // every round trip, so derived certificates are memoized per process.
    // Platforms without Synchronization.Mutex hold no cache state at all
    // and derive every certificate, matching the uncached behavior.
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    private enum CertificateCache {
        static let storage = Mutex<[CertificateCacheKey: Certificate?]>([:])
    }

    private static func cachedCertificate(
        parameterizedSurface: Surface3D,
        referenceSurface: Surface3D,
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Certificate? {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) else {
            return try makeCertificate(
                configuration: configuration,
                options: options,
                tolerance: tolerance
            )
        }
        let key = CertificateCacheKey(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            options: options,
            tolerance: tolerance
        )
        if let cached = CertificateCache.storage.withLock({ $0[key] }) {
            return cached
        }
        // Derivation runs outside the lock; concurrent duplicate derivation
        // is acceptable for a memoization cache.
        let certificate = try makeCertificate(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        CertificateCache.storage.withLock { cache in
            if cache.count >= 64 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = certificate
        }
        return certificate
    }

    public let parameterizedSurface: Surface3D
    public let referenceSurface: Surface3D
    public let componentIndex: Int
    public let componentCount: Int
    public let maximumSubdivisionDepth: Int
    public let maximumIterations: Int
    public let maximumSeedCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    private let certificate: Certificate

    public var majorAngleWindingCount: Int {
        certificate.cycles[componentIndex].count
    }

    public init(
        parameterizedSurface: Surface3D,
        referenceSurface: Surface3D,
        componentIndex: Int,
        maximumSubdivisionDepth: Int = 12,
        maximumIterations: Int = 32,
        maximumSeedCount: Int = 1_024,
        tolerance: ModelingTolerance
    ) throws {
        let options = Self.options(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumIterations: maximumIterations,
            maximumSeedCount: maximumSeedCount
        )
        try options.validate(tolerance: tolerance)
        let configuration = try Self.makeConfiguration(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            tolerance: tolerance
        )
        guard let certificate = try Self.cachedCertificate(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            configuration: configuration,
            options: options,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A general torus-torus curve cannot select a component from an empty intersection."
            )
        }
        try self.init(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            componentIndex: componentIndex,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumIterations: maximumIterations,
            maximumSeedCount: maximumSeedCount,
            tolerance: tolerance,
            configuration: configuration,
            certificate: certificate
        )
    }

    private init(
        parameterizedSurface: Surface3D,
        referenceSurface: Surface3D,
        componentIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumIterations: Int,
        maximumSeedCount: Int,
        tolerance: ModelingTolerance,
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        certificate: Certificate
    ) throws {
        self.parameterizedSurface = parameterizedSurface
        self.referenceSurface = referenceSurface
        self.componentIndex = componentIndex
        componentCount = certificate.cycles.count
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumIterations = maximumIterations
        self.maximumSeedCount = maximumSeedCount
        certificationTolerance = tolerance
        maximumResidualUpperBound = try Self.residualUpperBound(
            configuration: configuration,
            tolerance: tolerance
        )
        self.certificate = certificate
        try validate(tolerance: tolerance)
    }

    static func certifiedCurves(
        firstTorusSurface: Surface3D,
        secondTorusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedGeneralTorusTorusIntersectionCurve] {
        try options.validate(tolerance: tolerance)
        let ordered = try orderedSurfaces(
            first: firstTorusSurface,
            second: secondTorusSurface,
            tolerance: tolerance
        )
        let candidates = [
            (parameterized: ordered.first, reference: ordered.second),
            (parameterized: ordered.second, reference: ordered.first),
        ]
        var recoverableErrors: [KernelError] = []
        for candidate in candidates {
            do {
                let configuration = try makeConfiguration(
                    parameterizedSurface: candidate.parameterized,
                    referenceSurface: candidate.reference,
                    tolerance: tolerance
                )
                guard let certificate = try cachedCertificate(
                    parameterizedSurface: candidate.parameterized,
                    referenceSurface: candidate.reference,
                    configuration: configuration,
                    options: options,
                    tolerance: tolerance
                ) else {
                    return []
                }
                return try certificate.cycles.indices.map { componentIndex in
                    try CertifiedGeneralTorusTorusIntersectionCurve(
                        parameterizedSurface: candidate.parameterized,
                        referenceSurface: candidate.reference,
                        componentIndex: componentIndex,
                        maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        maximumIterations: options.maximumIterations,
                        maximumSeedCount: options.maximumSeedCount,
                        tolerance: tolerance,
                        configuration: configuration,
                        certificate: certificate
                    )
                }
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .singularSystem {
                recoverableErrors.append(error)
            }
        }
        if let error = recoverableErrors.min(by: {
            ($0.residual ?? .infinity) < ($1.residual ?? .infinity)
        }) {
            throw error
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "General torus-torus intersection exhausted both certified meridian-quartic parameterizations."
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general torus-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let options = Self.options(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumIterations: maximumIterations,
            maximumSeedCount: maximumSeedCount
        )
        try options.validate(tolerance: tolerance)
        let configuration = try Self.makeConfiguration(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            tolerance: tolerance
        )
        guard componentCount > 0,
              componentCount == certificate.cycles.count,
              componentIndex >= 0,
              componentIndex < componentCount,
              certificate.trace.parameters.count >= 2,
              certificate.trace.valuesByBranch.isEmpty == false,
              certificate.trace.permutation.count
                == certificate.trace.valuesByBranch.count,
              certificate.cycles.allSatisfy({ $0.isEmpty == false }),
              certificate.meridianRootCompleteness.processedCellCount > 0,
              certificate.branchSpatialDifferential.processedCellCount > 0,
              certificate.branchSpatialDifferential.partitions.isEmpty == false,
              certificate.branchSpatialDifferential.partitions.allSatisfy({
                  certificate.trace.valuesByBranch.indices.contains(
                      $0.branchIndex
                  )
                      && $0.majorAngleLower.isFinite
                      && $0.majorAngleUpper.isFinite
                      && $0.majorAngleUpper > $0.majorAngleLower
                      && $0.minorFirstDerivativeMagnitudeUpperBound.isFinite
                      && $0.minorSecondDerivativeMagnitudeUpperBound.isFinite
              }),
              maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound > 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A general torus-torus component has an invalid stored completeness certificate."
            )
        }
        let reproducedBound = try Self.residualUpperBound(
            configuration: configuration,
            tolerance: certificationTolerance
        )
        guard maximumResidualUpperBound == reproducedBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A general torus-torus residual certificate no longer matches its source surfaces."
            )
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        ).position
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            tolerance: tolerance
        )
        let cycle = certificate.cycles[componentIndex]
        let period = 2.0 * Double.pi
        let upper = period * Double(cycle.count)
        let branch: Int
        let majorAngle: Double
        if clamped == 1.0 {
            branch = cycle[0]
            majorAngle = 0.0
        } else {
            let parameter = upper * clamped
            let cycleIndex = min(
                Int(floor(max(parameter, 0.0) / period)),
                cycle.count - 1
            )
            branch = cycle[cycleIndex]
            majorAngle = parameter - Double(cycleIndex) * period
        }
        let intersector = GeneralTorusTorusSurfaceIntersector()
        let roots = try intersector.verifiedRoots(
            majorAngle: majorAngle,
            configuration: configuration,
            options: Self.options(
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumIterations: maximumIterations,
                maximumSeedCount: maximumSeedCount
            ),
            tolerance: tolerance
        )
        guard roots.count == certificate.trace.valuesByBranch.count else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(abs(
                    roots.count - certificate.trace.valuesByBranch.count
                )),
                tolerance: tolerance,
                message: "A certified torus-torus component changed meridian root count during evaluation."
            )
        }
        let reference = certificate.trace.referenceValue(
            branch: branch,
            at: majorAngle
        )
        let minorAngle = try intersector.selectedRoot(
            candidates: roots,
            reference: reference,
            period: period,
            tolerance: tolerance
        )
        let geometry = try Self.differentialGeometry(
            majorAngle: majorAngle,
            minorAngle: minorAngle,
            parameterScale: upper,
            configuration: configuration,
            tolerance: tolerance
        )
        let parameterizedProjection = try parameterizedSurface.parameterProjection(
            of: geometry.position,
            tolerance: tolerance
        )
        let referenceProjection = try referenceSurface.parameterProjection(
            of: geometry.position,
            tolerance: tolerance
        )
        let residual = max(
            parameterizedProjection.residual,
            referenceProjection.residual
        )
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified general torus-torus root exceeded its geometric residual bound."
            )
        }
        return geometry
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        guard surface == parameterizedSurface || surface == referenceSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general torus-torus pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            tolerance: tolerance
        )
        let radius = configuration.parameterized.majorRadius
            + configuration.parameterized.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.parameterized.center.x - radius,
                y: configuration.parameterized.center.y - radius,
                z: configuration.parameterized.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.parameterized.center.x + radius,
                y: configuration.parameterized.center.y + radius,
                z: configuration.parameterized.center.z + radius
            )
        )
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double = 0.0,
        toNormalizedFraction upperFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        let configuration = try Self.makeConfiguration(
            parameterizedSurface: parameterizedSurface,
            referenceSurface: referenceSurface,
            tolerance: tolerance
        )
        let period = 2.0 * Double.pi
        let totalMajorAngle = period * Double(majorAngleWindingCount)
        let lowerMajorAngle = max(lowerFraction, 0.0) * totalMajorAngle
        let upperMajorAngle = min(upperFraction, 1.0) * totalMajorAngle
        let lowerCycle = min(
            Int(floor(lowerMajorAngle / period)),
            majorAngleWindingCount - 1
        )
        let upperCycle = min(
            Int(floor(upperMajorAngle / period)),
            majorAngleWindingCount - 1
        )
        let cycle = certificate.cycles[componentIndex]
        var majorAngleRanges: [
            (branchIndex: Int, lower: Double, upper: Double)
        ] = []
        for cycleIndex in lowerCycle...upperCycle {
            let cycleOffset = Double(cycleIndex) * period
            let lower = max(lowerMajorAngle - cycleOffset, 0.0)
            let upper = min(upperMajorAngle - cycleOffset, period)
            if upper > lower {
                majorAngleRanges.append((
                    branchIndex: cycle[cycleIndex],
                    lower: lower,
                    upper: upper
                ))
            }
        }
        let overlappingPartitions = certificate.branchSpatialDifferential
            .partitions.filter { partition in
                majorAngleRanges.contains { range in
                    partition.branchIndex == range.branchIndex
                        && partition.majorAngleUpper >= range.lower
                        && partition.majorAngleLower <= range.upper
                }
            }
        guard overlappingPartitions.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "General torus-torus differential certification found no partition overlapping the requested source range."
            )
        }
        let minorFirst = overlappingPartitions.map(
            \.minorFirstDerivativeMagnitudeUpperBound
        ).max() ?? .infinity
        let minorSecond = overlappingPartitions.map(
            \.minorSecondDerivativeMagnitudeUpperBound
        ).max() ?? .infinity
        let majorRadiusBound = (
            configuration.parameterized.majorRadius
                + configuration.parameterized.minorRadius
        ).nextUp
        let minorRadius = configuration.parameterized.minorRadius.nextUp
        let firstPerMajorAngle = (
            majorRadiusBound + minorRadius * minorFirst
        ).nextUp
        let secondPerMajorAngle = (
            majorRadiusBound
                + 2.0 * minorRadius * minorFirst
                + minorRadius * minorFirst * minorFirst
                + minorRadius * minorSecond
        ).nextUp
        let parameterScale = totalMajorAngle.nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (firstPerMajorAngle * parameterScale).nextUp,
            second: (
                secondPerMajorAngle * parameterScale * parameterScale
            ).nextUp
        )
    }

    private static func makeConfiguration(
        parameterizedSurface: Surface3D,
        referenceSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> GeneralTorusTorusSurfaceIntersector.Configuration {
        try parameterizedSurface.validate(tolerance: tolerance)
        try referenceSurface.validate(tolerance: tolerance)
        guard case let .torus(parameterizedSource) = CanonicalAnalyticSurface(
            parameterizedSurface
        ), case let .torus(referenceSource) = CanonicalAnalyticSurface(
            referenceSurface
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified general torus-torus curve requires two exact tori."
            )
        }
        guard AnalyticAxisRelation.areParallel(
            parameterizedSource.axis,
            referenceSource.axis,
            tolerance: tolerance
        ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: parameterizedSource.axis.cross(referenceSource.axis).length,
                tolerance: tolerance,
                message: "A certified general torus-torus curve requires nonparallel axes."
            )
        }
        let intersector = GeneralTorusTorusSurfaceIntersector()
        return try intersector.makeConfiguration(
            parameterized: intersector.canonicalTorus(
                parameterizedSource,
                tolerance: tolerance
            ),
            reference: intersector.canonicalTorus(
                referenceSource,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
    }

    private static func makeCertificate(
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Certificate? {
        let intersector = GeneralTorusTorusSurfaceIntersector()
        let meridianRootCompleteness =
            try intersector.certifyConstantSimpleMeridianRoots(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        let initialRoots = try intersector.verifiedRoots(
            majorAngle: 0.0,
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        guard initialRoots.isEmpty == false else { return nil }
        let trace = try intersector.makeRootTrace(
            initialRoots: initialRoots,
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        let cycles = try intersector.permutationCycles(
            trace.permutation,
            tolerance: tolerance
        )
        guard cycles.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified torus-torus root permutation produced no closed components."
            )
        }
        let branchSpatialDifferential =
            try intersector.certifyBranchSpatialDifferentials(
                trace: trace,
                configuration: configuration,
                options: options,
                tolerance: tolerance
            )
        return Certificate(
            trace: trace,
            cycles: cycles,
            meridianRootCompleteness: meridianRootCompleteness,
            branchSpatialDifferential: branchSpatialDifferential
        )
    }

    private static func differentialGeometry(
        majorAngle: Double,
        minorAngle: Double,
        parameterScale: Double,
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let radial = configuration.radial(at: majorAngle)
        let radialFirst = configuration.zeroRadial * -sin(majorAngle)
            + configuration.quarterRadial * cos(majorAngle)
        let radialSecond = -radial
        let minorCosine = cos(minorAngle)
        let minorSine = sin(minorAngle)
        let radialScale = configuration.parameterized.majorRadius
            + configuration.parameterized.minorRadius * minorCosine
        let minorRadius = configuration.parameterized.minorRadius
        let position = configuration.parameterized.center
            + radial * radialScale
            + configuration.parameterized.axis * (minorRadius * minorSine)
        let majorTangent = radialFirst * radialScale
        let minorTangent = radial * (-minorRadius * minorSine)
            + configuration.parameterized.axis * (minorRadius * minorCosine)
        let majorSecond = radialSecond * radialScale
        let majorMinor = radialFirst * (-minorRadius * minorSine)
        let minorSecond = radial * (-minorRadius * minorCosine)
            + configuration.parameterized.axis * (-minorRadius * minorSine)
        let offset = position - configuration.reference.center
        let gradient = torusGradient(
            offset: offset,
            torus: configuration.reference
        )
        let minorDenominator = gradient.dot(minorTangent)
        let threshold = derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        )
        guard minorDenominator.isFinite,
              abs(minorDenominator) > threshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(minorDenominator),
                tolerance: tolerance,
                message: "A certified torus-torus branch reached a meridian-tangent root."
            )
        }
        let minorFirst = -gradient.dot(majorTangent) / minorDenominator
        let majorMajorImplicit = torusHessianBilinear(
            offset: offset,
            first: majorTangent,
            second: majorTangent,
            torus: configuration.reference
        ) + gradient.dot(majorSecond)
        let majorMinorImplicit = torusHessianBilinear(
            offset: offset,
            first: majorTangent,
            second: minorTangent,
            torus: configuration.reference
        ) + gradient.dot(majorMinor)
        let minorMinorImplicit = torusHessianBilinear(
            offset: offset,
            first: minorTangent,
            second: minorTangent,
            torus: configuration.reference
        ) + gradient.dot(minorSecond)
        let minorSecondDerivative = -(
            majorMajorImplicit
                + 2.0 * majorMinorImplicit * minorFirst
                + minorMinorImplicit * minorFirst * minorFirst
        ) / minorDenominator
        let firstDerivative = (
            majorTangent + minorTangent * minorFirst
        ) * parameterScale
        let secondDerivative = (
            majorSecond
                + majorMinor * (2.0 * minorFirst)
                + minorSecond * (minorFirst * minorFirst)
                + minorTangent * minorSecondDerivative
        ) * (parameterScale * parameterScale)
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified general torus-torus component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    private static func torusGradient(
        offset: Vector3D,
        torus: GeneralTorusTorusSurfaceIntersector.Torus
    ) -> Vector3D {
        let q = offset.dot(offset)
            + torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        let radial = offset - torus.axis * offset.dot(torus.axis)
        return offset * (4.0 * q)
            - radial * (8.0 * torus.majorRadius * torus.majorRadius)
    }

    private static func torusHessianBilinear(
        offset: Vector3D,
        first: Vector3D,
        second: Vector3D,
        torus: GeneralTorusTorusSurfaceIntersector.Torus
    ) -> Double {
        let q = offset.dot(offset)
            + torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        return 8.0 * offset.dot(first) * offset.dot(second)
            + 4.0 * q * first.dot(second)
            - 8.0 * torus.majorRadius * torus.majorRadius * (
                first.dot(second)
                    - first.dot(torus.axis) * second.dot(torus.axis)
            )
    }

    private static func derivativeThreshold(
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.angle * pow(configuration.characteristicLength, 4.0),
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 4.0) * 256.0
        )
    }

    private static func residualUpperBound(
        configuration: GeneralTorusTorusSurfaceIntersector.Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 1_048_576.0
        guard machineBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: machineBound,
                tolerance: tolerance,
                message: "General torus-torus reconstruction cannot satisfy the requested geometric tolerance."
            )
        }
        return tolerance.distance
    }

    private static func orderedSurfaces(
        first: Surface3D,
        second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (first: Surface3D, second: Surface3D) {
        guard case let .torus(firstSource) = CanonicalAnalyticSurface(first),
              case let .torus(secondSource) = CanonicalAnalyticSurface(second) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General torus-torus ordering requires two exact tori."
            )
        }
        let intersector = GeneralTorusTorusSurfaceIntersector()
        let firstTorus = try intersector.canonicalTorus(
            firstSource,
            tolerance: tolerance
        )
        let secondTorus = try intersector.canonicalTorus(
            secondSource,
            tolerance: tolerance
        )
        return intersector.torusKey(firstTorus)
            .lexicographicallyPrecedes(intersector.torusKey(secondTorus))
            ? (first, second)
            : (second, first)
    }

    private static func options(
        maximumSubdivisionDepth: Int,
        maximumIterations: Int,
        maximumSeedCount: Int
    ) -> SurfaceSurfaceIntersectionOptions {
        SurfaceSurfaceIntersectionOptions(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumIterations: maximumIterations,
            maximumSeedCount: maximumSeedCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case parameterizedSurface
        case referenceSurface
        case componentIndex
        case componentCount
        case maximumSubdivisionDepth
        case maximumIterations
        case maximumSeedCount
        case certificationTolerance
        case maximumResidualUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .parameterizedSurface,
                .referenceSurface,
                .componentIndex,
                .componentCount,
                .maximumSubdivisionDepth,
                .maximumIterations,
                .maximumSeedCount,
                .certificationTolerance,
                .maximumResidualUpperBound,
            ],
            in: decoder
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        try self.init(
            parameterizedSurface: container.decode(
                Surface3D.self,
                forKey: .parameterizedSurface
            ),
            referenceSurface: container.decode(
                Surface3D.self,
                forKey: .referenceSurface
            ),
            componentIndex: container.decode(Int.self, forKey: .componentIndex),
            maximumSubdivisionDepth: container.decode(
                Int.self,
                forKey: .maximumSubdivisionDepth
            ),
            maximumIterations: container.decode(
                Int.self,
                forKey: .maximumIterations
            ),
            maximumSeedCount: container.decode(
                Int.self,
                forKey: .maximumSeedCount
            ),
            tolerance: tolerance
        )
        let storedComponentCount = try container.decode(
            Int.self,
            forKey: .componentCount
        )
        guard storedComponentCount == componentCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .componentCount,
                in: container,
                debugDescription: "The general torus-torus component count does not match its regenerated periodic certificate."
            )
        }
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumResidualUpperBound,
                in: container,
                debugDescription: "The general torus-torus residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameterizedSurface, forKey: .parameterizedSurface)
        try container.encode(referenceSurface, forKey: .referenceSurface)
        try container.encode(componentIndex, forKey: .componentIndex)
        try container.encode(componentCount, forKey: .componentCount)
        try container.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try container.encode(maximumIterations, forKey: .maximumIterations)
        try container.encode(maximumSeedCount, forKey: .maximumSeedCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
