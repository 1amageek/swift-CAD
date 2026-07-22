import CADCore
import Foundation

public struct CertifiedGeneralTorusCylinderIntersectionCurve: Codable, Hashable, Sendable {
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

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
        let radialU: Vector3D
        let radialV: Vector3D
    }

    private struct Configuration {
        let torus: Torus
        let cylinder: Cylinder
        let lowerHeight: Double
        let upperHeight: Double
        let characteristicLength: Double

        func generatorPoint(angle: Double, height: Double) -> Point3D {
            cylinder.origin
                + cylinder.radialU * cos(angle)
                + cylinder.radialV * sin(angle)
                + cylinder.axis * height
        }

        func generatorAngleDerivative(angle: Double) -> Vector3D {
            cylinder.radialU * -sin(angle)
                + cylinder.radialV * cos(angle)
        }

        func generatorAngleSecondDerivative(angle: Double) -> Vector3D {
            cylinder.radialU * -cos(angle)
                + cylinder.radialV * -sin(angle)
        }

        func coefficients(at angle: Double) -> [Double] {
            let point = generatorPoint(angle: angle, height: 0.0)
            let offset = point - torus.center
            let pointSquared = offset.dot(offset)
            let pointDirection = offset.dot(cylinder.axis)
            let axialPoint = offset.dot(torus.axis)
            let axialDirection = cylinder.axis.dot(torus.axis)
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
        let height: Interval
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

        var width: Double {
            upper - lower
        }

        var midpoint: Double {
            lower + width * 0.5
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

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

    public let torusSurface: Surface3D
    public let cylinderSurface: Surface3D
    public let branchIndex: Int
    public let branchCount: Int
    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    private let certificate: Certificate

    public init(
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int = 24,
        maximumCellCount: Int = 65_536,
        tolerance: ModelingTolerance
    ) throws {
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let certificate = try Self.makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        try self.init(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            branchIndex: branchIndex,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance,
            configuration: configuration,
            certificate: certificate
        )
    }

    private init(
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        branchIndex: Int,
        maximumSubdivisionDepth: Int,
        maximumCellCount: Int,
        tolerance: ModelingTolerance,
        configuration: Configuration,
        certificate: Certificate
    ) throws {
        self.torusSurface = torusSurface
        self.cylinderSurface = cylinderSurface
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
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedGeneralTorusCylinderIntersectionCurve] {
        try options.validate(tolerance: tolerance)
        let maximumSubdivisionDepth = min(
            options.maximumSubdivisionDepth + 12,
            24
        )
        let maximumCellCount = min(
            max(options.maximumSeedCount * 16, 4_096),
            65_536
        )
        let configuration = try makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
        let certificate = try makeCertificate(
            configuration: configuration,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumCellCount: maximumCellCount,
            tolerance: tolerance
        )
        return try (0..<certificate.branchCount).map { branchIndex in
            try CertifiedGeneralTorusCylinderIntersectionCurve(
                torusSurface: torusSurface,
                cylinderSurface: cylinderSurface,
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
                message: "A general torus-cylinder curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        _ = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
            tolerance: tolerance
        )
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
                message: "A general torus-cylinder branch has an invalid stored completeness certificate."
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
        let angle = clamped == 1.0 ? 0.0 : 2.0 * Double.pi * clamped
        let configuration = try Self.makeConfiguration(
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
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
                message: "A certified torus-cylinder branch changed generator root count during evaluation."
            )
        }
        let height = roots[branchIndex].value
        let position = configuration.generatorPoint(angle: angle, height: height)
        let angleTangent = configuration.generatorAngleDerivative(angle: angle)
        let angleSecond = configuration.generatorAngleSecondDerivative(angle: angle)
        let offset = position - configuration.torus.center
        let gradient = Self.torusGradient(
            offset: offset,
            torus: configuration.torus
        )
        let heightDerivativeDenominator = gradient.dot(configuration.cylinder.axis)
        let derivativeThreshold = Self.derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        )
        guard heightDerivativeDenominator.isFinite,
              abs(heightDerivativeDenominator) > derivativeThreshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(heightDerivativeDenominator),
                tolerance: tolerance,
                message: "A certified torus-cylinder branch reached a generator-tangent root."
            )
        }
        let firstAngleImplicit = gradient.dot(angleTangent)
        let heightAngleDerivative = -firstAngleImplicit
            / heightDerivativeDenominator
        let angleAngleImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: angleTangent,
            torus: configuration.torus
        ) + gradient.dot(angleSecond)
        let angleHeightImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: angleTangent,
            second: configuration.cylinder.axis,
            torus: configuration.torus
        )
        let heightHeightImplicit = Self.torusHessianBilinear(
            offset: offset,
            first: configuration.cylinder.axis,
            second: configuration.cylinder.axis,
            torus: configuration.torus
        )
        let heightAngleSecondDerivative = -(
            angleAngleImplicit
                + 2.0 * angleHeightImplicit * heightAngleDerivative
                + heightHeightImplicit
                    * heightAngleDerivative * heightAngleDerivative
        ) / heightDerivativeDenominator
        let angularScale = 2.0 * Double.pi
        let firstDerivative = (
            angleTangent
                + configuration.cylinder.axis * heightAngleDerivative
        ) * angularScale
        let secondDerivative = (
            angleSecond
                + configuration.cylinder.axis * heightAngleSecondDerivative
        ) * (angularScale * angularScale)
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified torus-cylinder component has a singular differential."
            )
        }
        let torusProjection = try torusSurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let cylinderProjection = try cylinderSurface.parameterProjection(
            of: position,
            tolerance: tolerance
        )
        let residual = max(torusProjection.residual, cylinderProjection.residual)
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified torus-cylinder root exceeded its geometric residual bound."
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
        guard surface == torusSurface || surface == cylinderSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general torus-cylinder pcurve was requested on an unrelated surface."
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
            torusSurface: torusSurface,
            cylinderSurface: cylinderSurface,
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
        torusSurface: Surface3D,
        cylinderSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try torusSurface.validate(tolerance: tolerance)
        try cylinderSurface.validate(tolerance: tolerance)
        guard case let .torus(sourceTorus) = CanonicalAnalyticSurface(torusSurface),
              case let .cylinder(sourceCylinder) = CanonicalAnalyticSurface(
                cylinderSurface
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified general torus-cylinder curve requires one exact torus and one exact cylinder."
            )
        }
        guard AnalyticAxisRelation.areParallel(
            sourceTorus.axis,
            sourceCylinder.axis,
            tolerance: tolerance
        ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A general torus-cylinder curve requires non-parallel source axes."
            )
        }
        var torusAxis = try sourceTorus.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(torusAxis) { torusAxis = -torusAxis }
        var cylinderAxis = try sourceCylinder.axis.normalized(
            tolerance: tolerance.distance
        )
        if isNegative(cylinderAxis) { cylinderAxis = -cylinderAxis }
        let originVector = sourceCylinder.origin - .origin
        let cylinderOrigin = sourceCylinder.origin
            + cylinderAxis * -originVector.dot(cylinderAxis)
        let basis = try analyticOrthonormalBasis(
            cylinderAxis,
            tolerance: tolerance
        )
        let cylinder = Cylinder(
            origin: cylinderOrigin,
            axis: cylinderAxis,
            radius: sourceCylinder.radius,
            radialU: basis.u * sourceCylinder.radius,
            radialV: basis.v * sourceCylinder.radius
        )
        let torus = Torus(
            center: sourceTorus.center,
            axis: torusAxis,
            majorRadius: sourceTorus.majorRadius,
            minorRadius: sourceTorus.minorRadius
        )
        let outerRadius = sourceTorus.majorRadius + sourceTorus.minorRadius
        let centerHeight = (sourceTorus.center - cylinderOrigin).dot(cylinderAxis)
        let margin = tolerance.distance * 16.0
        return Configuration(
            torus: torus,
            cylinder: cylinder,
            lowerHeight: centerHeight - outerRadius - margin,
            upperHeight: centerHeight + outerRadius + margin,
            characteristicLength: max(
                outerRadius,
                sourceCylinder.radius,
                (sourceTorus.center - cylinderOrigin).length,
                1.0
            )
        )
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
                message: "General torus-cylinder certification limits are outside the supported resource envelope."
            )
        }
        var cells = [Cell(
            angle: Interval(0.0, 2.0 * Double.pi),
            height: Interval(configuration.lowerHeight, configuration.upperHeight),
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
                    message: "Torus-cylinder generator tangency certification exceeded its cell limit."
                )
            }
            let values = implicitIntervals(
                angle: cell.angle,
                height: cell.height,
                configuration: configuration
            )
            if values.implicit.containsZero == false
                || values.heightDerivative.containsZero == false {
                continue
            }
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(cell.angle.width, cell.height.width),
                    tolerance: tolerance,
                    message: "Non-parallel torus-cylinder subdivision exhausted its budget before certifying root simplicity."
                )
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedHeightWidth = cell.height.width
                / (configuration.upperHeight - configuration.lowerHeight)
            if normalizedAngleWidth >= normalizedHeightWidth {
                let middle = cell.angle.midpoint
                cells.append(Cell(
                    angle: Interval(middle, cell.angle.upper),
                    height: cell.height,
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: Interval(cell.angle.lower, middle),
                    height: cell.height,
                    depth: cell.depth + 1
                ))
            } else {
                let middle = cell.height.midpoint
                cells.append(Cell(
                    angle: cell.angle,
                    height: Interval(middle, cell.height.upper),
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: cell.angle,
                    height: Interval(cell.height.lower, middle),
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
        height: Interval,
        configuration: Configuration
    ) -> (implicit: Interval, heightDerivative: Interval) {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let centerOffset = configuration.cylinder.origin
            - configuration.torus.center
        let x = [
            coordinateInterval(
                center: centerOffset.x,
                radialU: configuration.cylinder.radialU.x,
                radialV: configuration.cylinder.radialV.x,
                axis: configuration.cylinder.axis.x,
                cosine: cosine,
                sine: sine,
                height: height
            ),
            coordinateInterval(
                center: centerOffset.y,
                radialU: configuration.cylinder.radialU.y,
                radialV: configuration.cylinder.radialV.y,
                axis: configuration.cylinder.axis.y,
                cosine: cosine,
                sine: sine,
                height: height
            ),
            coordinateInterval(
                center: centerOffset.z,
                radialU: configuration.cylinder.radialU.z,
                radialV: configuration.cylinder.radialV.z,
                axis: configuration.cylinder.axis.z,
                cosine: cosine,
                sine: sine,
                height: height
            ),
        ]
        let squaredLength = x.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(x, configuration.torus.axis)
        let generatorCoordinate = dotInterval(x, configuration.cylinder.axis)
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
        let axialDirection = configuration.torus.axis.dot(
            configuration.cylinder.axis
        )
        let heightDerivative = q.multiplied(by: generatorCoordinate)
            .scaled(by: 4.0)
            .subtracting(
                generatorCoordinate.subtracting(
                    axialDistance.scaled(by: axialDirection)
                ).scaled(by: 2.0 * majorFactor)
            )
        return (implicit, heightDerivative)
    }

    private static func coordinateInterval(
        center: Double,
        radialU: Double,
        radialV: Double,
        axis: Double,
        cosine: Interval,
        sine: Interval,
        height: Interval
    ) -> Interval {
        Interval.constant(center)
            .adding(cosine.scaled(by: radialU))
            .adding(sine.scaled(by: radialV))
            .adding(height.scaled(by: axis))
    }

    private static func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
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
        let roots = try solver.roots(
            coefficients: configuration.coefficients(at: angle)
        ).filter { root in
            root.upper >= configuration.lowerHeight
                && root.lower <= configuration.upperHeight
        }
        for root in roots {
            let derivative = polynomialDerivative(
                configuration.coefficients(at: angle),
                at: root.value
            )
            guard abs(derivative) > derivativeThreshold(
                configuration: configuration,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "Certified torus-cylinder root isolation encountered a generator-tangent root."
                )
            }
        }
        return roots
    }

    private static func torusGradient(
        offset: Vector3D,
        torus: Torus
    ) -> Vector3D {
        let squaredLength = offset.dot(offset)
        let q = squaredLength
            + torus.majorRadius * torus.majorRadius
            - torus.minorRadius * torus.minorRadius
        let axial = offset.dot(torus.axis)
        let radial = offset - torus.axis * axial
        return offset * (4.0 * q)
            - radial * (8.0 * torus.majorRadius * torus.majorRadius)
    }

    private static func torusHessianBilinear(
        offset: Vector3D,
        first: Vector3D,
        second: Vector3D,
        torus: Torus
    ) -> Double {
        let squaredLength = offset.dot(offset)
        let q = squaredLength
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
                message: "General torus-cylinder root isolation cannot satisfy the requested geometric tolerance."
            )
        }
        return result
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
        case torusSurface
        case cylinderSurface
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
                .torusSurface,
                .cylinderSurface,
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
            torusSurface: container.decode(Surface3D.self, forKey: .torusSurface),
            cylinderSurface: container.decode(
                Surface3D.self,
                forKey: .cylinderSurface
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
        let storedBranchCount = try container.decode(
            Int.self,
            forKey: .branchCount
        )
        guard storedBranchCount == branchCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .branchCount,
                in: container,
                debugDescription: "The general torus-cylinder branch count does not match its regenerated completeness certificate."
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
                debugDescription: "The general torus-cylinder residual certificate does not match the reconstructed source surfaces."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(cylinderSurface, forKey: .cylinderSurface)
        try container.encode(branchIndex, forKey: .branchIndex)
        try container.encode(branchCount, forKey: .branchCount)
        try container.encode(maximumSubdivisionDepth, forKey: .maximumSubdivisionDepth)
        try container.encode(maximumCellCount, forKey: .maximumCellCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
