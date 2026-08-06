import CADCore
import Foundation
import Synchronization

public struct CertifiedPlaneTorusIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedMinorAngle
        case negativeInnerTangencyBranch
        case positiveInnerTangencyBranch
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double

        var coefficientScale: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                1.0
            )
        }

        var absoluteUpperBound: Double {
            (
                abs(constant)
                    + abs(cosine)
                    + abs(sine)
                    + abs(cosineDouble)
            ).nextUp
        }

        var firstDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 2.0 * abs(cosineDouble)
            ).nextUp
        }

        var secondDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 4.0 * abs(cosineDouble)
            ).nextUp
        }

        var thirdDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 8.0 * abs(cosineDouble)
            ).nextUp
        }

        var globalLowerBound: Double {
            var result = constant.nextDown
            for magnitude in [abs(cosine), abs(sine), abs(cosineDouble)] {
                result = (result - magnitude.nextUp).nextDown
            }
            return result
        }

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine,
                constant - cosine + cosineDouble,
            ]
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
        }

        func derivative(at angle: Double) -> Double {
            -cosine * sin(angle)
                + sine * cos(angle)
                - 2.0 * cosineDouble * sin(2.0 * angle)
        }

        func secondDerivative(at angle: Double) -> Double {
            -cosine * cos(angle)
                - sine * sin(angle)
                - 4.0 * cosineDouble * cos(2.0 * angle)
        }

        func thirdDerivative(at angle: Double) -> Double {
            cosine * sin(angle)
                - sine * cos(angle)
                + 8.0 * cosineDouble * sin(2.0 * angle)
        }
    }

    private struct Configuration {
        let plane: CanonicalAnalyticSurface.Plane
        let torus: CanonicalAnalyticSurface.Torus
        let torusBasisU: Vector3D
        let torusBasisV: Vector3D
        let radialNormal: Vector3D
        let radialPerpendicular: Vector3D
        let radialNormalLength: Double
        let axialNormal: Double
        let centerDistance: Double
        let discriminant: TrigonometricPolynomial

        var characteristicLength: Double {
            max(
                torus.majorRadius + torus.minorRadius,
                abs(centerDistance),
                1.0
            )
        }

        var minimumRadialScale: Double {
            torus.majorRadius - torus.minorRadius
        }
    }

    private struct ScalarDifferential {
        let value: Double
        let first: Double
        let second: Double

        static func constant(_ value: Double) -> ScalarDifferential {
            ScalarDifferential(value: value, first: 0.0, second: 0.0)
        }

        func adding(
            _ other: ScalarDifferential
        ) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second
            )
        }

        func subtracting(
            _ other: ScalarDifferential
        ) -> ScalarDifferential {
            ScalarDifferential(
                value: value - other.value,
                first: first - other.first,
                second: second - other.second
            )
        }

        func scaled(by scale: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scale,
                first: first * scale,
                second: second * scale
            )
        }
    }

    private struct InnerTangencyCertificate {
        let minorAngle: Double
        let contactResidualUpperBound: Double
    }

    private struct ValidationCacheKey: Hashable, Sendable {
        let curve: CertifiedPlaneTorusIntersectionCurve
        let tolerance: ModelingTolerance
    }

    // Validation re-isolates the discriminant boundary roots with exact
    // arithmetic and reconstructs sample points, and every evaluation entry
    // point revalidates the same immutable value, so successful validations
    // are memoized per process. Platforms without Synchronization.Mutex
    // hold no cache state and validate every call.
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    private enum ValidationCache {
        static let storage = Mutex<Set<ValidationCacheKey>>([])
    }

    public let planeSurface: Surface3D
    public let torusSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerMinorAngle: Double
    public let upperMinorAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public var parameterDomain: CurveParameterDomain {
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            .periodic(period: 2.0 * Double.pi)
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            .bounded(lower: 0.0, upper: 2.0 * Double.pi)
        }
    }

    public static func regularComponents(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedPlaneTorusIntersectionCurve] {
        try options.validate(tolerance: tolerance)
        let configuration = try makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        if let innerTangency = Self.innerTangencyCertificate(
            configuration: configuration,
            tolerance: tolerance
        ) {
            return try [
                ComponentKind.negativeInnerTangencyBranch,
                .positiveInnerTangencyBranch,
            ].map { componentKind in
                try CertifiedPlaneTorusIntersectionCurve(
                    planeSurface: planeSurface,
                    torusSurface: torusSurface,
                    componentKind: componentKind,
                    lowerMinorAngle: innerTangency.minorAngle,
                    upperMinorAngle: innerTangency.minorAngle + 2.0 * Double.pi,
                    tolerance: tolerance
                )
            }
        }
        let boundaries = try boundaryAngles(
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            options: options,
            tolerance: tolerance
        )
        if boundaries.isEmpty {
            let value = configuration.discriminant.value(at: 0.0)
            if value < -classificationTolerance {
                return []
            }
            guard value > classificationTolerance else {
                throw singularSection(
                    residual: abs(value),
                    tolerance: tolerance,
                    message: "Plane-torus section has an unresolved full-domain tangency."
                )
            }
            return try [
                CertifiedPlaneTorusIntersectionCurve(
                    planeSurface: planeSurface,
                    torusSurface: torusSurface,
                    componentKind: .negativeFullBranch,
                    lowerMinorAngle: 0.0,
                    upperMinorAngle: 2.0 * Double.pi,
                    tolerance: tolerance
                ),
                CertifiedPlaneTorusIntersectionCurve(
                    planeSurface: planeSurface,
                    torusSurface: torusSurface,
                    componentKind: .positiveFullBranch,
                    lowerMinorAngle: 0.0,
                    upperMinorAngle: 2.0 * Double.pi,
                    tolerance: tolerance
                ),
            ]
        }

        guard boundaries.count.isMultiple(of: 2) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(boundaries.count),
                tolerance: tolerance,
                message: "A regular periodic plane-torus quartic must have an even boundary-root count."
            )
        }
        let intervals = try validIntervals(
            boundaries: boundaries,
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            tolerance: tolerance
        )
        return try intervals.map { interval in
            try CertifiedPlaneTorusIntersectionCurve(
                planeSurface: planeSurface,
                torusSurface: torusSurface,
                componentKind: .boundedMinorAngle,
                lowerMinorAngle: interval.lower,
                upperMinorAngle: interval.upper,
                tolerance: tolerance
            )
        }
    }

    public init(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerMinorAngle: Double,
        upperMinorAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.planeSurface = planeSurface
        self.torusSurface = torusSurface
        self.componentKind = componentKind
        self.lowerMinorAngle = lowerMinorAngle
        self.upperMinorAngle = upperMinorAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerMinorAngle: lowerMinorAngle,
            upperMinorAngle: upperMinorAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) else {
            try validateUncached(tolerance: tolerance)
            return
        }
        let key = ValidationCacheKey(curve: self, tolerance: tolerance)
        if ValidationCache.storage.withLock({ $0.contains(key) }) {
            return
        }
        try validateUncached(tolerance: tolerance)
        ValidationCache.storage.withLock { cache in
            if cache.count >= 256 {
                cache.removeAll(keepingCapacity: true)
            }
            cache.insert(key)
        }
    }

    private func validateUncached(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A plane-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        guard lowerMinorAngle.isFinite,
              upperMinorAngle.isFinite,
              upperMinorAngle > lowerMinorAngle,
              upperMinorAngle - lowerMinorAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperMinorAngle - lowerMinorAngle)
        }
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let certifiedBoundaries = try Self.boundaryAngles(
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            )
            guard abs(lowerMinorAngle) <= tolerance.angle,
                  abs(upperMinorAngle - 2.0 * Double.pi) <= tolerance.angle,
                  certifiedBoundaries.isEmpty,
                  configuration.discriminant.value(at: 0.0) > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A full plane-torus branch requires a positive root-free discriminant domain."
                )
            }
        case .boundedMinorAngle:
            let certifiedBoundaries = try Self.boundaryAngles(
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            )
            let lowerResidual = abs(configuration.discriminant.value(at: lowerMinorAngle))
            let upperResidual = abs(configuration.discriminant.value(at: upperMinorAngle))
            let midpoint = lowerMinorAngle + (upperMinorAngle - lowerMinorAngle) * 0.5
            let certifiedIntervals = try Self.validIntervals(
                boundaries: certifiedBoundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                tolerance: tolerance
            )
            let matchesCompleteComponent = certifiedIntervals.contains { interval in
                abs(interval.lower - lowerMinorAngle) <= tolerance.angle
                    && abs(interval.upper - upperMinorAngle) <= tolerance.angle
            }
            guard lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  matchesCompleteComponent,
                  configuration.discriminant.value(at: midpoint) > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded plane-torus component failed quartic endpoint or interior certification."
                )
            }
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard let certificate = Self.innerTangencyCertificate(
                configuration: configuration,
                tolerance: tolerance
            ),
            abs(certificate.minorAngle - lowerMinorAngle) <= tolerance.angle,
            abs(upperMinorAngle - lowerMinorAngle - 2.0 * Double.pi)
                <= tolerance.angle else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An inner-tangent plane-torus branch changed its certified nodal section."
                )
            }
        }
        let reproducedBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerMinorAngle: lowerMinorAngle,
            upperMinorAngle: upperMinorAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        guard maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound >= reproducedBound,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A plane-torus curve exceeded its certified geometric residual."
            )
        }
        for parameter in [
            0.0,
            Double.pi * 0.5,
            Double.pi,
            Double.pi * 1.5,
            2.0 * Double.pi,
        ] {
            let point = try point(at: parameter, tolerance: tolerance)
            let planeProjection = try planeSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            guard max(planeProjection.residual, torusProjection.residual)
                <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(planeProjection.residual, torusProjection.residual),
                    tolerance: tolerance,
                    message: "A plane-torus curve failed its algebraic reconstruction check."
                )
            }
        }
    }

    public func point(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try differentialGeometry(at: parameter, tolerance: tolerance).position
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let curveParameter: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            curveParameter = Self.normalizedAngle(parameter)
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard parameterDomain.contains(parameter, tolerance: tolerance.angle) else {
                throw GeometryError.invalidDistance(parameter)
            }
            curveParameter = min(max(parameter, 0.0), 2.0 * Double.pi)
        }
        let minor = minorAngleDifferential(at: curveParameter)
        let radialScale = configuration.torus.majorRadius
            + configuration.torus.minorRadius * cos(minor.value)
        let radialScaleFirst = -configuration.torus.minorRadius
            * sin(minor.value) * minor.first
        let radialScaleSecond = -configuration.torus.minorRadius * (
            cos(minor.value) * minor.first * minor.first
                + sin(minor.value) * minor.second
        )
        let axialTerm = configuration.centerDistance
            + configuration.torus.minorRadius
                * configuration.axialNormal * sin(minor.value)
        let axialTermFirst = configuration.torus.minorRadius
            * configuration.axialNormal * cos(minor.value) * minor.first
        let axialTermSecond = configuration.torus.minorRadius
            * configuration.axialNormal * (
                -sin(minor.value) * minor.first * minor.first
                    + cos(minor.value) * minor.second
            )
        let radialDiscriminant = pow(
            configuration.radialNormalLength * radialScale,
            2.0
        ) - axialTerm * axialTerm
        let radialDiscriminantFirst = 2.0
            * pow(configuration.radialNormalLength, 2.0)
            * radialScale * radialScaleFirst
            - 2.0 * axialTerm * axialTermFirst
        let radialDiscriminantSecond = 2.0
            * pow(configuration.radialNormalLength, 2.0)
            * (radialScaleFirst * radialScaleFirst + radialScale * radialScaleSecond)
            - 2.0 * (
                axialTermFirst * axialTermFirst + axialTerm * axialTermSecond
            )
        let transverse = try signedSquareRootDifferential(
            value: radialDiscriminant,
            first: radialDiscriminantFirst,
            second: radialDiscriminantSecond,
            minorAngle: minor.value,
            parameter: curveParameter,
            configuration: configuration,
            tolerance: tolerance
        )
        let inverseRadialNormalLength = 1.0 / configuration.radialNormalLength
        let along = ScalarDifferential(
            value: -axialTerm * inverseRadialNormalLength,
            first: -axialTermFirst * inverseRadialNormalLength,
            second: -axialTermSecond * inverseRadialNormalLength
        )
        let across = ScalarDifferential(
            value: transverse.value * inverseRadialNormalLength,
            first: transverse.first * inverseRadialNormalLength,
            second: transverse.second * inverseRadialNormalLength
        )
        let height = ScalarDifferential(
            value: configuration.torus.minorRadius * sin(minor.value),
            first: configuration.torus.minorRadius * cos(minor.value) * minor.first,
            second: configuration.torus.minorRadius * (
                -sin(minor.value) * minor.first * minor.first
                    + cos(minor.value) * minor.second
            )
        )
        let position = configuration.torus.center
            + configuration.radialNormal * along.value
            + configuration.radialPerpendicular * across.value
            + configuration.torus.axis * height.value
        let firstDerivative = configuration.radialNormal * along.first
            + configuration.radialPerpendicular * across.first
            + configuration.torus.axis * height.first
        let secondDerivative = configuration.radialNormal * along.second
            + configuration.radialPerpendicular * across.second
            + configuration.torus.axis * height.second
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified plane-torus component has a singular differential."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    public func surfaceParameters(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> (plane: SurfaceParameter, torus: SurfaceParameter) {
        let point = try point(at: parameter, tolerance: tolerance)
        let planeProjection = try planeSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let curveParameter: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            curveParameter = Self.normalizedAngle(parameter)
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard parameterDomain.contains(parameter, tolerance: tolerance.angle) else {
                throw GeometryError.invalidDistance(parameter)
            }
            curveParameter = min(max(parameter, 0.0), 2.0 * Double.pi)
        }
        let offset = point - configuration.torus.center
        let height = offset.dot(configuration.torus.axis)
        let radial = offset - configuration.torus.axis * height
        let rawMajorAngle = atan2(
            radial.dot(configuration.torusBasisV),
            radial.dot(configuration.torusBasisU)
        )
        let majorAngle: Double
        let minorAngle: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            majorAngle = Self.normalizedAngle(rawMajorAngle)
            minorAngle = Self.normalizedAngle(atan2(
                height,
                radial.length - configuration.torus.majorRadius
            ))
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            let nodeMinorAngle = lowerMinorAngle
            let nodeAxialTerm = configuration.centerDistance
                + configuration.torus.minorRadius
                    * configuration.axialNormal * sin(nodeMinorAngle)
            let nodeAlong = -nodeAxialTerm / configuration.radialNormalLength
            let nodeRadial = configuration.radialNormal * nodeAlong
            let nodeMajorAngle = atan2(
                nodeRadial.dot(configuration.torusBasisV),
                nodeRadial.dot(configuration.torusBasisU)
            )
            majorAngle = Self.unwrappedAngle(rawMajorAngle, nearest: nodeMajorAngle)
            minorAngle = lowerMinorAngle + curveParameter
        }
        return (
            SurfaceParameter(u: planeProjection.u, v: planeProjection.v),
            SurfaceParameter(u: majorAngle, v: minorAngle)
        )
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let radius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.torus.center.x - radius,
                y: configuration.torus.center.y - radius,
                z: configuration.torus.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.torus.center.x + radius,
                y: configuration.torus.center.y + radius,
                z: configuration.torus.center.z + radius
            )
        )
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Plane-torus full-branch differential bounds require a root-free full component."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let discriminant = configuration.discriminant
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 65_536.0
        ).nextUp
        let minimumDiscriminant = (
            discriminant.constant
                - abs(discriminant.cosine)
                - abs(discriminant.sine)
                - abs(discriminant.cosineDouble)
                - arithmeticEnvelope
        ).nextDown
        guard minimumDiscriminant > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A plane-torus full branch lacks a coefficient-separable positive discriminant margin."
            )
        }
        let rootLower = sqrt(minimumDiscriminant).nextDown
        guard rootLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A plane-torus full-branch square-root lower bound collapsed."
            )
        }
        let discriminantFirst =
            discriminant.firstDerivativeAbsoluteUpperBound
        let discriminantSecond =
            discriminant.secondDerivativeAbsoluteUpperBound
        let rootFirst = (
            discriminantFirst / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (
            minimumDiscriminant * rootLower
        ).nextDown
        let rootSecond = (
            discriminantSecond / (2.0 * rootLower).nextDown
                + discriminantFirst * discriminantFirst
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let inverseRadialNormalLength = (
            1.0 / configuration.radialNormalLength
        ).nextUp
        let axialDerivative = (
            configuration.torus.minorRadius
                * abs(configuration.axialNormal)
        ).nextUp
        let alongFirst = (
            axialDerivative * inverseRadialNormalLength
        ).nextUp
        let alongSecond = alongFirst
        let acrossFirst = (
            rootFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            rootSecond * inverseRadialNormalLength
        ).nextUp
        let heightDerivative = configuration.torus.minorRadius.nextUp
        let first = hypot(
            hypot(alongFirst, acrossFirst),
            heightDerivative
        ).nextUp
        let second = hypot(
            hypot(alongSecond, acrossSecond),
            heightDerivative
        ).nextUp
        guard first.isFinite, second.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Plane-torus full-branch differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second
        )
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        if upperFraction <= lowerFraction {
            // A span on a closed full branch can cross the periodic seam; its
            // differential bounds are the union of both seam-side sub-spans.
            switch componentKind {
            case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
                let head = try spatialDifferentialMagnitudeBounds(
                    fromNormalizedFraction: lowerFraction,
                    toNormalizedFraction: 1.0,
                    tolerance: tolerance
                )
                let tail = try spatialDifferentialMagnitudeBounds(
                    fromNormalizedFraction: 0.0,
                    toNormalizedFraction: upperFraction,
                    tolerance: tolerance
                )
                return SpatialDifferentialMagnitudeBounds(
                    first: max(head.first, tail.first),
                    second: max(head.second, tail.second)
                )
            case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
                throw GeometryError.invalidDistance(
                    upperFraction - lowerFraction
                )
            }
        }
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return try fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        case .boundedMinorAngle:
            return try boundedBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: max(lowerFraction, 0.0),
                toNormalizedFraction: min(upperFraction, 1.0),
                tolerance: tolerance
            )
        case .negativeInnerTangencyBranch,
             .positiveInnerTangencyBranch:
            return try innerTangencyBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        }
    }

    private func innerTangencyBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        guard componentKind == .negativeInnerTangencyBranch
                || componentKind == .positiveInnerTangencyBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Inner-tangency plane-torus differential bounds require a nodal branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        guard Self.innerTangencyCertificate(
            configuration: configuration,
            tolerance: tolerance
        ) != nil else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "An inner-tangency plane-torus branch lost its nodal certificate."
            )
        }
        let factor = Self.periodicDoubleRootFactor(
            configuration.discriminant,
            rootAngle: lowerMinorAngle
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne * factor.coefficientScale * 131_072.0
        ).nextUp
        let factorAmplitude = hypot(
            factor.cosine,
            factor.sine
        ).nextUp
        let factorLower = (
            factor.constant - factorAmplitude - arithmeticEnvelope
        ).nextDown
        let factorUpper = (
            factor.constant + factorAmplitude + arithmeticEnvelope
        ).nextUp
        guard factorLower > 0.0, factorUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "An inner-tangency plane-torus periodic factor lost its positive margin."
            )
        }
        let factorDerivative = (
            abs(factor.cosine) + abs(factor.sine)
        ).nextUp
        let rootLower = sqrt(factorLower).nextDown
        let rootUpper = sqrt(factorUpper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "An inner-tangency plane-torus factor square root collapsed."
            )
        }
        let rootFirst = (
            factorDerivative / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (
            factorLower * rootLower
        ).nextDown
        let rootSecond = (
            factorDerivative / (2.0 * rootLower).nextDown
                + factorDerivative * factorDerivative
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let distanceMagnitude = 2.0.nextUp
        let distanceFirst = 1.0.nextUp
        let distanceSecond = 0.5.nextUp
        let transverseFirst = (
            distanceFirst * rootUpper
                + distanceMagnitude * rootFirst
        ).nextUp
        let transverseSecond = (
            distanceSecond * rootUpper
                + 2.0 * distanceFirst * rootFirst
                + distanceMagnitude * rootSecond
        ).nextUp
        let inverseRadialNormalLength = (
            1.0 / configuration.radialNormalLength
        ).nextUp
        let axialScale = (
            configuration.torus.minorRadius
                * abs(configuration.axialNormal)
        ).nextUp
        let alongFirst = (
            axialScale * inverseRadialNormalLength
        ).nextUp
        let alongSecond = alongFirst
        let acrossFirst = (
            transverseFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            transverseSecond * inverseRadialNormalLength
        ).nextUp
        let heightFirst = configuration.torus.minorRadius.nextUp
        let heightSecond = heightFirst
        let first = hypot(
            hypot(alongFirst, acrossFirst),
            heightFirst
        ).nextUp
        let second = hypot(
            hypot(alongSecond, acrossSecond),
            heightSecond
        ).nextUp
        guard first.isFinite, second.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Inner-tangency plane-torus spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second
        )
    }

    private func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        guard componentKind == .boundedMinorAngle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded plane-torus differential bounds require a simple-root quartic component."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let discriminant = configuration.discriminant
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 131_072.0
        ).nextUp
        let phaseLower = 2.0 * Double.pi * lowerFraction
        let phaseUpper = 2.0 * Double.pi * upperFraction
        let minorRange = Self.boundedMinorAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerMinorAngle: lowerMinorAngle,
            upperMinorAngle: upperMinorAngle
        )
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerMinorAngle,
            componentUpper: upperMinorAngle,
            requestedLower: minorRange.lower,
            requestedUpper: minorRange.upper,
            lowerValue: discriminant.value(at: lowerMinorAngle),
            upperValue: discriminant.value(at: upperMinorAngle),
            lowerDerivative: discriminant.derivative(
                at: lowerMinorAngle
            ),
            upperDerivative: discriminant.derivative(
                at: upperMinorAngle
            ),
            firstDerivativeMagnitudeUpperBound:
                discriminant.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                discriminant.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                discriminant.thirdDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { lower, upper in
                Self.discriminantRange(
                    discriminant,
                    lower: lower,
                    upper: upper,
                    arithmeticEnvelope: arithmeticEnvelope
                )
            },
            tolerance: tolerance,
            label: "Plane-torus bounded branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded plane-torus regularized square-root factor lost its positive margin."
            )
        }
        let rootFirst = (
            factor.first / (2.0 * rootLower).nextDown
        ).nextUp
        let rootCubedLower = (
            factor.lower * rootLower
        ).nextDown
        let rootSecond = (
            factor.second / (2.0 * rootLower).nextDown
                + factor.first * factor.first
                    / (4.0 * rootCubedLower).nextDown
        ).nextUp
        let halfSpan = (
            (upperMinorAngle - lowerMinorAngle) * 0.5
        ).nextUp
        let sineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5
        )
        let cosineMagnitude = Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0
        )
        let minorFirst = (
            halfSpan * sineMagnitude
        ).nextUp
        let minorSecond = (
            halfSpan * cosineMagnitude
        ).nextUp
        let transverseFirst = (
            halfSpan * (
                cosineMagnitude * rootUpper
                    + sineMagnitude * rootFirst * minorFirst
            )
        ).nextUp
        let transverseSecond = (
            halfSpan * (
                sineMagnitude * rootUpper
                    + 2.0 * cosineMagnitude * rootFirst * minorFirst
                    + sineMagnitude * (
                        rootSecond * minorFirst * minorFirst
                            + rootFirst * minorSecond
                    )
            )
        ).nextUp
        let inverseRadialNormalLength = (
            1.0 / configuration.radialNormalLength
        ).nextUp
        let axialScale = (
            configuration.torus.minorRadius
                * abs(configuration.axialNormal)
        ).nextUp
        let alongFirst = (
            axialScale * minorFirst * inverseRadialNormalLength
        ).nextUp
        let alongSecond = (
            axialScale
                * (minorFirst * minorFirst + minorSecond)
                * inverseRadialNormalLength
        ).nextUp
        let acrossFirst = (
            transverseFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            transverseSecond * inverseRadialNormalLength
        ).nextUp
        let heightFirst = (
            configuration.torus.minorRadius * minorFirst
        ).nextUp
        let heightSecond = (
            configuration.torus.minorRadius
                * (minorFirst * minorFirst + minorSecond)
        ).nextUp
        let first = hypot(
            hypot(alongFirst, acrossFirst),
            heightFirst
        ).nextUp
        let second = hypot(
            hypot(alongSecond, acrossSecond),
            heightSecond
        ).nextUp
        guard first.isFinite, second.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Bounded plane-torus spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second
        )
    }

    private func minorAngleDifferential(at parameter: Double) -> ScalarDifferential {
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return ScalarDifferential(
                value: parameter,
                first: 1.0,
                second: 0.0
            )
        case .boundedMinorAngle:
            let midpoint = lowerMinorAngle
                + (upperMinorAngle - lowerMinorAngle) * 0.5
            let halfSpan = (upperMinorAngle - lowerMinorAngle) * 0.5
            return ScalarDifferential(
                value: midpoint - halfSpan * cos(parameter),
                first: halfSpan * sin(parameter),
                second: halfSpan * cos(parameter)
            )
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            return ScalarDifferential(
                value: lowerMinorAngle + parameter,
                first: 1.0,
                second: 0.0
            )
        }
    }

    private func signedSquareRootDifferential(
        value: Double,
        first: Double,
        second: Double,
        minorAngle: Double,
        parameter: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let branchSign: Double
        switch componentKind {
        case .negativeFullBranch, .negativeInnerTangencyBranch:
            branchSign = -1.0
        case .positiveFullBranch, .positiveInnerTangencyBranch:
            branchSign = 1.0
        case .boundedMinorAngle:
            branchSign = sin(parameter) < 0.0 ? -1.0 : 1.0
        }
        if componentKind == .boundedMinorAngle {
            let factor = try regularizedDiscriminantFactorDifferential(
                at: minorAngle,
                configuration: configuration,
                tolerance: tolerance
            )
            guard factor.value > 0.0, factor.value.isFinite else {
                throw Self.singularSection(
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "A bounded plane-torus component lost its positive regularized discriminant factor."
                )
            }
            let root = sqrt(factor.value)
            let rootByMinor = ScalarDifferential(
                value: root,
                first: factor.first / (2.0 * root),
                second: factor.second / (2.0 * root)
                    - factor.first * factor.first
                        / (4.0 * root * root * root)
            )
            let minor = minorAngleDifferential(at: parameter)
            let rootByParameter = ScalarDifferential(
                value: rootByMinor.value,
                first: rootByMinor.first * minor.first,
                second: rootByMinor.second * minor.first * minor.first
                    + rootByMinor.first * minor.second
            )
            let sine = ScalarDifferential(
                value: sin(parameter),
                first: cos(parameter),
                second: -sin(parameter)
            )
            let result = Self.product(
                sine,
                rootByParameter
            ).scaled(
                by: (upperMinorAngle - lowerMinorAngle) * 0.5
            )
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded plane-torus regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        if componentKind == .negativeInnerTangencyBranch
            || componentKind == .positiveInnerTangencyBranch {
            let factorPolynomial = Self.periodicDoubleRootFactor(
                configuration.discriminant,
                rootAngle: lowerMinorAngle
            )
            let factor = ScalarDifferential(
                value: factorPolynomial.value(at: parameter),
                first: factorPolynomial.derivative(at: parameter),
                second: factorPolynomial.secondDerivative(at: parameter)
            )
            guard factor.value > 0.0, factor.value.isFinite else {
                throw Self.singularSection(
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "An inner-tangent plane-torus branch lost its positive periodic factor."
                )
            }
            let root = sqrt(factor.value)
            let rootDifferential = ScalarDifferential(
                value: root,
                first: factor.first / (2.0 * root),
                second: factor.second / (2.0 * root)
                    - factor.first * factor.first
                        / (4.0 * root * root * root)
            )
            let halfParameter = parameter * 0.5
            let periodicDistance = ScalarDifferential(
                value: 2.0 * sin(halfParameter),
                first: cos(halfParameter),
                second: -0.5 * sin(halfParameter)
            )
            let result = Self.product(
                periodicDistance,
                rootDifferential
            ).scaled(by: branchSign)
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "An inner-tangent plane-torus periodic square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        guard value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -value,
                tolerance: tolerance,
                message: "A plane-torus evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw Self.singularSection(
                residual: magnitude,
                tolerance: tolerance,
                message: "A plane-torus square-root differential is singular."
            )
        }
        let signedValue = branchSign * magnitude
        return ScalarDifferential(
            value: signedValue,
            first: first / (2.0 * signedValue),
            second: second / (2.0 * signedValue)
                - first * first / (4.0 * signedValue * signedValue * signedValue)
        )
    }

    private func regularizedDiscriminantFactorDifferential(
        at minorAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let span = upperMinorAngle - lowerMinorAngle
        let lowerDistance = minorAngle - lowerMinorAngle
        let upperDistance = upperMinorAngle - minorAngle
        guard span > tolerance.angle,
              lowerDistance >= -tolerance.angle,
              upperDistance >= -tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: min(lowerDistance, upperDistance),
                tolerance: tolerance,
                message: "A bounded plane-torus regularized factor was evaluated outside its certified minor-angle component."
            )
        }
        let discriminant = configuration.discriminant
        let lowerValue = discriminant.value(at: lowerMinorAngle)
        let upperValue = discriminant.value(at: upperMinorAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint
            ? lowerMinorAngle
            : upperMinorAngle
        let dividedDifference = Self.trigonometricDividedDifference(
            discriminant,
            value: minorAngle,
            endpoint: endpoint
        )
        let numerator = usesLowerEndpoint
            ? dividedDifference.adding(.constant(-correctionSlope))
            : ScalarDifferential.constant(correctionSlope)
                .subtracting(dividedDifference)
        let denominator = usesLowerEndpoint
            ? ScalarDifferential(
                value: upperMinorAngle - minorAngle,
                first: -1.0,
                second: 0.0
            )
            : ScalarDifferential(
                value: minorAngle - lowerMinorAngle,
                first: 1.0,
                second: 0.0
            )
        return try Self.quotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded plane-torus regularized factor lost its opposite-endpoint denominator."
        )
    }

    private static func periodicDoubleRootFactor(
        _ polynomial: TrigonometricPolynomial,
        rootAngle: Double
    ) -> TrigonometricPolynomial {
        let firstCosine = polynomial.cosine * cos(rootAngle)
            + polynomial.sine * sin(rootAngle)
        let secondCosine = polynomial.cosineDouble
            * cos(2.0 * rootAngle)
        let secondSine = -polynomial.cosineDouble
            * sin(2.0 * rootAngle)
        return TrigonometricPolynomial(
            constant: -0.5 * firstCosine - secondCosine,
            cosine: -secondCosine,
            sine: -secondSine,
            cosineDouble: 0.0
        )
    }

    private static func trigonometricDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ) -> ScalarDifferential {
        var result = ScalarDifferential.constant(0.0)
        for harmonic in [
            (order: 1.0, cosine: polynomial.cosine, sine: polynomial.sine),
            (order: 2.0, cosine: polynomial.cosineDouble, sine: 0.0),
        ] {
            let halfOrder = harmonic.order * 0.5
            let difference = value - endpoint
            let midpoint = (value + endpoint) * halfOrder
            let sinc = sincDifferential(
                at: difference * halfOrder,
                derivativeScale: halfOrder
            )
            let amplitude = ScalarDifferential(
                value: -harmonic.cosine * sin(midpoint)
                    + harmonic.sine * cos(midpoint),
                first: halfOrder * (
                    -harmonic.cosine * cos(midpoint)
                        - harmonic.sine * sin(midpoint)
                ),
                second: -halfOrder * halfOrder * (
                    -harmonic.cosine * sin(midpoint)
                        + harmonic.sine * cos(midpoint)
                )
            )
            result = result.adding(
                product(sinc, amplitude).scaled(by: harmonic.order)
            )
        }
        return result
    }

    private static func sincDifferential(
        at value: Double,
        derivativeScale: Double
    ) -> ScalarDifferential {
        let valueResult: Double
        let firstByValue: Double
        let secondByValue: Double
        if abs(value) <= 0.25 {
            var accumulatedValue = 0.0
            var accumulatedFirst = 0.0
            var accumulatedSecond = 0.0
            var coefficient = 1.0
            for index in 0...12 {
                let exponent = index * 2
                accumulatedValue += coefficient
                    * pow(value, Double(exponent))
                if exponent > 0 {
                    accumulatedFirst += coefficient * Double(exponent)
                        * pow(value, Double(exponent - 1))
                }
                if exponent > 1 {
                    accumulatedSecond += coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(value, Double(exponent - 2))
                }
                coefficient /= -Double(
                    (2 * index + 2) * (2 * index + 3)
                )
            }
            valueResult = accumulatedValue
            firstByValue = accumulatedFirst
            secondByValue = accumulatedSecond
        } else {
            let sine = sin(value)
            let cosine = cos(value)
            let squared = value * value
            valueResult = sine / value
            firstByValue = (value * cosine - sine) / squared
            secondByValue = -sine / value
                - 2.0 * cosine / squared
                + 2.0 * sine / (squared * value)
        }
        return ScalarDifferential(
            value: valueResult,
            first: firstByValue * derivativeScale,
            second: secondByValue * derivativeScale * derivativeScale
        )
    }

    private static func product(
        _ first: ScalarDifferential,
        _ second: ScalarDifferential
    ) -> ScalarDifferential {
        ScalarDifferential(
            value: first.value * second.value,
            first: first.first * second.value
                + first.value * second.first,
            second: first.second * second.value
                + 2.0 * first.first * second.first
                + first.value * second.second
        )
    }

    private static func quotient(
        _ numerator: ScalarDifferential,
        _ denominator: ScalarDifferential,
        tolerance: ModelingTolerance,
        message: String
    ) throws -> ScalarDifferential {
        guard abs(denominator.value) > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator.value),
                tolerance: tolerance,
                message: message
            )
        }
        let inverse = 1.0 / denominator.value
        let inverseFirst = -denominator.first * inverse * inverse
        let inverseSecond = 2.0 * denominator.first * denominator.first
                * inverse * inverse * inverse
            - denominator.second * inverse * inverse
        return product(
            numerator,
            ScalarDifferential(
                value: inverse,
                first: inverseFirst,
                second: inverseSecond
            )
        )
    }

    private static func makeConfiguration(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try planeSurface.validate(tolerance: tolerance)
        try torusSurface.validate(tolerance: tolerance)
        guard case let .plane(plane) = CanonicalAnalyticSurface(planeSurface),
              case let .torus(torus) = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified plane-torus curve requires one exact plane and one exact torus."
            )
        }
        let axisProjection = plane.normal.dot(torus.axis)
        let projectedNormal = plane.normal - torus.axis * axisProjection
        let radialNormalLength = projectedNormal.length
        guard radialNormalLength > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: radialNormalLength,
                tolerance: tolerance,
                message: "Axial plane-torus sections must use their closed-form circle representation."
            )
        }
        let radialNormal = try projectedNormal.normalized(
            tolerance: tolerance.distance
        )
        let radialPerpendicular = try torus.axis.cross(radialNormal).normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(torus.axis, tolerance: tolerance)
        let centerDistance = (torus.center - plane.origin).dot(plane.normal)
        let radialSquared = radialNormalLength * radialNormalLength
        let axialSquared = axisProjection * axisProjection
        let minorSquared = torus.minorRadius * torus.minorRadius
        let discriminant = TrigonometricPolynomial(
            constant: radialSquared * (
                torus.majorRadius * torus.majorRadius + minorSquared * 0.5
            ) - centerDistance * centerDistance - axialSquared * minorSquared * 0.5,
            cosine: 2.0 * radialSquared * torus.majorRadius * torus.minorRadius,
            sine: -2.0 * centerDistance * torus.minorRadius * axisProjection,
            cosineDouble: minorSquared * (radialSquared + axialSquared) * 0.5
        )
        return Configuration(
            plane: plane,
            torus: torus,
            torusBasisU: basis.u,
            torusBasisV: basis.v,
            radialNormal: radialNormal,
            radialPerpendicular: radialPerpendicular,
            radialNormalLength: radialNormalLength,
            axialNormal: axisProjection,
            centerDistance: centerDistance,
            discriminant: discriminant
        )
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
    }

    private static func innerTangencyCertificate(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> InnerTangencyCertificate? {
        let radialSupport = configuration.torus.majorRadius
            * configuration.radialNormalLength
        let innerSupport = radialSupport - configuration.torus.minorRadius
        guard innerSupport > tolerance.distance else { return nil }

        let arithmeticLengthTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 32_768.0
        let offsetResidual = abs(abs(configuration.centerDistance) - innerSupport)
        guard offsetResidual <= arithmeticLengthTolerance else { return nil }

        let centerSign = configuration.centerDistance >= 0.0 ? 1.0 : -1.0
        let minorAngle = normalizedAngle(atan2(
            centerSign * configuration.axialNormal,
            -configuration.radialNormalLength
        ))
        let valueResidual = abs(configuration.discriminant.value(at: minorAngle))
        let derivativeResidual = abs(configuration.discriminant.derivative(at: minorAngle))
        let arithmeticSquaredTolerance = Double.ulpOfOne
            * pow(configuration.characteristicLength, 2.0) * 131_072.0
        let secondDerivative = configuration.discriminant.secondDerivative(at: minorAngle)
        guard valueResidual <= arithmeticSquaredTolerance,
              derivativeResidual <= arithmeticSquaredTolerance,
              secondDerivative > arithmeticSquaredTolerance else {
            return nil
        }

        let radialScale = configuration.torus.majorRadius
            + configuration.torus.minorRadius * cos(minorAngle)
        let axialTerm = configuration.centerDistance
            + configuration.torus.minorRadius
                * configuration.axialNormal * sin(minorAngle)
        let nodeRadialLength = abs(axialTerm) / configuration.radialNormalLength
        let contactResidual = abs(nodeRadialLength - radialScale)
        guard contactResidual <= tolerance.distance else { return nil }
        return InnerTangencyCertificate(
            minorAngle: minorAngle,
            contactResidualUpperBound: contactResidual
        )
    }

    private static func boundaryAngles(
        configuration: Configuration,
        classificationTolerance: Double,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let polynomial = configuration.discriminant
        if polynomial.globalLowerBound > classificationTolerance {
            return []
        }
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.25,
                Double.ulpOfOne * 1_024.0
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: min(
                max(options.maximumIterations * 8, 128),
                2_048
            ),
            tolerance: tolerance
        )
        let tangentRoots = try solver.roots(
            coefficients: polynomial.tangentHalfAngleCoefficients
        )
        guard tangentRoots.count <= options.maximumSeedCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Plane-torus section exceeded its quartic boundary-root limit."
            )
        }
        var values = tangentRoots.map {
            normalizedAngle(2.0 * atan($0.value))
        }
        if abs(polynomial.value(at: Double.pi)) <= classificationTolerance {
            values.append(Double.pi)
        }
        values = values.map {
            refinedAngle(
                $0,
                polynomial: polynomial,
                maximumIterations: options.maximumIterations,
                residualTolerance: classificationTolerance * 1.0e-8,
                tolerance: tolerance
            )
        }.filter {
            abs(polynomial.value(at: $0)) <= classificationTolerance * 16.0
        }.sorted()

        var result: [Double] = []
        for value in values where result.last.map({
            angularDistance($0, value) <= tolerance.angle
        }) != true {
            result.append(value)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           angularDistance(first, last) <= tolerance.angle {
            result.removeLast()
        }
        let derivativeThreshold = max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
        for angle in result {
            let derivative = abs(polynomial.derivative(at: angle))
            guard derivative > derivativeThreshold else {
                throw singularSection(
                    residual: derivative,
                    tolerance: tolerance,
                    message: "Plane-torus section contains a singular or tangent quartic boundary."
                )
            }
        }
        return result
    }

    private static func validIntervals(
        boundaries: [Double],
        configuration: Configuration,
        classificationTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [(lower: Double, upper: Double)] {
        let period = 2.0 * Double.pi
        var result: [(lower: Double, upper: Double)] = []
        for index in boundaries.indices {
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + period
            let midpoint = lower + (upper - lower) * 0.5
            let value = configuration.discriminant.value(at: midpoint)
            if value > classificationTolerance {
                result.append((lower, upper))
            } else if abs(value) <= classificationTolerance {
                throw singularSection(
                    residual: abs(value),
                    tolerance: tolerance,
                    message: "Plane-torus quartic interval could not be classified away from zero."
                )
            }
        }
        return result
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerMinorAngle: Double,
        upperMinorAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 65_536.0
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return machineBound
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard let certificate = innerTangencyCertificate(
                configuration: configuration,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An inner-tangent plane-torus branch lost its nodal certificate."
                )
            }
            let result = certificate.contactResidualUpperBound + machineBound
            guard result <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result,
                    tolerance: tolerance,
                    message: "An inner-tangent plane-torus node exceeds the requested tolerance."
                )
            }
            return result
        case .boundedMinorAngle:
            break
        }
        let rootResidual = max(
            abs(configuration.discriminant.value(at: lowerMinorAngle)),
            abs(configuration.discriminant.value(at: upperMinorAngle))
        )
        let denominator = pow(configuration.radialNormalLength, 2.0)
            * max(configuration.minimumRadialScale, tolerance.distance)
        let rootGeometryBound = rootResidual / denominator
        let result = rootGeometryBound + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Plane-torus quartic roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }

    private static func refinedAngle(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        maximumIterations: Int,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let effectiveResidual = max(
            residualTolerance,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<maximumIterations {
            let value = polynomial.value(at: angle)
            if abs(value) <= effectiveResidual { break }
            let derivative = polynomial.derivative(at: angle)
            guard abs(derivative) > tolerance.angle * polynomial.coefficientScale else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
    }

    private static func boundedMinorAngleRange(
        phaseLower: Double,
        phaseUpper: Double,
        lowerMinorAngle: Double,
        upperMinorAngle: Double
    ) -> (lower: Double, upper: Double) {
        let midpoint = lowerMinorAngle
            + (upperMinorAngle - lowerMinorAngle) * 0.5
        let halfSpan = (upperMinorAngle - lowerMinorAngle) * 0.5
        var values = [
            midpoint - halfSpan * cos(phaseLower),
            midpoint - halfSpan * cos(phaseUpper),
        ]
        for index in 0...2 {
            let phase = Double(index) * Double.pi
            if phase > phaseLower, phase < phaseUpper {
                values.append(midpoint - halfSpan * cos(phase))
            }
        }
        return (
            (values.min() ?? lowerMinorAngle).nextDown,
            (values.max() ?? upperMinorAngle).nextUp
        )
    }

    private static func discriminantRange(
        _ discriminant: TrigonometricPolynomial,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double
    ) -> (lower: Double, upper: Double) {
        let midpoint = lower + (upper - lower) * 0.5
        let radius = (
            discriminant.firstDerivativeAbsoluteUpperBound
                * (upper - lower) * 0.5
                + arithmeticEnvelope
        ).nextUp
        let value = discriminant.value(at: midpoint)
        return (
            (value - radius).nextDown,
            (value + radius).nextUp
        )
    }

    private static func maximumAbsoluteTrigonometricValue(
        lower: Double,
        upper: Double,
        phase: Double
    ) -> Double {
        var result = max(
            abs(cos(lower - phase)),
            abs(cos(upper - phase))
        )
        for index in -2...4 {
            let extremum = phase + Double(index) * Double.pi
            if extremum > lower, extremum < upper {
                result = 1.0
                break
            }
        }
        return result.nextUp
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private static func unwrappedAngle(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + round((reference - angle) / period) * period
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        let period = 2.0 * Double.pi
        let difference = abs(first - second).truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
    }

    private static func singularSection(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularSystem,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private static func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }

    private enum CodingKeys: String, CodingKey {
        case planeSurface
        case torusSurface
        case componentKind
        case lowerMinorAngle
        case upperMinorAngle
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .planeSurface,
                .torusSurface,
                .componentKind,
                .lowerMinorAngle,
                .upperMinorAngle,
                .certificationTolerance,
            ],
            in: decoder
        )
        try self.init(
            planeSurface: container.decode(Surface3D.self, forKey: .planeSurface),
            torusSurface: container.decode(Surface3D.self, forKey: .torusSurface),
            componentKind: container.decode(ComponentKind.self, forKey: .componentKind),
            lowerMinorAngle: container.decode(Double.self, forKey: .lowerMinorAngle),
            upperMinorAngle: container.decode(Double.self, forKey: .upperMinorAngle),
            tolerance: container.decode(
                ModelingTolerance.self,
                forKey: .certificationTolerance
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planeSurface, forKey: .planeSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerMinorAngle, forKey: .lowerMinorAngle)
        try container.encode(upperMinorAngle, forKey: .upperMinorAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
