import CADCore
import Foundation

public struct CertifiedGeneralConeTorusIntersectionCurve: Codable, Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public typealias ApexReduction =
        CertifiedConeTorusApexIntersectionCurve

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
        let centerDirection: Vector3D
        let radialU: Vector3D
        let radialV: Vector3D

        func direction(at angle: Double) -> Vector3D {
            centerDirection
                + radialU * cos(angle)
                + radialV * sin(angle)
        }

        func directionFirstDerivative(at angle: Double) -> Vector3D {
            radialU * -sin(angle) + radialV * cos(angle)
        }

        func directionSecondDerivative(at angle: Double) -> Vector3D {
            radialU * -cos(angle) + radialV * -sin(angle)
        }
    }

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct Configuration {
        let cone: Cone
        let torus: Torus
        let lowerSlant: Double
        let upperSlant: Double
        let characteristicLength: Double

        func generatorPoint(angle: Double, slant: Double) -> Point3D {
            cone.apex + cone.direction(at: angle) * slant
        }

        func coefficients(at angle: Double) -> [Double] {
            let offset = cone.apex - torus.center
            let direction = cone.direction(at: angle)
            let pointSquared = offset.dot(offset)
            let pointDirection = offset.dot(direction)
            let axialPoint = offset.dot(torus.axis)
            let axialDirection = direction.dot(torus.axis)
            let q0 = pointSquared
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            let q1 = 2.0 * pointDirection
            let radial0 = pointSquared - axialPoint * axialPoint
            let radial1 = 2.0 * (
                pointDirection - axialPoint * axialDirection
            )
            let radial2 = 1.0 - axialDirection * axialDirection
            let majorFactor = 4.0 * torus.majorRadius * torus.majorRadius
            return [
                q0 * q0 - majorFactor * radial0,
                2.0 * q0 * q1 - majorFactor * radial1,
                q1 * q1 + 2.0 * q0 - majorFactor * radial2,
                2.0 * q1,
                1.0,
            ]
        }
    }

    private struct Certificate: Hashable, Sendable {
        let branchCount: Int
        let processedCellCount: Int
    }

    private struct Cell {
        let angle: Interval
        let slant: Interval
        let depth: Int
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
    }

    public let coneSurface: Surface3D
    public let torusSurface: Surface3D
    public let branchIndex: Int
    public let branchCount: Int
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    public let apexReduction: ApexReduction?
    private let certificate: Certificate

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int = 24,
        maximumCellCount: Int = 65_536,
        tolerance: ModelingTolerance
    ) throws {
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let certificate = try Self.makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        try self.init(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            branchIndex: branchIndex,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance,
            configuration: configuration,
            certificate: certificate
        )
    }

    public init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        branchCount: Int,
        apexReduction: ApexReduction,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.branchIndex = branchIndex
        self.branchCount = branchCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        self.apexReduction = apexReduction
        certificate = Certificate(
            branchCount: branchCount,
            processedCellCount: branchCount
        )
        try validate(tolerance: tolerance)
    }

    private init(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance,
        configuration: Configuration,
        certificate: Certificate
    ) throws {
        self.coneSurface = coneSurface
        self.torusSurface = torusSurface
        self.branchIndex = branchIndex
        branchCount = certificate.branchCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
        certificationTolerance = tolerance
        maximumResidualUpperBound = try Self.residualUpperBound(
            configuration: configuration,
            tolerance: tolerance
        )
        apexReduction = nil
        self.certificate = certificate
        try validate(tolerance: tolerance)
    }

    static func certifiedCurves(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedGeneralConeTorusIntersectionCurve] {
        try options.validate(tolerance: tolerance)
        let maximumSubdivisionDepth = min(
            options.maximumSubdivisionDepth + 12,
            24
        )
        let maximumCellCount = min(
            max(options.maximumSeedCount * 64, 16_384),
            65_536
        )
        let configuration = try makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let certificate = try makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        return try (0..<certificate.branchCount).map { branchIndex in
            try CertifiedGeneralConeTorusIntersectionCurve(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
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
                message: "A general cone-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        if let apexReduction {
            try Self.validate(
                apexReduction: apexReduction,
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                tolerance: tolerance
            )
        } else {
            _ = try Self.makeConfiguration(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                tolerance: tolerance
            )
        }
        guard maximumSubdivisionDepth > 0,
              maximumSubdivisionDepth <= 24,
              maximumCellCount > 0,
              maximumCellCount <= 65_536,
              branchCount > 0,
              branchIndex >= 0,
              branchIndex < branchCount,
              certificate.branchCount == branchCount,
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
                message: "A general cone-torus branch has an invalid stored completeness certificate."
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
        if let apexReduction {
            let geometry = try apexReduction.differential(
                atNormalizedFraction: min(max(fraction, 0.0), 1.0),
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
        let clamped = min(max(fraction, 0.0), 1.0)
        let angle = clamped == 1.0 ? 0.0 : 2.0 * Double.pi * clamped
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        )
        let roots = try Self.certifiedRoots(
            angle: angle,
            configuration: configuration,
            tolerance: tolerance
        )
        guard roots.count == branchCount else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(abs(roots.count - branchCount)),
                tolerance: tolerance,
                message: "A certified cone-torus branch changed generator root count during evaluation."
            )
        }
        let slant = roots[branchIndex].value
        guard abs(slant) > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(slant),
                tolerance: tolerance,
                message: "A certified cone-torus branch reaches the cone apex."
            )
        }
        let direction = configuration.cone.direction(at: angle)
        let directionFirst = configuration.cone.directionFirstDerivative(at: angle)
        let directionSecond = configuration.cone.directionSecondDerivative(at: angle)
        let position = configuration.cone.apex + direction * slant
        let angleTangent = directionFirst * slant
        let angleSecond = directionSecond * slant
        let offset = position - configuration.torus.center
        let gradient = Self.torusGradient(
            offset: offset,
            torus: configuration.torus
        )
        let slantDenominator = gradient.dot(direction)
        let derivativeThreshold = Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        )
        guard slantDenominator.isFinite,
              abs(slantDenominator) > derivativeThreshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(slantDenominator),
                tolerance: tolerance,
                message: "A certified cone-torus branch reached a generator-tangent root."
            )
        }
        let angleImplicit = gradient.dot(angleTangent)
        let slantAngleDerivative = -angleImplicit / slantDenominator
        let angleAngleImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: angleTangent,
            torus: configuration.torus
        ) + gradient.dot(angleSecond)
        let angleSlantImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: direction,
            torus: configuration.torus
        ) + gradient.dot(directionFirst)
        let slantSlantImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: direction,
            second: direction,
            torus: configuration.torus
        )
        let slantAngleSecondDerivative = -(
            angleAngleImplicit
                + 2.0 * angleSlantImplicit * slantAngleDerivative
                + slantSlantImplicit
                    * slantAngleDerivative * slantAngleDerivative
        ) / slantDenominator
        let angularScale = 2.0 * Double.pi
        let firstDerivative = (
            angleTangent + direction * slantAngleDerivative
        ) * angularScale
        let secondDerivative = (
            angleSecond
                + directionFirst * (2.0 * slantAngleDerivative)
                + direction * slantAngleSecondDerivative
        ) * (angularScale * angularScale)
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-torus component has a singular differential."
            )
        }
        let coneProjection = try coneSurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let torusProjection = try torusSurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let residual = max(coneProjection.residual, torusProjection.residual)
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified cone-torus root exceeded its geometric residual bound."
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
        guard surface == coneSurface || surface == torusSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general cone-torus pcurve was requested on an unrelated surface."
            )
        }
        if let apexReduction {
            return try apexReduction.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
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
        if let apexReduction {
            return try apexReduction.boundingBox(
                tolerance: tolerance
            )
        }
        let configuration = try Self.makeConfiguration(
            coneSurface: coneSurface,
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

    private static func makeConfiguration(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try coneSurface.validate(tolerance: tolerance)
        try torusSurface.validate(tolerance: tolerance)
        guard case let .cone(sourceCone) = CanonicalAnalyticSurface(coneSurface),
              case let .torus(sourceTorus) = CanonicalAnalyticSurface(
                torusSurface
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified general cone-torus curve requires one exact cone and one exact torus."
            )
        }
        var coneAxis = try sourceCone.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(coneAxis) { coneAxis = -coneAxis }
        var torusAxis = try sourceTorus.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(torusAxis) { torusAxis = -torusAxis }
        let axesAreParallel = AnalyticAxisRelation.areParallel(
            coneAxis,
            torusAxis,
            tolerance: tolerance
        )
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: sourceTorus.center,
            axis: torusAxis,
            to: sourceCone.apex
        )
        guard axesAreParallel == false || radialOffset.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general cone-torus curve requires non-coaxial source surfaces."
            )
        }
        let basis = try analyticOrthonormalBasis(coneAxis, tolerance: tolerance)
        let sine = sin(sourceCone.halfAngle)
        let cone = Cone(
            apex: sourceCone.apex,
            axis: coneAxis,
            halfAngle: sourceCone.halfAngle,
            centerDirection: coneAxis * cos(sourceCone.halfAngle),
            radialU: basis.u * sine,
            radialV: basis.v * sine
        )
        let torus = Torus(
            center: sourceTorus.center,
            axis: torusAxis,
            majorRadius: sourceTorus.majorRadius,
            minorRadius: sourceTorus.minorRadius
        )
        try rejectApexContact(cone: cone, torus: torus, tolerance: tolerance)
        let outerRadius = sourceTorus.majorRadius + sourceTorus.minorRadius
        let slantBound = (sourceTorus.center - sourceCone.apex).length
            + outerRadius
            + tolerance.distance * 16.0
        return Configuration(
            cone: cone,
            torus: torus,
            lowerSlant: -slantBound,
            upperSlant: slantBound,
            characteristicLength: max(
                outerRadius,
                (sourceTorus.center - sourceCone.apex).length,
                1.0
            )
        )
    }

    private static func validate(
        apexReduction: ApexReduction,
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try apexReduction.validate(tolerance: tolerance)
        guard apexReduction.coneSurface == coneSurface,
              apexReduction.torusSurface == torusSurface,
              case let .cone(cone) = CanonicalAnalyticSurface(coneSurface),
              case .torus = CanonicalAnalyticSurface(torusSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus rational reduction changed its analytic source surfaces."
            )
        }
        let apexProjection = try torusSurface.parameterProjection(
            of: cone.apex,
            tolerance: tolerance
        )
        guard apexProjection.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: apexProjection.residual,
                tolerance: tolerance,
                message: "A cone-torus apex reduction requires the cone apex on the torus."
            )
        }
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
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "General cone-torus certification limits are outside the supported resource envelope."
            )
        }
        var cells = [Cell(
            angle: Interval(0.0, 2.0 * Double.pi),
            slant: Interval(configuration.lowerSlant, configuration.upperSlant),
            depth: 0
        )]
        var processedCellCount = 0
        while let cell = cells.popLast() {
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCellCount),
                    tolerance: tolerance,
                    message: "Cone-torus generator tangency certification exceeded its cell limit."
                )
            }
            let values = implicitIntervals(
                angle: cell.angle,
                slant: cell.slant,
                configuration: configuration
            )
            if values.implicit.containsZero == false
                || values.slantDerivative.containsZero == false {
                continue
            }
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(cell.angle.width, cell.slant.width),
                    tolerance: tolerance,
                    message: "General cone-torus subdivision exhausted its budget before certifying root simplicity."
                )
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedSlantWidth = cell.slant.width
                / (configuration.upperSlant - configuration.lowerSlant)
            if normalizedAngleWidth >= normalizedSlantWidth {
                let middle = cell.angle.midpoint
                cells.append(Cell(
                    angle: Interval(middle, cell.angle.upper),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: Interval(cell.angle.lower, middle),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ))
            } else {
                let middle = cell.slant.midpoint
                cells.append(Cell(
                    angle: cell.angle,
                    slant: Interval(middle, cell.slant.upper),
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: cell.angle,
                    slant: Interval(cell.slant.lower, middle),
                    depth: cell.depth + 1
                ))
            }
        }
        let initialRoots = try certifiedRoots(
            angle: 0.0,
            configuration: configuration,
            tolerance: tolerance
        )
        return Certificate(
            branchCount: initialRoots.count,
            processedCellCount: processedCellCount
        )
    }

    private static func implicitIntervals(
        angle: Interval,
        slant: Interval,
        configuration: Configuration
    ) -> (implicit: Interval, slantDerivative: Interval) {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let direction = [
            directionInterval(
                center: configuration.cone.centerDirection.x,
                radialU: configuration.cone.radialU.x,
                radialV: configuration.cone.radialV.x,
                cosine: cosine,
                sine: sine
            ),
            directionInterval(
                center: configuration.cone.centerDirection.y,
                radialU: configuration.cone.radialU.y,
                radialV: configuration.cone.radialV.y,
                cosine: cosine,
                sine: sine
            ),
            directionInterval(
                center: configuration.cone.centerDirection.z,
                radialU: configuration.cone.radialU.z,
                radialV: configuration.cone.radialV.z,
                cosine: cosine,
                sine: sine
            ),
        ]
        let centerOffset = configuration.cone.apex - configuration.torus.center
        let base = [centerOffset.x, centerOffset.y, centerOffset.z]
        let coordinates = direction.indices.map { index in
            Interval.constant(base[index]).adding(
                direction[index].multiplied(by: slant)
            )
        }
        let squaredLength = coordinates.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(coordinates, configuration.torus.axis)
        let generatorCoordinate = dotInterval(coordinates, direction)
        let axialDirection = dotInterval(direction, configuration.torus.axis)
        let radiusDifference = configuration.torus.majorRadius
            * configuration.torus.majorRadius
            - configuration.torus.minorRadius
                * configuration.torus.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.torus.majorRadius
            * configuration.torus.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )
        let slantDerivative = q.multiplied(by: generatorCoordinate)
            .scaled(by: 4.0)
            .subtracting(
                generatorCoordinate.subtracting(
                    axialDistance.multiplied(by: axialDirection)
                ).scaled(by: 2.0 * majorFactor)
            )
        return (implicit, slantDerivative)
    }

    private static func directionInterval(
        center: Double,
        radialU: Double,
        radialV: Double,
        cosine: Interval,
        sine: Interval
    ) -> Interval {
        Interval.constant(center)
            .adding(cosine.scaled(by: radialU))
            .adding(sine.scaled(by: radialV))
    }

    private static func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
    }

    private static func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        first.indices.reduce(Interval.constant(0.0)) { result, index in
            result.adding(first[index].multiplied(by: second[index]))
        }
    }

    private static func certifiedRoots(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedSimplePolynomialRootSolver.Root] {
        let solver = try CertifiedSimplePolynomialRootSolver(
            rootTolerance: rootTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0,
            maximumRefinementIterations: 256,
            tolerance: tolerance
        )
        let coefficients = configuration.coefficients(at: angle)
        let roots = try solver.roots(coefficients: coefficients).filter { root in
            root.upper >= configuration.lowerSlant
                && root.lower <= configuration.upperSlant
        }
        for root in roots {
            let derivative = polynomialDerivative(coefficients, at: root.value)
            guard abs(derivative) > derivativeThreshold(
                configuration: configuration,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "Certified cone-torus root isolation encountered a generator-tangent root."
                )
            }
            guard abs(root.value) > tolerance.distance * 8.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: abs(root.value),
                    tolerance: tolerance,
                    message: "Certified cone-torus root isolation reached the cone apex."
                )
            }
        }
        return roots
    }

    private static func torusGradient(
        offset: Vector3D,
        torus: Torus
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
        torus: Torus
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

    private static func polynomialDerivative(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        guard coefficients.count > 1 else { return 0.0 }
        return (1..<coefficients.count).reversed().reduce(0.0) {
            $0 * value + coefficients[$1] * Double($1)
        }
    }

    private static func derivativeThreshold(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.angle * pow(configuration.characteristicLength, 3.0),
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 3.0) * 256.0
        )
    }

    private static func rootTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.distance * 1.0e-6,
            Double.ulpOfOne * configuration.characteristicLength * 256.0
        )
    }

    private static func residualUpperBound(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let result = rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        ) + Double.ulpOfOne * configuration.characteristicLength * 1_048_576.0
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "General cone-torus root isolation cannot satisfy the requested geometric tolerance."
            )
        }
        return result
    }

    private static func rejectApexContact(
        cone: Cone,
        torus: Torus,
        tolerance: ModelingTolerance
    ) throws {
        let offset = cone.apex - torus.center
        let axial = offset.dot(torus.axis)
        let radialSquared = max(0.0, offset.dot(offset) - axial * axial)
        let meridianDistance = hypot(
            sqrt(radialSquared) - torus.majorRadius,
            axial
        )
        let residual = abs(meridianDistance - torus.minorRadius)
        guard residual > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: residual,
                tolerance: tolerance,
                message: "General cone-torus intersection reaches the cone apex."
            )
        }
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

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case coneSurface
        case torusSurface
        case branchIndex
        case branchCount
        case maximumSubdivisionDepth
        case maximumCellCount
        case certificationTolerance
        case maximumResidualUpperBound
        case apexReduction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .coneSurface,
                .torusSurface,
                .branchIndex,
                .branchCount,
                .maximumSubdivisionDepth,
                .maximumCellCount,
                .certificationTolerance,
                .maximumResidualUpperBound,
                .apexReduction,
            ],
            in: decoder
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        let coneSurface = try container.decode(
            Surface3D.self,
            forKey: .coneSurface
        )
        let torusSurface = try container.decode(
            Surface3D.self,
            forKey: .torusSurface
        )
        let branchIndex = try container.decode(Int.self, forKey: .branchIndex)
        let maximumSubdivisionDepth = try container.decode(
            Int.self,
            forKey: .maximumSubdivisionDepth
        )
        let maximumCellCount = try container.decode(
            Int.self,
            forKey: .maximumCellCount
        )
        let storedBranchCount = try container.decode(
            Int.self,
            forKey: .branchCount
        )
        if let reduction = try container.decodeIfPresent(
            ApexReduction.self,
            forKey: .apexReduction
        ) {
            try self.init(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: branchIndex,
                branchCount: storedBranchCount,
                apexReduction: reduction,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance
            )
        } else {
            try self.init(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: branchIndex,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumCellCount: maximumCellCount,
                tolerance: tolerance
            )
        }
        guard storedBranchCount == branchCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .branchCount,
                in: container,
                debugDescription: "The general cone-torus branch count does not match its regenerated completeness certificate."
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
                debugDescription: "The general cone-torus residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(branchIndex, forKey: .branchIndex)
        try container.encode(branchCount, forKey: .branchCount)
        try container.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try container.encode(maximumCellCount, forKey: .maximumCellCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
        try container.encodeIfPresent(apexReduction, forKey: .apexReduction)
    }
}
