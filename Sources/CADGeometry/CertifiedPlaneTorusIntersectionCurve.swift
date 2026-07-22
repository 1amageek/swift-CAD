import CADCore
import Foundation

public struct CertifiedPlaneTorusIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedMinorAngle
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
    }

    public let planeSurface: Surface3D
    public let torusSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerMinorAngle: Double
    public let upperMinorAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public var parameterDomain: CurveParameterDomain {
        .periodic(period: 2.0 * Double.pi)
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
        let certifiedBoundaries = try Self.boundaryAngles(
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        )
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
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
        for parameter in [0.0, Double.pi * 0.5, Double.pi, Double.pi * 1.5] {
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
        let angle = Self.normalizedAngle(parameter)
        let minor = minorAngleDifferential(at: angle)
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
            parameter: angle,
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
        let offset = point - configuration.torus.center
        let height = offset.dot(configuration.torus.axis)
        let radial = offset - configuration.torus.axis * height
        let majorAngle = Self.normalizedAngle(atan2(
            radial.dot(configuration.torusBasisV),
            radial.dot(configuration.torusBasisU)
        ))
        let minorAngle = Self.normalizedAngle(atan2(
            height,
            radial.length - configuration.torus.majorRadius
        ))
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
        case .negativeFullBranch:
            branchSign = -1.0
        case .positiveFullBranch:
            branchSign = 1.0
        case .boundedMinorAngle:
            branchSign = sin(parameter) < 0.0 ? -1.0 : 1.0
        }
        if componentKind == .boundedMinorAngle,
           abs(sin(parameter)) <= max(tolerance.angle, Double.ulpOfOne * 256.0),
           abs(value) <= classificationTolerance * 32.0 {
            let radialScale = configuration.torus.majorRadius
                + configuration.torus.minorRadius * cos(minorAngle)
            let radialScaleDerivative = -configuration.torus.minorRadius
                * sin(minorAngle)
            let axialTerm = configuration.centerDistance
                + configuration.torus.minorRadius
                    * configuration.axialNormal * sin(minorAngle)
            let axialTermDerivative = configuration.torus.minorRadius
                * configuration.axialNormal * cos(minorAngle)
            let derivativeByMinorAngle = 2.0
                * pow(configuration.radialNormalLength, 2.0)
                * radialScale * radialScaleDerivative
                - 2.0 * axialTerm * axialTermDerivative
            let halfSpan = (upperMinorAngle - lowerMinorAngle) * 0.5
            let isUpper = cos(parameter) < 0.0
            let squaredSlope = (isUpper ? -1.0 : 1.0)
                * derivativeByMinorAngle * halfSpan * 0.5
            guard squaredSlope > 0.0 else {
                throw Self.singularSection(
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A plane-torus quartic endpoint has no regular square-root continuation."
                )
            }
            return ScalarDifferential(
                value: 0.0,
                first: (isUpper ? -1.0 : 1.0) * sqrt(squaredSlope),
                second: 0.0
            )
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

    private static func boundaryAngles(
        configuration: Configuration,
        classificationTolerance: Double,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let polynomial = configuration.discriminant
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
        guard componentKind == .boundedMinorAngle else {
            return machineBound
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

    private static func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
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
