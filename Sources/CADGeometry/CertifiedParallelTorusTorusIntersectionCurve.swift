import CADCore
import Foundation

public struct CertifiedParallelTorusTorusIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case regularClosed
        case nodalSelfLoop
        case nearNodalClosedLoop
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct Configuration {
        let primary: Torus
        let secondary: Torus
        let radialDirection: Vector3D
        let quarterDirection: Vector3D
        let radialOffset: Double
        let axialOffset: Double
        let characteristicLength: Double

        func contactNormalResidual(
            tubeAngle: Double,
            secondaryRadialSign: Double,
            intersectionSign: Double,
            tolerance: ModelingTolerance
        ) -> Double? {
            let cosine = cos(tubeAngle)
            let sine = sin(tubeAngle)
            let primaryRadius = primary.majorRadius + primary.minorRadius * cosine
            let primaryHeight = primary.minorRadius * sine
            let secondaryHeight = axialOffset + primaryHeight
            let secondaryTubeSquared = secondary.minorRadius * secondary.minorRadius
                - secondaryHeight * secondaryHeight
            let algebraicTolerance = tolerance.distance
                * characteristicLength * 8.0
            guard primaryRadius > tolerance.distance,
                  secondaryTubeSquared >= -algebraicTolerance else {
                return nil
            }
            let secondaryTubeRadius = sqrt(max(secondaryTubeSquared, 0.0))
            let secondaryRadius = secondary.majorRadius
                + secondaryRadialSign * secondaryTubeRadius
            guard secondaryRadius > tolerance.distance else { return nil }
            let radialCoordinate = (
                primaryRadius * primaryRadius
                    + radialOffset * radialOffset
                    - secondaryRadius * secondaryRadius
            ) / (2.0 * radialOffset)
            let transverseSquared = primaryRadius * primaryRadius
                - radialCoordinate * radialCoordinate
            guard transverseSquared >= -algebraicTolerance else { return nil }
            let transverseCoordinate = intersectionSign
                * sqrt(max(transverseSquared, 0.0))
            let primaryRadial = radialDirection * (radialCoordinate / primaryRadius)
                + quarterDirection * (transverseCoordinate / primaryRadius)
            let secondaryRadial = radialDirection
                    * ((radialCoordinate - radialOffset) / secondaryRadius)
                + quarterDirection * (transverseCoordinate / secondaryRadius)
            let primaryNormal = primaryRadial * cosine + primary.axis * sine
            let secondaryNormal = secondaryRadial
                    * (secondaryRadialSign * secondaryTubeRadius / secondary.minorRadius)
                + secondary.axis * (secondaryHeight / secondary.minorRadius)
            guard primaryNormal.isFinite, secondaryNormal.isFinite else { return nil }
            return primaryNormal.cross(secondaryNormal).length
        }
    }

    private struct Certificate: Hashable, Sendable {
        let componentKind: ComponentKind
        let processedCellCount: Int

        var branchCount: Int {
            componentKind == .nearNodalClosedLoop ? 2 : 4
        }
    }

    private struct NodalContactCertificate {
        let contactResidualUpperBound: Double
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        init(_ lower: Double, _ upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        static func constant(_ value: Double) -> Interval {
            Interval(value, value)
        }

        var width: Double { upper - lower }
        var midpoint: Double { lower + width * 0.5 }
        var containsZero: Bool { lower <= 0.0 && upper >= 0.0 }

        func adding(_ other: Interval) -> Interval {
            Interval(lower + other.lower, upper + other.upper)
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(lower - other.upper, upper - other.lower)
        }

        func multiplied(by other: Interval) -> Interval {
            let values = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Interval(
                values.min() ?? -.infinity,
                values.max() ?? .infinity
            )
        }

        func divided(by other: Interval) -> Interval? {
            guard other.containsZero == false else { return nil }
            let values = [
                lower / other.lower,
                lower / other.upper,
                upper / other.lower,
                upper / other.upper,
            ]
            return Interval(
                values.min() ?? -.infinity,
                values.max() ?? .infinity
            )
        }

        func scaled(by scalar: Double) -> Interval {
            scalar >= 0.0
                ? Interval(lower * scalar, upper * scalar)
                : Interval(upper * scalar, lower * scalar)
        }

        func squared() -> Interval {
            if containsZero {
                return Interval(0.0, max(lower * lower, upper * upper))
            }
            return Interval(
                min(lower * lower, upper * upper),
                max(lower * lower, upper * upper)
            )
        }

        func squareRoot() -> Interval? {
            guard lower >= 0.0 else { return nil }
            return Interval(sqrt(lower), sqrt(upper))
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double
        let third: Double

        static func constant(_ value: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value,
                first: 0.0,
                second: 0.0,
                third: 0.0
            )
        }

        func adding(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second,
                third: third + other.third
            )
        }

        func subtracting(_ other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value - other.value,
                first: first - other.first,
                second: second - other.second,
                third: third - other.third
            )
        }

        func multiplied(by other: ScalarDifferential) -> ScalarDifferential {
            ScalarDifferential(
                value: value * other.value,
                first: first * other.value + value * other.first,
                second: second * other.value
                    + 2.0 * first * other.first
                    + value * other.second,
                third: third * other.value
                    + 3.0 * second * other.first
                    + 3.0 * first * other.second
                    + value * other.third
            )
        }

        func scaled(by scalar: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scalar,
                first: first * scalar,
                second: second * scalar,
                third: third * scalar
            )
        }

        func divided(by scalar: Double) -> ScalarDifferential {
            scaled(by: 1.0 / scalar)
        }

        func squared() -> ScalarDifferential {
            multiplied(by: self)
        }

        func squareRoot(
            tolerance: ModelingTolerance,
            message: String
        ) throws -> ScalarDifferential {
            guard value.isFinite, value > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: value,
                    tolerance: tolerance,
                    message: message
                )
            }
            let root = sqrt(value)
            let rootFirst = first / (2.0 * root)
            let rootSecond = second / (2.0 * root)
                - first * first / (4.0 * root * root * root)
            return ScalarDifferential(
                value: root,
                first: rootFirst,
                second: rootSecond,
                third: third / (2.0 * root)
                    - 3.0 * rootFirst * rootSecond / root
            )
        }
    }

    public let primarySurface: Surface3D
    public let secondarySurface: Surface3D
    public let componentKind: ComponentKind
    public let branchIndex: Int
    public let branchCount: Int
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    private let certificate: Certificate

    public init(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int = 24,
        maximumCellCount: Int = 65_536,
        tolerance: ModelingTolerance
    ) throws {
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        let certificate = try Self.makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        try self.init(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            branchIndex: branchIndex,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance,
            configuration: configuration,
            certificate: certificate
        )
    }

    private init(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance,
        configuration: Configuration,
        certificate: Certificate
    ) throws {
        self.primarySurface = primarySurface
        self.secondarySurface = secondarySurface
        componentKind = certificate.componentKind
        self.branchIndex = branchIndex
        branchCount = certificate.branchCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
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
    ) throws -> [CertifiedParallelTorusTorusIntersectionCurve] {
        try options.validate(tolerance: tolerance)
        let ordered = try orderedSurfaces(
            first: firstTorusSurface,
            second: secondTorusSurface,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            primarySurface: ordered.primary,
            secondarySurface: ordered.secondary,
            tolerance: tolerance
        )
        if boundingSpheresAreSeparated(
            first: configuration.primary,
            second: configuration.secondary,
            tolerance: tolerance
        ) {
            return []
        }
        let maximumSubdivisionDepth = min(
            options.maximumSubdivisionDepth + 12,
            24
        )
        let maximumCellCount = min(
            max(options.maximumSeedCount * 16, 4_096),
            65_536
        )
        let certificate = try makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        return try (0..<certificate.branchCount).map { branchIndex in
            try CertifiedParallelTorusTorusIntersectionCurve(
                primarySurface: ordered.primary,
                secondarySurface: ordered.secondary,
                branchIndex: branchIndex,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance,
                configuration: configuration,
                certificate: certificate
            )
        }
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
                message: "A parallel torus-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 24,
              maximumCellCount > 0,
              maximumCellCount <= 65_536,
              branchCount == certificate.branchCount,
              branchIndex >= 0,
              branchIndex < branchCount,
              certificate.componentKind == componentKind,
              certificate.processedCellCount > 0,
              certificate.processedCellCount <= maximumCellCount,
              maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound > 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A parallel torus-torus branch has an invalid stored completeness certificate."
            )
        }
        let reproducedBound = try Self.residualUpperBound(
            configuration: configuration,
            tolerance: tolerance
        )
        guard maximumResidualUpperBound == reproducedBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A parallel torus-torus residual certificate no longer matches its source surfaces."
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
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        let period = 2.0 * Double.pi
        let signs = componentKind == .nearNodalClosedLoop
            ? (
                secondaryRadial: branchIndex == 0 ? -1.0 : 1.0,
                intersection: clamped <= 0.5 ? 1.0 : -1.0
            )
            : Self.branchSigns(branchIndex)
        let nodalBaseAngle = signs.secondaryRadial < 0.0 ? 0.0 : Double.pi
        let angle: ScalarDifferential
        if componentKind == .nearNodalClosedLoop {
            let contactAngle = try Self.nearNodalContactAngle(
                configuration: configuration,
                tolerance: tolerance
            )
            let lower = signs.secondaryRadial < 0.0
                ? contactAngle
                : Double.pi + contactAngle
            let upper = signs.secondaryRadial < 0.0
                ? period - contactAngle
                : 3.0 * Double.pi - contactAngle
            let span = upper - lower
            let phase = Double.pi * clamped
            angle = ScalarDifferential(
                value: lower + span * pow(sin(phase), 2.0),
                first: span * Double.pi * sin(2.0 * phase),
                second: span * 2.0 * pow(Double.pi, 2.0)
                    * cos(2.0 * phase),
                third: -span * 4.0 * pow(Double.pi, 3.0)
                    * sin(2.0 * phase)
            )
        } else {
            let baseAngle = componentKind == .nodalSelfLoop ? nodalBaseAngle : 0.0
            angle = ScalarDifferential(
                value: clamped == 1.0 ? baseAngle : baseAngle + period * clamped,
                first: period,
                second: 0.0,
                third: 0.0
            )
        }
        let differentials = try Self.intersectionDifferentials(
            angle: angle,
            secondaryRadialSign: signs.secondaryRadial,
            configuration: configuration,
            tolerance: tolerance
        )
        let primaryHeight = differentials.primaryHeight
        let primaryRadius = differentials.primaryRadius
        let radialCoordinate = differentials.radialCoordinate
        let transverseCoordinate = try signedTransverseCoordinate(
            squared: differentials.transverseSquared,
            fraction: clamped,
            branchSign: signs.intersection,
            tolerance: tolerance
        )
        let endpointThreshold = Double.ulpOfOne * 1_024.0
        let isNodalEndpoint = componentKind == .nodalSelfLoop
            && (clamped <= endpointThreshold
                || 1.0 - clamped <= endpointThreshold)
        let isNearNodalJoin = componentKind == .nearNodalClosedLoop
            && (clamped <= endpointThreshold
                || abs(clamped - 0.5) <= endpointThreshold
                || 1.0 - clamped <= endpointThreshold)
        let radialValue: Double
        if isNodalEndpoint || isNearNodalJoin {
            radialValue = signs.secondaryRadial < 0.0
                ? primaryRadius.value
                : -primaryRadius.value
        } else {
            radialValue = radialCoordinate.value
        }
        let position = configuration.primary.center
            + configuration.primary.axis * primaryHeight.value
            + configuration.radialDirection * radialValue
            + configuration.quarterDirection * transverseCoordinate.value
        let firstDerivative = configuration.primary.axis * primaryHeight.first
            + configuration.radialDirection * radialCoordinate.first
            + configuration.quarterDirection * transverseCoordinate.first
        let secondDerivative = configuration.primary.axis * primaryHeight.second
            + configuration.radialDirection * radialCoordinate.second
            + configuration.quarterDirection * transverseCoordinate.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified parallel torus-torus component has a singular differential."
            )
        }
        let primaryProjection = try primarySurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let secondaryProjection = try secondarySurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let residual = max(primaryProjection.residual, secondaryProjection.residual)
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified parallel torus-torus branch exceeded its geometric residual bound."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        guard surface == primarySurface || surface == secondarySurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A parallel torus-torus pcurve was requested on an unrelated surface."
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
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        let radius = configuration.primary.majorRadius
            + configuration.primary.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.primary.center.x - radius,
                y: configuration.primary.center.y - radius,
                z: configuration.primary.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.primary.center.x + radius,
                y: configuration.primary.center.y + radius,
                z: configuration.primary.center.z + radius
            )
        )
    }

    private func signedTransverseCoordinate(
        squared: ScalarDifferential,
        fraction: Double,
        branchSign: Double,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let endpointThreshold = Double.ulpOfOne * 1_024.0
        if componentKind == .nodalSelfLoop {
            let isLower = fraction <= endpointThreshold
            let isUpper = 1.0 - fraction <= endpointThreshold
            if isLower || isUpper {
                let rootSlopeMagnitude = sqrt(max(squared.second * 0.5, 0.0))
                guard rootSlopeMagnitude > tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: rootSlopeMagnitude,
                        tolerance: tolerance,
                        message: "A nodal torus-torus component has no regular one-sided branch."
                    )
                }
                let unsignedFirst = isLower
                    ? rootSlopeMagnitude
                    : -rootSlopeMagnitude
                let unsignedSecond = squared.third / (6.0 * unsignedFirst)
                return ScalarDifferential(
                    value: 0.0,
                    first: branchSign * unsignedFirst,
                    second: branchSign * unsignedSecond,
                    third: 0.0
                )
            }
        }
        if componentKind == .nearNodalClosedLoop {
            let isLower = fraction <= endpointThreshold
            let isMiddle = abs(fraction - 0.5) <= endpointThreshold
            let isUpper = 1.0 - fraction <= endpointThreshold
            if isLower || isMiddle || isUpper {
                let rootSlopeMagnitude = sqrt(max(squared.second * 0.5, 0.0))
                guard rootSlopeMagnitude > tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: rootSlopeMagnitude,
                        tolerance: tolerance,
                        message: "A near-nodal torus-torus component has no regular joined branch."
                    )
                }
                let signedFirst = isMiddle
                    ? -rootSlopeMagnitude
                    : rootSlopeMagnitude
                return ScalarDifferential(
                    value: 0.0,
                    first: signedFirst,
                    second: squared.third / (6.0 * signedFirst),
                    third: 0.0
                )
            }
        }
        return try squared.squareRoot(
            tolerance: tolerance,
            message: "A certified torus-torus branch reached a circle-intersection tangency."
        ).scaled(by: branchSign)
    }

    private static func makeConfiguration(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try primarySurface.validate(tolerance: tolerance)
        try secondarySurface.validate(tolerance: tolerance)
        guard case let .torus(primarySource) = CanonicalAnalyticSurface(
            primarySurface
        ), case let .torus(secondarySource) = CanonicalAnalyticSurface(
            secondarySurface
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified parallel torus-torus curve requires two exact tori."
            )
        }
        let primary = try canonicalTorus(primarySource, tolerance: tolerance)
        let secondary = try canonicalTorus(secondarySource, tolerance: tolerance)
        guard AnalyticAxisRelation.areParallel(
            primary.axis,
            secondary.axis,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: primary.axis.cross(secondary.axis).length,
                tolerance: tolerance,
                message: "A certified parallel torus-torus curve requires parallel axes."
            )
        }
        let centerOffset = secondary.center - primary.center
        let axialCenterOffset = centerOffset.dot(primary.axis)
        let radialCenterOffset = centerOffset - primary.axis * axialCenterOffset
        let radialOffset = radialCenterOffset.length
        guard radialOffset > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: radialOffset,
                tolerance: tolerance,
                message: "A certified parallel torus-torus curve requires distinct axes."
            )
        }
        let radialDirection = try radialCenterOffset.normalized(
            tolerance: tolerance.distance
        )
        let quarterDirection = try primary.axis.cross(radialDirection).normalized(
            tolerance: tolerance.distance
        )
        return Configuration(
            primary: primary,
            secondary: secondary,
            radialDirection: radialDirection,
            quarterDirection: quarterDirection,
            radialOffset: radialOffset,
            axialOffset: -axialCenterOffset,
            characteristicLength: max(
                primary.majorRadius + primary.minorRadius,
                secondary.majorRadius + secondary.minorRadius,
                centerOffset.length,
                1.0
            )
        )
    }

    private static func intersectionDifferentials(
        angle: ScalarDifferential,
        secondaryRadialSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> (
        primaryRadius: ScalarDifferential,
        primaryHeight: ScalarDifferential,
        radialCoordinate: ScalarDifferential,
        transverseSquared: ScalarDifferential
    ) {
        let cosine = cosine(angle)
        let sine = sine(angle)
        let primaryRadius = ScalarDifferential
            .constant(configuration.primary.majorRadius)
            .adding(cosine.scaled(by: configuration.primary.minorRadius))
        let primaryHeight = sine.scaled(by: configuration.primary.minorRadius)
        let secondaryHeight = ScalarDifferential
            .constant(configuration.axialOffset)
            .adding(primaryHeight)
        let secondaryTubeSquared = ScalarDifferential
            .constant(
                configuration.secondary.minorRadius
                    * configuration.secondary.minorRadius
            )
            .subtracting(secondaryHeight.squared())
        let secondaryTubeRadius = try secondaryTubeSquared.squareRoot(
            tolerance: tolerance,
            message: "A certified torus-torus branch reached a secondary tube-height singularity."
        )
        let secondaryRadius = ScalarDifferential
            .constant(configuration.secondary.majorRadius)
            .adding(secondaryTubeRadius.scaled(by: secondaryRadialSign))
        let radialCoordinate = primaryRadius.squared()
            .adding(.constant(
                configuration.radialOffset * configuration.radialOffset
            ))
            .subtracting(secondaryRadius.squared())
            .divided(by: 2.0 * configuration.radialOffset)
        return (
            primaryRadius,
            primaryHeight,
            radialCoordinate,
            primaryRadius.squared().subtracting(radialCoordinate.squared())
        )
    }

    private static func orderedSurfaces(
        first: Surface3D,
        second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> (primary: Surface3D, secondary: Surface3D) {
        guard case let .torus(firstSource) = CanonicalAnalyticSurface(first),
              case let .torus(secondSource) = CanonicalAnalyticSurface(second) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Parallel torus-torus ordering requires two exact tori."
            )
        }
        let firstTorus = try canonicalTorus(firstSource, tolerance: tolerance)
        let secondTorus = try canonicalTorus(secondSource, tolerance: tolerance)
        return torusKey(firstTorus).lexicographicallyPrecedes(torusKey(secondTorus))
            ? (first, second)
            : (second, first)
    }

    private static func makeCertificate(
        configuration: Configuration,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance
    ) throws -> Certificate {
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 24,
              maximumCellCount > 0,
              maximumCellCount <= 65_536 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Parallel torus-torus certification limits are invalid."
            )
        }
        if try nodalContactCertificate(
            configuration: configuration,
            tolerance: tolerance
        ) != nil {
            return Certificate(
                componentKind: .nodalSelfLoop,
                processedCellCount: 2
            )
        }
        if try nearNodalContactAngle(
            configuration: configuration,
            tolerance: tolerance
        ) > 0.0 {
            let conditioningFloor = configuration.characteristicLength
                / Double(maximumCellCount).squareRoot()
            let nodalMargin = configuration.primary.minorRadius
                + configuration.secondary.minorRadius
                - configuration.radialOffset
            if nodalMargin > tolerance.distance,
               nodalMargin <= conditioningFloor {
                return Certificate(
                    componentKind: .nearNodalClosedLoop,
                    processedCellCount: 2
                )
            }
        }
        var processedCellCount = 0
        for secondaryRadialSign in [-1.0, 1.0] {
            try certify(
                angle: Interval(0.0, 2.0 * Double.pi),
                secondaryRadialSign: secondaryRadialSign,
                depth: 0,
                maximumDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                processedCellCount: &processedCellCount,
                configuration: configuration,
                tolerance: tolerance
            )
        }
        return Certificate(
            componentKind: .regularClosed,
            processedCellCount: processedCellCount
        )
    }

    private static func nodalContactCertificate(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> NodalContactCertificate? {
        let arithmeticLengthTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 32_768.0
        let majorRadiusResidual = abs(
            configuration.primary.majorRadius - configuration.secondary.majorRadius
        )
        let axialResidual = abs(configuration.axialOffset)
        let radialResidual = abs(
            configuration.radialOffset
                - configuration.primary.minorRadius
                - configuration.secondary.minorRadius
        )
        guard majorRadiusResidual <= arithmeticLengthTolerance,
              axialResidual <= arithmeticLengthTolerance,
              radialResidual <= arithmeticLengthTolerance,
              configuration.secondary.minorRadius
                - configuration.primary.minorRadius > arithmeticLengthTolerance else {
            return nil
        }

        let arithmeticSquaredTolerance = Double.ulpOfOne
            * pow(configuration.characteristicLength, 2.0) * 131_072.0
        for (secondaryRadialSign, nodeAngle) in [
            (-1.0, 0.0),
            (1.0, Double.pi),
        ] {
            let angle = ScalarDifferential(
                value: nodeAngle,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
            let differential = try intersectionDifferentials(
                angle: angle,
                secondaryRadialSign: secondaryRadialSign,
                configuration: configuration,
                tolerance: tolerance
            ).transverseSquared
            guard abs(differential.value) <= arithmeticSquaredTolerance,
                  abs(differential.first) <= arithmeticSquaredTolerance,
                  differential.second > arithmeticSquaredTolerance else {
                return nil
            }
        }

        let contactResidual = majorRadiusResidual + axialResidual + radialResidual
        guard contactResidual <= tolerance.distance else { return nil }
        return NodalContactCertificate(
            contactResidualUpperBound: contactResidual
        )
    }

    private static func nearNodalContactAngle(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let arithmeticLengthTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 32_768.0
        guard abs(
            configuration.primary.majorRadius
                - configuration.secondary.majorRadius
        ) <= arithmeticLengthTolerance,
        abs(configuration.axialOffset) <= arithmeticLengthTolerance else {
            return 0.0
        }
        let firstRadius = configuration.primary.minorRadius
        let secondRadius = configuration.secondary.minorRadius
        let distance = configuration.radialOffset
        guard distance < firstRadius + secondRadius - tolerance.distance,
              distance > abs(secondRadius - firstRadius) + tolerance.distance else {
            return 0.0
        }
        let cosine = (
            distance * distance
                + firstRadius * firstRadius
                - secondRadius * secondRadius
        ) / (2.0 * distance * firstRadius)
        guard cosine > -1.0, cosine < 1.0 else {
            return 0.0
        }
        return acos(cosine)
    }

    private static func certify(
        angle: Interval,
        secondaryRadialSign: Double,
        depth: Int,
        maximumDepth: Int,
        maximumCellCount: Int,
        processedCellCount: inout Int,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws {
        processedCellCount += 1
        guard processedCellCount <= maximumCellCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(processedCellCount),
                tolerance: tolerance,
                message: "Parallel torus-torus branch certification exceeded its cell limit."
            )
        }
        if branchIsCertified(
            angle: angle,
            secondaryRadialSign: secondaryRadialSign,
            configuration: configuration,
            tolerance: tolerance
        ) {
            return
        }
        if let residual = singularContactResidual(
            angle: angle,
            secondaryRadialSign: secondaryRadialSign,
            configuration: configuration,
            tolerance: tolerance
        ) {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: residual,
                tolerance: tolerance,
                message: "Parallel-offset tori have a verified rank-deficient contact."
            )
        }
        guard depth < maximumDepth else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: angle.width,
                tolerance: tolerance,
                message: "Parallel torus-torus subdivision exhausted its budget before certifying four complete simple branches."
            )
        }
        let middle = angle.midpoint
        try certify(
            angle: Interval(angle.lower, middle),
            secondaryRadialSign: secondaryRadialSign,
            depth: depth + 1,
            maximumDepth: maximumDepth,
            maximumCellCount: maximumCellCount,
            processedCellCount: &processedCellCount,
            configuration: configuration,
            tolerance: tolerance
        )
        try certify(
            angle: Interval(middle, angle.upper),
            secondaryRadialSign: secondaryRadialSign,
            depth: depth + 1,
            maximumDepth: maximumDepth,
            maximumCellCount: maximumCellCount,
            processedCellCount: &processedCellCount,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private static func singularContactResidual(
        angle: Interval,
        secondaryRadialSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double? {
        let candidates = [angle.lower, angle.midpoint, angle.upper]
        var minimumResidual = Double.infinity
        for candidate in candidates {
            for intersectionSign in [-1.0, 1.0] {
                guard let residual = configuration.contactNormalResidual(
                    tubeAngle: candidate,
                    secondaryRadialSign: secondaryRadialSign,
                    intersectionSign: intersectionSign,
                    tolerance: tolerance
                ) else {
                    continue
                }
                minimumResidual = min(minimumResidual, residual)
            }
        }
        let threshold = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * 1_024.0
        )
        return minimumResidual <= threshold ? minimumResidual : nil
    }

    private static func branchIsCertified(
        angle: Interval,
        secondaryRadialSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Bool {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let primaryRadius = Interval.constant(configuration.primary.majorRadius)
            .adding(cosine.scaled(by: configuration.primary.minorRadius))
        guard primaryRadius.lower > tolerance.distance else { return false }
        let secondaryHeight = Interval.constant(configuration.axialOffset)
            .adding(sine.scaled(by: configuration.primary.minorRadius))
        let secondaryTubeSquared = Interval.constant(
            configuration.secondary.minorRadius
                * configuration.secondary.minorRadius
        ).subtracting(secondaryHeight.squared())
        guard let secondaryTubeRadius = secondaryTubeSquared.squareRoot() else {
            return false
        }
        let secondaryRadius = Interval.constant(configuration.secondary.majorRadius)
            .adding(secondaryTubeRadius.scaled(by: secondaryRadialSign))
        guard secondaryRadius.lower > tolerance.distance else { return false }
        let radialNumerator = primaryRadius.squared()
            .adding(.constant(
                configuration.radialOffset * configuration.radialOffset
            ))
            .subtracting(secondaryRadius.squared())
        let radialDenominator = primaryRadius.scaled(
            by: 2.0 * configuration.radialOffset
        )
        guard let circleCosine = radialNumerator.divided(by: radialDenominator) else {
            return false
        }
        let circleMargin = max(
            tolerance.distance / configuration.characteristicLength * 8.0,
            Double.ulpOfOne * 1_024.0
        )
        guard circleCosine.lower > -1.0 + circleMargin,
              circleCosine.upper < 1.0 - circleMargin else {
            return false
        }
        let radialDotNumerator = primaryRadius.squared()
            .adding(secondaryRadius.squared())
            .subtracting(.constant(
                configuration.radialOffset * configuration.radialOffset
            ))
        let radialDotDenominator = primaryRadius.multiplied(by: secondaryRadius)
            .scaled(by: 2.0)
        guard let radialDot = radialDotNumerator.divided(by: radialDotDenominator) else {
            return false
        }
        let secondaryCosine = secondaryTubeRadius.scaled(
            by: secondaryRadialSign / configuration.secondary.minorRadius
        )
        let secondarySine = secondaryHeight.scaled(
            by: 1.0 / configuration.secondary.minorRadius
        )
        let normalDot = cosine.multiplied(by: secondaryCosine)
            .multiplied(by: radialDot)
            .adding(sine.multiplied(by: secondarySine))
        let normalMargin = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * 1_024.0
        )
        return normalDot.lower > -1.0 + normalMargin
            && normalDot.upper < 1.0 - normalMargin
    }

    private static func residualUpperBound(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 1_048_576.0
        let nodalBound = try nodalContactCertificate(
            configuration: configuration,
            tolerance: tolerance
        )?.contactResidualUpperBound ?? 0.0
        let result = machineBound + nodalBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Parallel torus-torus algebraic reconstruction cannot satisfy the requested geometric tolerance."
            )
        }
        return result
    }

    private static func boundingSpheresAreSeparated(
        first: Torus,
        second: Torus,
        tolerance: ModelingTolerance
    ) -> Bool {
        let firstRadius = first.majorRadius + first.minorRadius
        let secondRadius = second.majorRadius + second.minorRadius
        return (first.center - second.center).length
            > firstRadius + secondRadius + tolerance.distance
    }

    private static func branchSigns(
        _ branchIndex: Int
    ) -> (secondaryRadial: Double, intersection: Double) {
        (
            branchIndex < 2 ? -1.0 : 1.0,
            branchIndex.isMultiple(of: 2) ? -1.0 : 1.0
        )
    }

    private static func cosine(
        _ angle: ScalarDifferential
    ) -> ScalarDifferential {
        let value = cos(angle.value)
        let sine = sin(angle.value)
        return ScalarDifferential(
            value: value,
            first: -sine * angle.first,
            second: -value * angle.first * angle.first
                - sine * angle.second,
            third: sine * angle.first * angle.first * angle.first
                - 3.0 * value * angle.first * angle.second
                - sine * angle.third
        )
    }

    private static func sine(
        _ angle: ScalarDifferential
    ) -> ScalarDifferential {
        let value = sin(angle.value)
        let cosine = cos(angle.value)
        return ScalarDifferential(
            value: value,
            first: cosine * angle.first,
            second: -value * angle.first * angle.first
                + cosine * angle.second,
            third: -cosine * angle.first * angle.first * angle.first
                - 3.0 * value * angle.first * angle.second
                + cosine * angle.third
        )
    }

    private static func cosineInterval(_ angle: Interval) -> Interval {
        trigonometricInterval(angle, phase: 0.0)
    }

    private static func sineInterval(_ angle: Interval) -> Interval {
        trigonometricInterval(angle, phase: Double.pi * 0.5)
    }

    private static func trigonometricInterval(
        _ angle: Interval,
        phase: Double
    ) -> Interval {
        guard angle.width < 2.0 * Double.pi else {
            return Interval(-1.0, 1.0)
        }
        let first = cos(angle.lower - phase)
        let second = cos(angle.upper - phase)
        var lower = min(first, second)
        var upper = max(first, second)
        if containsPeriodicValue(
            angle,
            value: phase,
            period: 2.0 * Double.pi
        ) {
            upper = 1.0
        }
        if containsPeriodicValue(
            angle,
            value: phase + Double.pi,
            period: 2.0 * Double.pi
        ) {
            lower = -1.0
        }
        return Interval(lower, upper)
    }

    private static func containsPeriodicValue(
        _ interval: Interval,
        value: Double,
        period: Double
    ) -> Bool {
        let firstIndex = ceil((interval.lower - value) / period)
        return value + firstIndex * period <= interval.upper
    }

    private static func canonicalTorus(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    ) throws -> Torus {
        var axis = try torus.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        return Torus(
            center: torus.center,
            axis: axis,
            majorRadius: torus.majorRadius,
            minorRadius: torus.minorRadius
        )
    }

    private static func torusKey(_ torus: Torus) -> [Double] {
        [
            torus.minorRadius,
            torus.majorRadius,
            torus.center.x,
            torus.center.y,
            torus.center.z,
            torus.axis.x,
            torus.axis.y,
            torus.axis.z,
        ]
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case primarySurface
        case secondarySurface
        case componentKind
        case branchIndex
        case branchCount
        case maximumSubdivisionDepth
        case maximumCellCount
        case certificationTolerance
        case maximumResidualUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .primarySurface,
                .secondarySurface,
                .componentKind,
                .branchIndex,
                .branchCount,
                .maximumSubdivisionDepth,
                .maximumCellCount,
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
            primarySurface: container.decode(
                Surface3D.self,
                forKey: .primarySurface
            ),
            secondarySurface: container.decode(
                Surface3D.self,
                forKey: .secondarySurface
            ),
            branchIndex: container.decode(Int.self, forKey: .branchIndex),
            maximumSubdivisionDepth: container.decode(
                Int.self,
                forKey: .maximumSubdivisionDepth
            ),
            maximumCellCount: container.decode(
                Int.self,
                forKey: .maximumCellCount
            ),
            tolerance: tolerance
        )
        let storedBranchCount = try container.decode(Int.self, forKey: .branchCount)
        guard storedBranchCount == branchCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .branchCount,
                in: container,
                debugDescription: "The parallel torus-torus branch count does not match its regenerated certificate."
            )
        }
        let storedComponentKind = try container.decode(
            ComponentKind.self,
            forKey: .componentKind
        )
        guard storedComponentKind == componentKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .componentKind,
                in: container,
                debugDescription: "The parallel torus-torus component kind does not match its regenerated certificate."
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
                debugDescription: "The parallel torus-torus residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primarySurface, forKey: .primarySurface)
        try container.encode(secondarySurface, forKey: .secondarySurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(branchIndex, forKey: .branchIndex)
        try container.encode(branchCount, forKey: .branchCount)
        try container.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try container.encode(maximumCellCount, forKey: .maximumCellCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
