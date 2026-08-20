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
        let firstDerivativeMagnitudeUpperBound: Double
        let secondDerivativeMagnitudeUpperBound: Double
        let traceParameters: [Double]
        let heightsByBranch: [[Double]]

        static func == (lhs: Certificate, rhs: Certificate) -> Bool {
            lhs.branchCount == rhs.branchCount
                && lhs.processedCellCount == rhs.processedCellCount
                && lhs.firstDerivativeMagnitudeUpperBound
                    == rhs.firstDerivativeMagnitudeUpperBound
                && lhs.secondDerivativeMagnitudeUpperBound
                    == rhs.secondDerivativeMagnitudeUpperBound
                && lhs.traceParameters == rhs.traceParameters
                && lhs.heightsByBranch == rhs.heightsByBranch
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(branchCount)
            hasher.combine(processedCellCount)
            hasher.combine(firstDerivativeMagnitudeUpperBound)
            hasher.combine(secondDerivativeMagnitudeUpperBound)
            hasher.combine(traceParameters.count)
            hasher.combine(traceParameters.first ?? 0.0)
            hasher.combine(traceParameters.last ?? 0.0)
            hasher.combine(heightsByBranch.first?.first ?? 0.0)
            hasher.combine(heightsByBranch.last?.last ?? 0.0)
        }

        func referenceHeight(
            branchIndex: Int,
            at angle: Double
        ) -> Double {
            if angle <= traceParameters[0] {
                return heightsByBranch[branchIndex][0]
            }
            if angle >= traceParameters[traceParameters.count - 1] {
                return heightsByBranch[branchIndex][traceParameters.count - 1]
            }
            var lower = 0
            var upper = traceParameters.count - 1
            while upper - lower > 1 {
                let middle = (lower + upper) / 2
                if traceParameters[middle] <= angle {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            let span = traceParameters[upper] - traceParameters[lower]
            let fraction = span > 0.0
                ? (angle - traceParameters[lower]) / span
                : 0.0
            return heightsByBranch[branchIndex][lower]
                + (
                    heightsByBranch[branchIndex][upper]
                        - heightsByBranch[branchIndex][lower]
                ) * fraction
        }
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

        var minimumAbsoluteValue: Double {
            containsZero ? 0.0 : min(abs(lower), abs(upper)).nextDown
        }

        var maximumAbsoluteValue: Double {
            max(abs(lower), abs(upper)).nextUp
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
            max(options.maximumSeedCount * 64, 4_096),
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
              certificate.firstDerivativeMagnitudeUpperBound.isFinite,
              certificate.firstDerivativeMagnitudeUpperBound > 0.0,
              certificate.secondDerivativeMagnitudeUpperBound.isFinite,
              certificate.secondDerivativeMagnitudeUpperBound > 0.0,
              certificate.traceParameters.count >= 2,
              certificate.heightsByBranch.count == branchCount,
              certificate.heightsByBranch.allSatisfy({
                  $0.count == certificate.traceParameters.count
                      && $0.allSatisfy(\.isFinite)
              }),
              certificate.traceParameters.first == 0.0,
              certificate.traceParameters.last == 2.0 * Double.pi,
              zip(
                  certificate.traceParameters,
                  certificate.traceParameters.dropFirst()
              ).allSatisfy({ $0 < $1 }),
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
        let referenceHeight = certificate.referenceHeight(
            branchIndex: branchIndex,
            at: angle
        )
        let height = try Self.refinedRoot(
            angle: angle,
            initialHeight: referenceHeight,
            configuration: configuration,
            tolerance: tolerance
        )
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

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        return SpatialDifferentialMagnitudeBounds(
            first: certificate.firstDerivativeMagnitudeUpperBound,
            second: certificate.secondDerivativeMagnitudeUpperBound
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
        var maximumHeightFirstDerivative = 0.0
        var maximumHeightSecondDerivative = 0.0
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
            let values = implicitDifferentialIntervals(
                angle: cell.angle,
                height: cell.height,
                configuration: configuration
            )
            if values.implicit.containsZero == false {
                continue
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedHeightWidth = cell.height.width
                / (configuration.upperHeight - configuration.lowerHeight)
            let differentialCellWidth = 1.0 / 128.0
            if values.heightDerivative.containsZero == false,
               normalizedAngleWidth <= differentialCellWidth,
               normalizedHeightWidth <= differentialCellWidth {
                let denominator = values.heightDerivative.minimumAbsoluteValue
                let heightFirstDerivative = (
                    values.angleDerivative.maximumAbsoluteValue / denominator
                ).nextUp
                let heightSecondDerivative = ((
                    values.angleAngleDerivative.maximumAbsoluteValue
                        + 2.0
                            * values.angleHeightDerivative.maximumAbsoluteValue
                            * heightFirstDerivative
                        + values.heightHeightDerivative.maximumAbsoluteValue
                            * heightFirstDerivative * heightFirstDerivative
                ) / denominator).nextUp
                maximumHeightFirstDerivative = max(
                    maximumHeightFirstDerivative,
                    heightFirstDerivative
                )
                maximumHeightSecondDerivative = max(
                    maximumHeightSecondDerivative,
                    heightSecondDerivative
                )
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
        let trace = try makeRootTrace(
            initialHeights: initialRoots.map(\.value),
            configuration: configuration,
            tolerance: tolerance
        )
        let angularScale = (2.0 * Double.pi).nextUp
        let firstDerivativeMagnitudeUpperBound = ((
            configuration.cylinder.radius + maximumHeightFirstDerivative
        ).nextUp * angularScale).nextUp
        let secondDerivativeMagnitudeUpperBound = ((
            configuration.cylinder.radius + maximumHeightSecondDerivative
        ).nextUp * angularScale * angularScale).nextUp
        return Certificate(
            branchCount: initialRoots.count,
            processedCellCount: processedCellCount,
            firstDerivativeMagnitudeUpperBound:
                firstDerivativeMagnitudeUpperBound,
            secondDerivativeMagnitudeUpperBound:
                secondDerivativeMagnitudeUpperBound,
            traceParameters: trace.parameters,
            heightsByBranch: trace.heightsByBranch
        )
    }

    private static func makeRootTrace(
        initialHeights: [Double],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> (
        parameters: [Double],
        heightsByBranch: [[Double]]
    ) {
        let period = 2.0 * Double.pi
        let initialSegmentCount = 32
        let maximumDepth = 16
        let maximumSegmentCount = 4_096
        var parameters = [0.0]
        var heightsByBranch = initialHeights.map { [$0] }
        var acceptedSegmentCount = 0

        func appendInterval(
            lowerAngle: Double,
            lowerHeights: [Double],
            upperAngle: Double,
            depth: Int
        ) throws -> [Double] {
            let refined = try lowerHeights.map {
                try refinedRoot(
                    angle: upperAngle,
                    initialHeight: $0,
                    configuration: configuration,
                    tolerance: tolerance
                )
            }
            let sorted = refined.sorted()
            let minimumSeparation = zip(
                sorted,
                sorted.dropFirst()
            ).map { $1 - $0 }.min() ?? .infinity
            let maximumMovement = zip(
                lowerHeights,
                refined
            ).map { abs($1 - $0) }.max() ?? 0.0
            let movementLimit = min(
                configuration.characteristicLength * 0.125,
                minimumSeparation * 0.25
            )
            let rootResolution = rootTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let preservesOrder = zip(refined, sorted).allSatisfy {
                abs($0 - $1) <= rootResolution * 8.0
            }
            if preservesOrder,
               minimumSeparation > rootResolution * 16.0,
               maximumMovement < movementLimit {
                acceptedSegmentCount += 1
                guard acceptedSegmentCount <= maximumSegmentCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        residual: Double(acceptedSegmentCount),
                        tolerance: tolerance,
                        message: "General torus-cylinder root continuation exceeded its segment budget."
                    )
                }
                parameters.append(upperAngle)
                for branchIndex in heightsByBranch.indices {
                    heightsByBranch[branchIndex].append(refined[branchIndex])
                }
                return refined
            }
            guard depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: maximumMovement,
                    tolerance: tolerance,
                    message: "General torus-cylinder root continuation remained ambiguous after adaptive subdivision."
                )
            }
            let middle = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let middleHeights = try appendInterval(
                lowerAngle: lowerAngle,
                lowerHeights: lowerHeights,
                upperAngle: middle,
                depth: depth + 1
            )
            return try appendInterval(
                lowerAngle: middle,
                lowerHeights: middleHeights,
                upperAngle: upperAngle,
                depth: depth + 1
            )
        }

        var lowerAngle = 0.0
        var lowerHeights = initialHeights
        for index in 1...initialSegmentCount {
            let upperAngle = period * Double(index) / Double(initialSegmentCount)
            lowerHeights = try appendInterval(
                lowerAngle: lowerAngle,
                lowerHeights: lowerHeights,
                upperAngle: upperAngle,
                depth: 0
            )
            lowerAngle = upperAngle
        }
        let closureTolerance = rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        ) * 16.0
        guard zip(lowerHeights, initialHeights).allSatisfy({
            abs($0 - $1) <= closureTolerance
        }) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: zip(lowerHeights, initialHeights).map {
                    abs($0 - $1)
                }.max(),
                tolerance: tolerance,
                message: "General torus-cylinder root continuation did not close over one angular period."
            )
        }
        return (parameters, heightsByBranch)
    }

    private static func implicitDifferentialIntervals(
        angle: Interval,
        height: Interval,
        configuration: Configuration
    ) -> (
        implicit: Interval,
        angleDerivative: Interval,
        heightDerivative: Interval,
        angleAngleDerivative: Interval,
        angleHeightDerivative: Interval,
        heightHeightDerivative: Interval
    ) {
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
        let angleTangent = [
            sine.scaled(by: -configuration.cylinder.radialU.x)
                .adding(cosine.scaled(by: configuration.cylinder.radialV.x)),
            sine.scaled(by: -configuration.cylinder.radialU.y)
                .adding(cosine.scaled(by: configuration.cylinder.radialV.y)),
            sine.scaled(by: -configuration.cylinder.radialU.z)
                .adding(cosine.scaled(by: configuration.cylinder.radialV.z)),
        ]
        let angleSecond = [
            cosine.scaled(by: -configuration.cylinder.radialU.x)
                .adding(sine.scaled(by: -configuration.cylinder.radialV.x)),
            cosine.scaled(by: -configuration.cylinder.radialU.y)
                .adding(sine.scaled(by: -configuration.cylinder.radialV.y)),
            cosine.scaled(by: -configuration.cylinder.radialU.z)
                .adding(sine.scaled(by: -configuration.cylinder.radialV.z)),
        ]
        let squaredLength = x.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(x, configuration.torus.axis)
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
        let radial = [
            x[0].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.x)
            ),
            x[1].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.y)
            ),
            x[2].subtracting(
                axialDistance.scaled(by: configuration.torus.axis.z)
            ),
        ]
        let gradient = [
            q.multiplied(by: x[0]).scaled(by: 4.0).subtracting(
                radial[0].scaled(by: 2.0 * majorFactor)
            ),
            q.multiplied(by: x[1]).scaled(by: 4.0).subtracting(
                radial[1].scaled(by: 2.0 * majorFactor)
            ),
            q.multiplied(by: x[2]).scaled(by: 4.0).subtracting(
                radial[2].scaled(by: 2.0 * majorFactor)
            ),
        ]
        let axisIntervals = [
            Interval.constant(configuration.cylinder.axis.x),
            Interval.constant(configuration.cylinder.axis.y),
            Interval.constant(configuration.cylinder.axis.z),
        ]
        let angleDerivative = dotInterval(gradient, angleTangent)
        let heightDerivative = dotInterval(
            gradient,
            configuration.cylinder.axis
        )
        let angleAngleDerivative = torusHessianBilinearInterval(
            offset: x,
            q: q,
            first: angleTangent,
            second: angleTangent,
            torus: configuration.torus
        ).adding(dotInterval(gradient, angleSecond))
        let angleHeightDerivative = torusHessianBilinearInterval(
            offset: x,
            q: q,
            first: angleTangent,
            second: axisIntervals,
            torus: configuration.torus
        )
        let heightHeightDerivative = torusHessianBilinearInterval(
            offset: x,
            q: q,
            first: axisIntervals,
            second: axisIntervals,
            torus: configuration.torus
        )
        return (
            implicit,
            angleDerivative,
            heightDerivative,
            angleAngleDerivative,
            angleHeightDerivative,
            heightHeightDerivative
        )
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

    private static func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        first[0].multiplied(by: second[0])
            .adding(first[1].multiplied(by: second[1]))
            .adding(first[2].multiplied(by: second[2]))
    }

    private static func torusHessianBilinearInterval(
        offset: [Interval],
        q: Interval,
        first: [Interval],
        second: [Interval],
        torus: Torus
    ) -> Interval {
        let firstSecond = dotInterval(first, second)
        let firstAxis = dotInterval(first, torus.axis)
        let secondAxis = dotInterval(second, torus.axis)
        return dotInterval(offset, first)
            .multiplied(by: dotInterval(offset, second))
            .scaled(by: 8.0)
            .adding(
                q.multiplied(by: firstSecond).scaled(by: 4.0)
            )
            .subtracting(
                firstSecond.subtracting(
                    firstAxis.multiplied(by: secondAxis)
                ).scaled(by: 8.0 * torus.majorRadius * torus.majorRadius)
            )
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

    private static func refinedRoot(
        angle: Double,
        initialHeight: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let coefficients = configuration.coefficients(at: angle)
        let derivativeLowerBound = derivativeThreshold(
            configuration: configuration,
            tolerance: tolerance
        )
        let stepTolerance = rootTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        var height = initialHeight
        var converged = false
        for _ in 0..<24 {
            let value = polynomialValue(coefficients, at: height)
            let derivative = polynomialDerivative(coefficients, at: height)
            guard value.isFinite,
                  derivative.isFinite,
                  abs(derivative) > derivativeLowerBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "General torus-cylinder branch refinement reached a generator-tangent root."
                )
            }
            let step = value / derivative
            height -= step
            if abs(step) <= stepTolerance {
                converged = true
                break
            }
        }
        guard converged,
              height >= configuration.lowerHeight,
              height <= configuration.upperHeight else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: abs(polynomialValue(coefficients, at: height)),
                tolerance: tolerance,
                message: "General torus-cylinder branch refinement left its certified simple-root domain."
            )
        }
        return height
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

    private static func polynomialValue(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) {
            $0 * value + $1
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
