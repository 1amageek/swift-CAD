import CADCore
import Foundation

public struct CertifiedConeConeIntersectionCurve: Codable, Hashable, Sendable {
    public enum ComponentKind: String, Codable, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case apexReducedAngularInterval
    }

    enum ApexContactTopology {
        case isolatedPoint
        case isolatedPointAndLoop
        case nodeIntervals([ClosedRange<Double>])
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct ThirdOrderDifferentialGeometry {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
        let thirdDerivative: Vector3D
    }

    struct ParameterDifferentialThroughThirdOrder: Sendable {
        let parameter: SurfaceParameter
        let firstDerivative: Point2D
        let secondDerivative: Point2D
        let thirdDerivative: Point2D
    }

    fileprivate struct Cone: Sendable {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    fileprivate struct TrigonometricPolynomial: Sendable {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        var coefficientScale: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                abs(sineDouble),
                1.0
            )
        }

        var absoluteCoefficientSum: Double {
            abs(constant)
                + abs(cosine)
                + abs(sine)
                + abs(cosineDouble)
                + abs(sineDouble)
        }

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine + 4.0 * sineDouble,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine - 4.0 * sineDouble,
                constant - cosine + cosineDouble,
            ]
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }

        func firstDerivative(at angle: Double) -> Double {
            -cosine * sin(angle)
                + sine * cos(angle)
                - 2.0 * cosineDouble * sin(2.0 * angle)
                + 2.0 * sineDouble * cos(2.0 * angle)
        }

        func secondDerivative(at angle: Double) -> Double {
            -cosine * cos(angle)
                - sine * sin(angle)
                - 4.0 * cosineDouble * cos(2.0 * angle)
                - 4.0 * sineDouble * sin(2.0 * angle)
        }

        func thirdDerivative(at angle: Double) -> Double {
            cosine * sin(angle)
                - sine * cos(angle)
                + 8.0 * cosineDouble * sin(2.0 * angle)
                - 8.0 * sineDouble * cos(2.0 * angle)
        }

        var derivativePolynomial: TrigonometricPolynomial {
            TrigonometricPolynomial(
                constant: 0.0,
                cosine: sine,
                sine: -cosine,
                cosineDouble: 2.0 * sineDouble,
                sineDouble: -2.0 * cosineDouble
            )
        }
    }

    fileprivate struct Configuration: Sendable {
        let reference: Cone
        let parameterized: Cone
        let referenceBasisU: Vector3D
        let referenceBasisV: Vector3D
        let parameterizedBasisU: Vector3D
        let parameterizedBasisV: Vector3D
        let baseOffset: Vector3D
        let referenceMetricScale: Double
        let constantTerm: Double
        let halfLinearPolynomial: TrigonometricPolynomial
        let quadraticPolynomial: TrigonometricPolynomial
        let discriminantPolynomial: TrigonometricPolynomial

        var characteristicLength: Double {
            max(baseOffset.length, 1.0)
        }

        func direction(at angle: Double) -> Vector3D {
            parameterized.axis * cos(parameterized.halfAngle)
                + radial(at: angle) * sin(parameterized.halfAngle)
        }

        func directionFirstDerivative(at angle: Double) -> Vector3D {
            tangent(at: angle) * sin(parameterized.halfAngle)
        }

        func directionSecondDerivative(at angle: Double) -> Vector3D {
            -radial(at: angle) * sin(parameterized.halfAngle)
        }

        func directionThirdDerivative(at angle: Double) -> Vector3D {
            -tangent(at: angle) * sin(parameterized.halfAngle)
        }

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - referenceMetricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }

        private func radial(at angle: Double) -> Vector3D {
            parameterizedBasisU * cos(angle)
                + parameterizedBasisV * sin(angle)
        }

        private func tangent(at angle: Double) -> Vector3D {
            -parameterizedBasisU * sin(angle)
                + parameterizedBasisV * cos(angle)
        }
    }

    struct FullBranchDifferentialBoundsPreparation: Sendable {
        struct ParameterDifferentialMagnitudeBounds: Sendable {
            let uFirst: Double
            let vFirst: Double
            let uSecond: Double
            let vSecond: Double
            let uThird: Double
            let vThird: Double

            func scaled(
                by scale: Double
            ) -> ParameterDifferentialMagnitudeBounds {
                let firstScale = abs(scale).nextUp
                let secondScale = (firstScale * firstScale).nextUp
                let thirdScale = (secondScale * firstScale).nextUp
                return ParameterDifferentialMagnitudeBounds(
                    uFirst: (uFirst * firstScale).nextUp,
                    vFirst: (vFirst * firstScale).nextUp,
                    uSecond: (uSecond * secondScale).nextUp,
                    vSecond: (vSecond * secondScale).nextUp,
                    uThird: (uThird * thirdScale).nextUp,
                    vThird: (vThird * thirdScale).nextUp
                )
            }
        }

        fileprivate struct Cell: Sendable {
            let spatial: SpatialDifferentialMagnitudeBounds
            let parameterizedVFirst: Double
            let parameterizedVSecond: Double
            let parameterizedVThird: Double
        }

        fileprivate struct ReferenceChart: Sendable {
            let uNodes: [Double]
            let maximumUVariations: [Double]
        }

        private let curve: CertifiedConeConeIntersectionCurve
        private let configuration: Configuration
        private let cells: [Cell]
        private let referenceChart: ReferenceChart

        fileprivate init(
            curve: CertifiedConeConeIntersectionCurve,
            configuration: Configuration,
            cells: [Cell],
            referenceChart: ReferenceChart
        ) {
            self.curve = curve
            self.configuration = configuration
            self.cells = cells
            self.referenceChart = referenceChart
        }

        func parameterizedParameterDifferential(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> ParameterDifferentialThroughThirdOrder {
            try curve.parameterizedParameterDifferential(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            )
        }

        func parameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> SurfaceParameter {
            try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            )
        }

        func continuousParameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> SurfaceParameter {
            let parameter = try self.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            guard CertifiedConeConeIntersectionCurve.isEquivalent(
                surface,
                to: curve.referenceSurface
            ) else {
                return parameter
            }
            guard fraction.isFinite,
                  fraction >= -tolerance.relative,
                  fraction <= 1.0 + tolerance.relative,
                  referenceChart.uNodes.count == cells.count + 1,
                  referenceChart.maximumUVariations.count == cells.count else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A root-free cone-cone reference chart has an invalid continuous-lift preparation."
                )
            }
            let boundedFraction = min(max(fraction, 0.0), 1.0)
            if boundedFraction == 1.0 {
                return SurfaceParameter(
                    u: referenceChart.uNodes[cells.count],
                    v: parameter.v
                )
            }
            let index = min(
                cells.count - 1,
                Int(floor(boundedFraction * Double(cells.count)))
            )
            let anchor = referenceChart.uNodes[index]
            let period = 2.0 * Double.pi
            let turn = round((anchor - parameter.u) / period)
            let liftedU = parameter.u + turn * period
            let arithmeticEnvelope = (
                Double.ulpOfOne * max(abs(anchor), abs(liftedU), 1.0)
                    * 16_384.0
            ).nextUp
            guard abs(liftedU - anchor)
                    <= referenceChart.maximumUVariations[index]
                        + arithmeticEnvelope else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    residual: abs(liftedU - anchor),
                    tolerance: tolerance,
                    message: "A root-free cone-cone reference parameter left its certified continuous chart cell."
                )
            }
            return SurfaceParameter(u: liftedU, v: parameter.v)
        }

        func referenceParameterAndFirstDerivative(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> (parameter: SurfaceParameter, firstDerivative: Point2D) {
            try curve.referenceParameterAndFirstDerivative(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            )
        }

        func bounds(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        ) throws -> SpatialDifferentialMagnitudeBounds {
            guard lower.isFinite,
                  upper.isFinite,
                  lower >= -tolerance.relative,
                  upper <= 1.0 + tolerance.relative,
                  upper - lower > Double.leastNonzeroMagnitude else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: upper - lower,
                    tolerance: tolerance,
                    message: "Local root-free cone-cone differential bounds require an ordered nondegenerate source interval."
                )
            }
            guard cells.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A root-free cone-cone differential preparation has no proof cells."
                )
            }
            let indices = try overlappingCellIndices(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
            var first = 0.0
            var second = 0.0
            var third = 0.0
            for index in indices {
                let spatial = cells[index].spatial
                first = max(first, spatial.first)
                second = max(second, spatial.second)
                guard let cellThird = spatial.third else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A root-free cone-cone proof cell has no third-derivative certificate."
                    )
                }
                third = max(third, cellThird)
            }
            return SpatialDifferentialMagnitudeBounds(
                first: first,
                second: second,
                third: third
            )
        }

        func parameterizedParameterDifferentialMagnitudeBounds(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        ) throws -> ParameterDifferentialMagnitudeBounds {
            let indices = try overlappingCellIndices(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
            var vFirst = 0.0
            var vSecond = 0.0
            var vThird = 0.0
            for index in indices {
                let cell = cells[index]
                vFirst = max(vFirst, cell.parameterizedVFirst)
                vSecond = max(vSecond, cell.parameterizedVSecond)
                vThird = max(vThird, cell.parameterizedVThird)
            }
            let period = (2.0 * Double.pi).nextUp
            return ParameterDifferentialMagnitudeBounds(
                uFirst: period,
                vFirst: vFirst,
                uSecond: 0.0,
                vSecond: vSecond,
                uThird: 0.0,
                vThird: vThird
            )
        }

        private func overlappingCellIndices(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        ) throws -> ClosedRange<Int> {
            guard lower.isFinite,
                  upper.isFinite,
                  lower >= -tolerance.relative,
                  upper <= 1.0 + tolerance.relative,
                  upper - lower > Double.leastNonzeroMagnitude else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: upper - lower,
                    tolerance: tolerance,
                    message: "Local root-free cone-cone differential bounds require an ordered nondegenerate source interval."
                )
            }
            guard cells.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A root-free cone-cone differential preparation has no proof cells."
                )
            }
            let boundedLower = min(max(lower, 0.0), 1.0)
            let boundedUpper = min(max(upper, 0.0), 1.0)
            let lowerIndex = min(
                cells.count - 1,
                Int(floor(boundedLower * Double(cells.count)))
            )
            let upperIndex = min(
                cells.count - 1,
                Int(floor(boundedUpper * Double(cells.count)))
            )
            return lowerIndex...upperIndex
        }
    }

    private struct PiecewiseDifferentialBounds {
        let aggregate: SpatialDifferentialMagnitudeBounds
        let cells: [FullBranchDifferentialBoundsPreparation.Cell]
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

        func scaled(by scale: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scale,
                first: first * scale,
                second: second * scale,
                third: third * scale
            )
        }
    }

    private struct CertifiedInterval {
        let lower: Double
        let upper: Double

        var absoluteUpperBound: Double {
            max(abs(lower), abs(upper)).nextUp
        }
    }

    public let referenceSurface: Surface3D
    public let parameterizedSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.referenceSurface = referenceSurface
        self.parameterizedSurface = parameterizedSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance
        )
        try validate(tolerance: tolerance)
    }

    static func apexContactTopology(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ApexContactTopology? {
        let configuration = try makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        guard apexReductionResidualUpperBound(
            configuration: configuration
        ) <= tolerance.distance else {
            return nil
        }
        let halfLinearTolerance = max(
            Double.ulpOfOne * configuration.characteristicLength * 4_096.0,
            tolerance.distance * 1.0e-6
        )
        let maximumHalfLinear = try maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        )
        guard maximumHalfLinear > halfLinearTolerance else {
            return .isolatedPoint
        }
        let boundaries = try roots(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        )
        guard boundaries.isEmpty == false else {
            return .isolatedPointAndLoop
        }
        let intervals = boundaries.indices.map { index in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return lower...upper
        }
        return .nodeIntervals(intervals)
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
                message: "A cone-cone curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        guard lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperAngle - lowerAngle)
        }
        let classificationTolerance = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let boundaries = try Self.roots(
            of: configuration.discriminantPolynomial,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let minimumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: false,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let maximumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: true,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        )
        let quadraticTolerance = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
        guard minimumQuadratic > quadraticTolerance
                || maximumQuadratic < -quadraticTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: min(abs(minimumQuadratic), abs(maximumQuadratic)),
                tolerance: tolerance,
                message: "A certified cone-cone curve contains an asymptotic ruling."
            )
        }

        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let minimumDiscriminant = try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: classificationTolerance,
                tolerance: tolerance
            )
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  minimumDiscriminant > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumDiscriminant,
                    tolerance: tolerance,
                    message: "A full cone-cone branch requires a positive root-free discriminant domain."
                )
            }
        case .boundedAngularInterval:
            let lowerResidual = abs(configuration.discriminantPolynomial.value(at: lowerAngle))
            let upperResidual = abs(configuration.discriminantPolynomial.value(at: upperAngle))
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let matchesCompleteInterval = Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminantPolynomial,
                classificationTolerance: classificationTolerance
            ).contains { interval in
                Self.angularDistance(interval.lower, lowerAngle) <= tolerance.angle
                    && Self.angularDistance(interval.upper, upperAngle) <= tolerance.angle
            }
            guard lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  matchesCompleteInterval,
                  configuration.discriminantPolynomial.value(at: midpoint)
                    > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded cone-cone component failed endpoint or interior certification."
                )
            }
        case .apexReducedAngularInterval:
            guard let topology = try Self.apexContactTopology(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: Self.apexReductionResidualUpperBound(
                        configuration: configuration
                    ),
                    tolerance: tolerance,
                    message: "An apex-reduced cone-cone component requires a certified cone-apex contact."
                )
            }
            let matchesTopology: Bool
            switch topology {
            case .isolatedPoint:
                matchesTopology = false
            case .isolatedPointAndLoop:
                matchesTopology = abs(lowerAngle) <= tolerance.angle
                    && abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle
            case let .nodeIntervals(intervals):
                matchesTopology = intervals.contains { interval in
                    abs(interval.lowerBound - lowerAngle) <= tolerance.angle
                        && abs(interval.upperBound - upperAngle) <= tolerance.angle
                }
            }
            guard matchesTopology else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "An apex-reduced cone-cone component must cover one complete non-apex root interval."
                )
            }
        }

        let reproducedBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
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
                message: "A cone-cone curve exceeded its certified geometric residual."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let referenceProjection = try referenceSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let parameterizedProjection = try parameterizedSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            guard max(referenceProjection.residual, parameterizedProjection.residual)
                    <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(referenceProjection.residual, parameterizedProjection.residual),
                    tolerance: tolerance,
                    message: "A cone-cone curve failed its algebraic reconstruction check."
                )
            }
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
        let geometry = try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative,
            secondDerivative: geometry.secondDerivative
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        ).thirdDerivative
    }

    private func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> ThirdOrderDifferentialGeometry {
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let angle = coordinates.angle
        let slant = coordinates.slant
        let direction = configuration.direction(at: angle.value)
        let directionFirst = configuration.directionFirstDerivative(at: angle.value)
            * angle.first
        let directionSecond = configuration.directionSecondDerivative(at: angle.value)
            * (angle.first * angle.first)
            + configuration.directionFirstDerivative(at: angle.value) * angle.second
        let directionThird = configuration.directionThirdDerivative(at: angle.value)
                * (angle.first * angle.first * angle.first)
            + configuration.directionSecondDerivative(at: angle.value)
                * (3.0 * angle.first * angle.second)
            + configuration.directionFirstDerivative(at: angle.value) * angle.third
        let position = configuration.parameterized.apex + direction * slant.value
        let firstDerivative = directionFirst * slant.value
            + direction * slant.first
        let secondDerivative = directionSecond * slant.value
            + directionFirst * (2.0 * slant.first)
            + direction * slant.second
        let thirdDerivative = directionThird * slant.value
            + directionSecond * (3.0 * slant.first)
            + directionFirst * (3.0 * slant.second)
            + direction * slant.third
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified cone-cone component has a singular differential."
            )
        }
        guard thirdDerivative.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A certified cone-cone third differential exceeded finite arithmetic."
            )
        }
        return ThirdOrderDifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            thirdDerivative: thirdDerivative
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        guard Self.isEquivalent(surface, to: referenceSurface)
                || Self.isEquivalent(surface, to: parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-cone pcurve was requested on an unrelated surface."
            )
        }
        if Self.isEquivalent(surface, to: parameterizedSurface) {
            let configuration = try Self.makeConfiguration(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            )
            return try parameterizedParameterDifferential(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            ).parameter
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

    fileprivate func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        guard Self.isEquivalent(surface, to: referenceSurface)
                || Self.isEquivalent(surface, to: parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A prepared cone-cone pcurve was requested on an unrelated surface."
            )
        }
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let point = configuration.parameterized.apex
            + configuration.direction(at: coordinates.angle.value)
                * coordinates.slant.value
        let result: SurfaceParameter
        if Self.isEquivalent(surface, to: parameterizedSurface) {
            result = SurfaceParameter(
                u: coordinates.angle.value,
                v: coordinates.slant.value
            )
        } else {
            let projection = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            result = SurfaceParameter(u: projection.u, v: projection.v)
        }
        let reconstructed = try surface.point(
            u: result.u,
            v: result.v,
            tolerance: tolerance
        )
        let residual = (reconstructed - point).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A prepared cone-cone pcurve failed exact point reconstruction."
            )
        }
        return result
    }

    fileprivate func parameterizedParameterDifferential(
        atNormalizedFraction fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ParameterDifferentialThroughThirdOrder {
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        return ParameterDifferentialThroughThirdOrder(
            parameter: SurfaceParameter(
                u: coordinates.angle.value,
                v: coordinates.slant.value
            ),
            firstDerivative: Point2D(
                x: coordinates.angle.first,
                y: coordinates.slant.first
            ),
            secondDerivative: Point2D(
                x: coordinates.angle.second,
                y: coordinates.slant.second
            ),
            thirdDerivative: Point2D(
                x: coordinates.angle.third,
                y: coordinates.slant.third
            )
        )
    }

    fileprivate func referenceParameterAndFirstDerivative(
        atNormalizedFraction fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> (parameter: SurfaceParameter, firstDerivative: Point2D) {
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        )
        let angle = coordinates.angle
        let slant = coordinates.slant
        let direction = configuration.direction(at: angle.value)
        let directionFirst = configuration.directionFirstDerivative(at: angle.value)
            * angle.first
        let offset = configuration.baseOffset + direction * slant.value
        let offsetFirst = directionFirst * slant.value
            + direction * slant.first
        let axialDistance = offset.dot(configuration.reference.axis)
        let cosine = cos(configuration.reference.halfAngle)
        guard cosine.isFinite,
              abs(cosine) > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(cosine),
                tolerance: tolerance,
                message: "A reference cone chart has a singular axial parameter projection."
            )
        }
        let signedV = axialDistance / cosine
        let radial = offset - configuration.reference.axis * axialDistance
        let axialFirst = offsetFirst.dot(configuration.reference.axis)
        let radialFirst = offsetFirst
            - configuration.reference.axis * axialFirst
        let orientedRadial = signedV >= 0.0 ? radial : -radial
        let orientedRadialFirst = signedV >= 0.0 ? radialFirst : -radialFirst
        guard orientedRadial.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: orientedRadial.length,
                tolerance: tolerance,
                message: "A root-free cone-cone branch reached the reference cone apex."
            )
        }
        let rawU = atan2(
            orientedRadial.dot(configuration.referenceBasisV),
            orientedRadial.dot(configuration.referenceBasisU)
        )
        let radialU = orientedRadial.dot(configuration.referenceBasisU)
        let radialV = orientedRadial.dot(configuration.referenceBasisV)
        let radialFirstU = orientedRadialFirst.dot(configuration.referenceBasisU)
        let radialFirstV = orientedRadialFirst.dot(configuration.referenceBasisV)
        let radialSquared = radialU * radialU + radialV * radialV
        let period = 2.0 * Double.pi
        let remainder = rawU.truncatingRemainder(dividingBy: period)
        let u = remainder >= 0.0 ? remainder : remainder + period
        return (
            SurfaceParameter(u: u, v: signedV),
            Point2D(
                x: (radialU * radialFirstV - radialV * radialFirstU)
                    / radialSquared,
                y: axialFirst / cosine
            )
        )
    }

    private func parameterizedCoordinateDifferentials(
        atNormalizedFraction fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> (angle: ScalarDifferential, slant: ScalarDifferential) {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let normalizedFraction = min(max(fraction, 0.0), 1.0)
        let angle = angleDifferential(at: normalizedFraction)
        let halfLinear = composedDifferential(
            configuration.halfLinearPolynomial,
            angle: angle
        )
        let quadratic = composedDifferential(
            configuration.quadraticPolynomial,
            angle: angle
        )
        let numerator: ScalarDifferential
        if componentKind == .apexReducedAngularInterval {
            numerator = ScalarDifferential(
                value: -2.0 * halfLinear.value,
                first: -2.0 * halfLinear.first,
                second: -2.0 * halfLinear.second,
                third: -2.0 * halfLinear.third
            )
        } else {
            let discriminant = composedDifferential(
                configuration.discriminantPolynomial,
                angle: angle
            )
            let root = try signedSquareRootDifferential(
                discriminant,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            numerator = ScalarDifferential(
                value: -halfLinear.value + root.value,
                first: -halfLinear.first + root.first,
                second: -halfLinear.second + root.second,
                third: -halfLinear.third + root.third
            )
        }
        let slant = try quotient(
            numerator,
            by: quadratic,
            configuration: configuration,
            tolerance: tolerance
        )
        guard componentKind == .apexReducedAngularInterval
                || abs(slant.value) > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(slant.value),
                tolerance: tolerance,
                message: "A certified cone-cone curve reaches a cone apex."
            )
        }
        return (angle, slant)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let minimumQuadratic = try Self.minimumAbsoluteValue(
            of: configuration.quadraticPolynomial,
            residualTolerance: Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let maximumHalfLinear = try Self.maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let maximumDiscriminant = max(
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: true,
                residualTolerance: Self.classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            0.0
        )
        let radius = (maximumHalfLinear + sqrt(maximumDiscriminant))
            / minimumQuadratic
            + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.parameterized.apex.x - radius,
                y: configuration.parameterized.apex.y - radius,
                z: configuration.parameterized.apex.z - radius
            ),
            maximum: Point3D(
                x: configuration.parameterized.apex.x + radius,
                y: configuration.parameterized.apex.y + radius,
                z: configuration.parameterized.apex.z + radius
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
                message: "Root-free cone-cone differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let classificationEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let arithmeticEnvelope = try Self.upperProduct(
            classificationEnvelope,
            32.0,
            tolerance: tolerance
        )
        let minimumDiscriminant = (
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - arithmeticEnvelope
        ).nextDown
        guard minimumDiscriminant > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone differential certificate lost its positive discriminant margin."
            )
        }
        let rootLower = sqrt(minimumDiscriminant).nextDown
        guard rootLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone square-root lower bound collapsed."
            )
        }

        let discriminant = configuration.discriminantPolynomial
        let discriminantValue = try Self.polynomialAbsoluteUpperBound(
            discriminant,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let discriminantFirst = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let discriminantSecond = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let discriminantThird = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let rootFirst = try Self.upperQuotient(
            discriminantFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootSquaredLower = (rootLower * rootLower).nextDown
        let rootCubedLower = (rootSquaredLower * rootLower).nextDown
        let rootFifthLower = (
            rootCubedLower * rootSquaredLower
        ).nextDown
        let rootSecond = try Self.upperSum(
            Self.upperQuotient(
                discriminantSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    discriminantFirst,
                    discriminantFirst,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootThird = try Self.upperSum(
            Self.upperQuotient(
                discriminantThird,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            discriminantFirst,
                            discriminantSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            discriminantFirst,
                            Self.upperProduct(
                                discriminantFirst,
                                discriminantFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )

        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearThird = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let numeratorValue = try Self.upperSum(
            halfLinearValue,
            sqrt(discriminantValue).nextUp,
            tolerance: tolerance
        )
        let numeratorFirst = try Self.upperSum(
            halfLinearFirst,
            rootFirst,
            tolerance: tolerance
        )
        let numeratorSecond = try Self.upperSum(
            halfLinearSecond,
            rootSecond,
            tolerance: tolerance
        )
        let numeratorThird = try Self.upperSum(
            halfLinearThird,
            rootThird,
            tolerance: tolerance
        )

        let quadratic = configuration.quadraticPolynomial
        let quadraticFirst = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticSecond = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticThird = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone ruling denominator lost its nonzero margin."
            )
        }
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let slantValue = try Self.upperQuotient(
            numeratorValue,
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        quadraticFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        ),
                        try Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantThird = try Self
            .quotientThirdDerivativeMagnitudeUpperBound(
                numeratorValue: numeratorValue,
                numeratorFirst: numeratorFirst,
                numeratorSecond: numeratorSecond,
                numeratorThird: numeratorThird,
                denominatorLower: denominatorLower,
                denominatorFirst: quadraticFirst,
                denominatorSecond: quadraticSecond,
                denominatorThird: quadraticThird,
                tolerance: tolerance
            )

        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let angularFirst = try Self.upperSum(
            Self.upperProduct(
                generatorDerivative,
                slantValue,
                tolerance: tolerance
            ),
            slantFirst,
            tolerance: tolerance
        )
        let angularSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    generatorDerivative,
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        2.0,
                        generatorDerivative,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            slantSecond,
            tolerance: tolerance
        )
        let angularThird = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    generatorDerivative,
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        generatorDerivative,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        generatorDerivative,
                        tolerance: tolerance
                    ),
                    slantSecond,
                    tolerance: tolerance
                ),
                slantThird,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        )
        let coarseBounds = SpatialDifferentialMagnitudeBounds(
            first: try Self.upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            ),
            second: try Self.upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            ),
            third: try Self.upperProduct(
                periodCubed,
                angularThird,
                tolerance: tolerance
            )
        )
        let piecewiseBounds = try Self.piecewiseSpatialDifferentialBounds(
            configuration: configuration,
            branchSign: componentKind == .negativeFullBranch ? -1.0 : 1.0,
            tolerance: tolerance
        ).aggregate
        guard let coarseThird = coarseBounds.third,
              let piecewiseThird = piecewiseBounds.third else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A root-free cone-cone third-derivative certificate was not produced."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: min(coarseBounds.first, piecewiseBounds.first),
            second: min(coarseBounds.second, piecewiseBounds.second),
            third: min(coarseThird, piecewiseThird)
        )
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try prepareFullBranchDifferentialBounds(
            tolerance: tolerance
        ).bounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            tolerance: tolerance
        )
    }

    func prepareFullBranchDifferentialBounds(
        tolerance: ModelingTolerance
    ) throws -> FullBranchDifferentialBoundsPreparation {
        try validate(tolerance: tolerance)
        guard componentKind == .negativeFullBranch
                || componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Local root-free cone-cone differential preparation requires a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let piecewiseBounds = try Self.piecewiseSpatialDifferentialBounds(
            configuration: configuration,
            branchSign: componentKind == .negativeFullBranch ? -1.0 : 1.0,
            tolerance: tolerance
        )
        let referenceChart = try prepareReferenceChart(
            configuration: configuration,
            cells: piecewiseBounds.cells,
            tolerance: tolerance
        )
        return FullBranchDifferentialBoundsPreparation(
            curve: self,
            configuration: configuration,
            cells: piecewiseBounds.cells,
            referenceChart: referenceChart
        )
    }

    private func prepareReferenceChart(
        configuration: Configuration,
        cells: [FullBranchDifferentialBoundsPreparation.Cell],
        tolerance: ModelingTolerance
    ) throws -> FullBranchDifferentialBoundsPreparation.ReferenceChart {
        guard cells.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A root-free cone-cone reference chart requires proof cells."
            )
        }
        let count = cells.count
        let inverseCount = 1.0 / Double(count)
        let sine = abs(sin(configuration.reference.halfAngle)).nextDown
        guard sine.isFinite, sine > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: sine,
                tolerance: tolerance,
                message: "A root-free cone-cone reference chart has a singular radial scale."
            )
        }
        var maximumUVariations: [Double] = []
        maximumUVariations.reserveCapacity(count)
        for index in 0..<count {
            let middleFraction = (Double(index) + 0.5) * inverseCount
            let middle = try parameter(
                on: referenceSurface,
                atNormalizedFraction: middleFraction,
                configuration: configuration,
                tolerance: tolerance
            )
            let maximumVChange = (
                cells[index].spatial.first * inverseCount * 0.5
            ).nextUp
            let arithmeticEnvelope = (
                Double.ulpOfOne * max(abs(middle.v), maximumVChange, 1.0)
                    * 16_384.0
            ).nextUp
            let minimumAbsoluteV = max(
                0.0,
                (abs(middle.v) - maximumVChange - arithmeticEnvelope).nextDown
            )
            let minimumRadialScale = (minimumAbsoluteV * sine).nextDown
            guard minimumRadialScale.isFinite,
                  minimumRadialScale > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: minimumRadialScale,
                    tolerance: tolerance,
                    message: "A root-free cone-cone reference chart cell reaches the cone apex."
                )
            }
            let variation = (
                cells[index].spatial.first / minimumRadialScale * inverseCount
            ).nextUp
            guard variation.isFinite, variation < Double.pi else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: variation,
                    tolerance: tolerance,
                    message: "A root-free cone-cone reference chart cell cannot uniquely certify its periodic lift."
                )
            }
            maximumUVariations.append(variation)
        }

        let period = 2.0 * Double.pi
        let first = try parameter(
            on: referenceSurface,
            atNormalizedFraction: 0.0,
            configuration: configuration,
            tolerance: tolerance
        ).u
        var uNodes = [first]
        uNodes.reserveCapacity(count + 1)
        for index in 1...count {
            let principal = try parameter(
                on: referenceSurface,
                atNormalizedFraction: Double(index) * inverseCount,
                configuration: configuration,
                tolerance: tolerance
            ).u
            let previous = uNodes[index - 1]
            let turn = round((previous - principal) / period)
            let lifted = principal + turn * period
            let arithmeticEnvelope = (
                Double.ulpOfOne * max(abs(previous), abs(lifted), 1.0)
                    * 16_384.0
            ).nextUp
            guard abs(lifted - previous)
                    <= maximumUVariations[index - 1] + arithmeticEnvelope else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    residual: abs(lifted - previous),
                    tolerance: tolerance,
                    message: "A root-free cone-cone reference chart failed certified periodic unwrapping."
                )
            }
            uNodes.append(lifted)
        }
        return FullBranchDifferentialBoundsPreparation.ReferenceChart(
            uNodes: uNodes,
            maximumUVariations: maximumUVariations
        )
    }

    func apexReducedBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .apexReducedAngularInterval else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Apex-reduced cone-cone differential bounds require an apex graph loop."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let classificationEnvelope = Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let halfLinearThird = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirstByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticSecondByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let quadraticThirdByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        )
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            ) - Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "An apex-reduced cone-cone ruling denominator lost its nonzero margin."
            )
        }
        let span = (upperAngle - lowerAngle).nextUp
        let spanSquared = try Self.upperProduct(
            span,
            span,
            tolerance: tolerance
        )
        let spanCubed = try Self.upperProduct(
            spanSquared,
            span,
            tolerance: tolerance
        )
        let numeratorValue = try Self.upperProduct(
            2.0,
            halfLinearValue,
            tolerance: tolerance
        )
        let numeratorFirst = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearFirst,
                tolerance: tolerance
            ),
            span,
            tolerance: tolerance
        )
        let numeratorSecond = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearSecond,
                tolerance: tolerance
            ),
            spanSquared,
            tolerance: tolerance
        )
        let numeratorThird = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearThird,
                tolerance: tolerance
            ),
            spanCubed,
            tolerance: tolerance
        )
        let quadraticFirst = try Self.upperProduct(
            quadraticFirstByAngle,
            span,
            tolerance: tolerance
        )
        let quadraticSecond = try Self.upperProduct(
            quadraticSecondByAngle,
            spanSquared,
            tolerance: tolerance
        )
        let quadraticThird = try Self.upperProduct(
            quadraticThirdByAngle,
            spanCubed,
            tolerance: tolerance
        )
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let slantValue = try Self.upperQuotient(
            numeratorValue,
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        quadraticFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantThird = try Self
            .quotientThirdDerivativeMagnitudeUpperBound(
                numeratorValue: numeratorValue,
                numeratorFirst: numeratorFirst,
                numeratorSecond: numeratorSecond,
                numeratorThird: numeratorThird,
                denominatorLower: denominatorLower,
                denominatorFirst: quadraticFirst,
                denominatorSecond: quadraticSecond,
                denominatorThird: quadraticThird,
                tolerance: tolerance
            )
        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let first = try Self.upperSum(
            Self.upperProduct(
                try Self.upperProduct(
                    generatorDerivative,
                    span,
                    tolerance: tolerance
                ),
                slantValue,
                tolerance: tolerance
            ),
            slantFirst,
            tolerance: tolerance
        )
        let second = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    try Self.upperProduct(
                        generatorDerivative,
                        spanSquared,
                        tolerance: tolerance
                    ),
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            generatorDerivative,
                            tolerance: tolerance
                        ),
                        span,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            slantSecond,
            tolerance: tolerance
        )
        let directionFirst = try Self.upperProduct(
            generatorDerivative,
            span,
            tolerance: tolerance
        )
        let directionSecond = try Self.upperProduct(
            generatorDerivative,
            spanSquared,
            tolerance: tolerance
        )
        let directionThird = try Self.upperProduct(
            generatorDerivative,
            spanCubed,
            tolerance: tolerance
        )
        let third = try Self.upperSum(
            Self.upperSum(
                Self.upperProduct(
                    directionThird,
                    slantValue,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        directionSecond,
                        tolerance: tolerance
                    ),
                    slantFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        directionFirst,
                        tolerance: tolerance
                    ),
                    slantSecond,
                    tolerance: tolerance
                ),
                slantThird,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard componentKind == .boundedAngularInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded cone-cone differential bounds require a valid complete simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        )
        let discriminant = configuration.discriminantPolynomial
        let discriminantFirst = discriminant.derivativePolynomial
        let discriminantSecond = discriminantFirst.derivativePolynomial
        let discriminantThird = discriminantSecond.derivativePolynomial
        let discriminantFourth = discriminantThird.derivativePolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 131_072.0
        ).nextUp
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        )
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        )
        let phaseLower = period * lower
        let phaseUpper = period * upper
        let angleRange = Self.boundedAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        )
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: angleRange.lower,
            requestedUpper: angleRange.upper,
            lowerValue: discriminant.value(at: lowerAngle),
            upperValue: discriminant.value(at: upperAngle),
            lowerDerivative: discriminant.firstDerivative(at: lowerAngle),
            upperDerivative: discriminant.firstDerivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                discriminantFirst.absoluteCoefficientSum.nextUp,
            secondDerivativeMagnitudeUpperBound:
                discriminantSecond.absoluteCoefficientSum.nextUp,
            thirdDerivativeMagnitudeUpperBound:
                discriminantThird.absoluteCoefficientSum.nextUp,
            fourthDerivativeMagnitudeUpperBound:
                discriminantFourth.absoluteCoefficientSum.nextUp,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper in
                try Self.restrictedPolynomialRange(
                    discriminant,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope,
                    tolerance: tolerance
                )
            },
            tolerance: tolerance,
            label: "Cone-cone bounded branch"
        )
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded cone-cone regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try Self.upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        )
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootFifthLower = (rootCubedLower * factor.lower).nextDown
        let rootSecondByAngle = try Self.upperSum(
            Self.upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                ),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootThirdByAngle = try Self.upperSum(
            Self.upperQuotient(
                factor.third,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            factor.first,
                            factor.second,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            factor.first,
                            Self.upperProduct(
                                factor.first,
                                factor.first,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
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
        let angleFirst = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                period,
                tolerance: tolerance
            ),
            sineMagnitude,
            tolerance: tolerance
        )
        let angleSecond = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                periodSquared,
                tolerance: tolerance
            ),
            cosineMagnitude,
            tolerance: tolerance
        )
        let angleThird = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                periodCubed,
                tolerance: tolerance
            ),
            sineMagnitude,
            tolerance: tolerance
        )
        let rootFirstByFraction = try Self.upperProduct(
            rootFirstByAngle,
            angleFirst,
            tolerance: tolerance
        )
        let rootSecondByFraction = try Self.upperSum(
            Self.upperProduct(
                rootSecondByAngle,
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                rootFirstByAngle,
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootThirdByFraction = try Self.upperSum(
            Self.upperProduct(
                rootThirdByAngle,
                Self.upperProduct(
                    angleFirst,
                    Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        rootSecondByAngle,
                        Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    rootFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootMagnitude = try Self.upperProduct(
            Self.upperProduct(
                halfSpan,
                sineMagnitude,
                tolerance: tolerance
            ),
            rootUpper,
            tolerance: tolerance
        )
        let signedRootFirst = try Self.upperProduct(
            halfSpan,
            Self.upperSum(
                Self.upperProduct(
                    Self.upperProduct(
                        period,
                        cosineMagnitude,
                        tolerance: tolerance
                    ),
                    rootUpper,
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    Self.upperProduct(
                        sineMagnitude,
                        rootFirstByAngle,
                        tolerance: tolerance
                    ),
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootSecond = try Self.upperProduct(
            halfSpan,
            Self.upperSum(
                Self.upperProduct(
                    Self.upperProduct(
                        periodSquared,
                        sineMagnitude,
                        tolerance: tolerance
                    ),
                    rootUpper,
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        Self.upperProduct(
                            Self.upperProduct(
                                2.0,
                                period,
                                tolerance: tolerance
                            ),
                            cosineMagnitude,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            rootFirstByAngle,
                            angleFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    Self.upperProduct(
                        sineMagnitude,
                        Self.upperSum(
                            Self.upperProduct(
                                rootSecondByAngle,
                                Self.upperProduct(
                                    angleFirst,
                                    angleFirst,
                                    tolerance: tolerance
                                ),
                                tolerance: tolerance
                            ),
                            Self.upperProduct(
                                rootFirstByAngle,
                                angleSecond,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let signedRootThird = try Self.upperProduct(
            halfSpan,
            Self.upperSum(
                Self.upperProduct(
                    Self.upperProduct(
                        periodCubed,
                        cosineMagnitude,
                        tolerance: tolerance
                    ),
                    rootUpper,
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            Self.upperProduct(
                                periodSquared,
                                sineMagnitude,
                                tolerance: tolerance
                            ),
                            rootFirstByFraction,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    Self.upperSum(
                        Self.upperProduct(
                            3.0,
                            Self.upperProduct(
                                Self.upperProduct(
                                    period,
                                    cosineMagnitude,
                                    tolerance: tolerance
                                ),
                                rootSecondByFraction,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            sineMagnitude,
                            rootThirdByFraction,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearFirstByAngle = halfLinear.derivativePolynomial
            .absoluteCoefficientSum.nextUp
        let halfLinearSecondByAngle = halfLinear.derivativePolynomial
            .derivativePolynomial.absoluteCoefficientSum.nextUp
        let halfLinearThirdByAngle = halfLinear.derivativePolynomial
            .derivativePolynomial.derivativePolynomial
            .absoluteCoefficientSum.nextUp
        let halfLinearMagnitude = halfLinear.absoluteCoefficientSum.nextUp
        let halfLinearFirst = try Self.upperProduct(
            halfLinearFirstByAngle,
            angleFirst,
            tolerance: tolerance
        )
        let halfLinearSecond = try Self.upperSum(
            Self.upperProduct(
                halfLinearSecondByAngle,
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                halfLinearFirstByAngle,
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let halfLinearThird = try Self.upperSum(
            Self.upperProduct(
                halfLinearThirdByAngle,
                Self.upperProduct(
                    angleFirst,
                    Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        halfLinearSecondByAngle,
                        Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    halfLinearFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let numeratorMagnitude = try Self.upperSum(
            halfLinearMagnitude,
            signedRootMagnitude,
            tolerance: tolerance
        )
        let numeratorFirst = try Self.upperSum(
            halfLinearFirst,
            signedRootFirst,
            tolerance: tolerance
        )
        let numeratorSecond = try Self.upperSum(
            halfLinearSecond,
            signedRootSecond,
            tolerance: tolerance
        )
        let numeratorThird = try Self.upperSum(
            halfLinearThird,
            signedRootThird,
            tolerance: tolerance
        )
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirstByAngle = quadratic.derivativePolynomial
            .absoluteCoefficientSum.nextUp
        let quadraticSecondByAngle = quadratic.derivativePolynomial
            .derivativePolynomial.absoluteCoefficientSum.nextUp
        let quadraticThirdByAngle = quadratic.derivativePolynomial
            .derivativePolynomial.derivativePolynomial
            .absoluteCoefficientSum.nextUp
        let quadraticFirst = try Self.upperProduct(
            quadraticFirstByAngle,
            angleFirst,
            tolerance: tolerance
        )
        let quadraticSecond = try Self.upperSum(
            Self.upperProduct(
                quadraticSecondByAngle,
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperProduct(
                quadraticFirstByAngle,
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let quadraticThird = try Self.upperSum(
            Self.upperProduct(
                quadraticThirdByAngle,
                Self.upperProduct(
                    angleFirst,
                    Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperProduct(
                    3.0,
                    Self.upperProduct(
                        quadraticSecondByAngle,
                        Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperProduct(
                    quadraticFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: Self.classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ) - Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A bounded cone-cone ruling denominator lost its nonzero margin."
            )
        }
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let slantMagnitude = try Self.upperQuotient(
            numeratorMagnitude,
            denominatorLower,
            tolerance: tolerance
        )
        let slantFirst = try Self.upperSum(
            Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            ),
            Self.upperQuotient(
                Self.upperProduct(
                    numeratorMagnitude,
                    quadraticFirst,
                    tolerance: tolerance
                ),
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantSecond = try Self.upperSum(
            Self.upperSum(
                Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        numeratorMagnitude,
                        quadraticSecond,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            Self.upperSum(
                Self.upperQuotient(
                    Self.upperProduct(
                        Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        ),
                        quadraticFirst,
                        tolerance: tolerance
                    ),
                    denominatorSquaredLower,
                    tolerance: tolerance
                ),
                Self.upperQuotient(
                    Self.upperProduct(
                        Self.upperProduct(
                            2.0,
                            numeratorMagnitude,
                            tolerance: tolerance
                        ),
                        Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let slantThird = try Self
            .quotientThirdDerivativeMagnitudeUpperBound(
                numeratorValue: numeratorMagnitude,
                numeratorFirst: numeratorFirst,
                numeratorSecond: numeratorSecond,
                numeratorThird: numeratorThird,
                denominatorLower: denominatorLower,
                denominatorFirst: quadraticFirst,
                denominatorSecond: quadraticSecond,
                denominatorThird: quadraticThird,
                tolerance: tolerance
            )
        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let directionFirst = try Self.upperProduct(
            generatorDerivative,
            angleFirst,
            tolerance: tolerance
        )
        let directionSecond = try Self.upperProduct(
            generatorDerivative,
            Self.upperSum(
                Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                ),
                angleSecond,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let directionThird = try Self.upperProduct(
            generatorDerivative,
            Self.upperSum(
                Self.upperProduct(
                    angleFirst,
                    Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        3.0,
                        Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    angleThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return SpatialDifferentialMagnitudeBounds(
            first: try Self.upperSum(
                Self.upperProduct(
                    directionFirst,
                    slantMagnitude,
                    tolerance: tolerance
                ),
                slantFirst,
                tolerance: tolerance
            ),
            second: try Self.upperSum(
                Self.upperSum(
                    Self.upperProduct(
                        directionSecond,
                        slantMagnitude,
                        tolerance: tolerance
                    ),
                    Self.upperProduct(
                        Self.upperProduct(
                            2.0,
                            directionFirst,
                            tolerance: tolerance
                        ),
                        slantFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                slantSecond,
                tolerance: tolerance
            ),
            third: try Self.upperSum(
                Self.upperSum(
                    Self.upperProduct(
                        directionThird,
                        slantMagnitude,
                        tolerance: tolerance
                    ),
                    Self.upperProduct(
                        Self.upperProduct(
                            3.0,
                            directionSecond,
                            tolerance: tolerance
                        ),
                        slantFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                Self.upperSum(
                    Self.upperProduct(
                        Self.upperProduct(
                            3.0,
                            directionFirst,
                            tolerance: tolerance
                        ),
                        slantSecond,
                        tolerance: tolerance
                    ),
                    slantThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        )
    }

    private func angleDifferential(at fraction: Double) -> ScalarDifferential {
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return ScalarDifferential(
                value: period * fraction,
                first: period,
                second: 0.0,
                third: 0.0
            )
        case .boundedAngularInterval:
            let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            let phase = period * fraction
            return ScalarDifferential(
                value: midpoint - halfSpan * cos(phase),
                first: halfSpan * period * sin(phase),
                second: halfSpan * period * period * cos(phase),
                third: -halfSpan * period * period * period * sin(phase)
            )
        case .apexReducedAngularInterval:
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * fraction,
                first: span,
                second: 0.0,
                third: 0.0
            )
        }
    }

    private func composedDifferential(
        _ polynomial: TrigonometricPolynomial,
        angle: ScalarDifferential
    ) -> ScalarDifferential {
        let angularFirst = polynomial.firstDerivative(at: angle.value)
        let angularSecond = polynomial.secondDerivative(at: angle.value)
        return ScalarDifferential(
            value: polynomial.value(at: angle.value),
            first: angularFirst * angle.first,
            second: angularSecond
                * angle.first * angle.first
                + angularFirst * angle.second,
            third: polynomial.thirdDerivative(at: angle.value)
                    * angle.first * angle.first * angle.first
                + 3.0 * angularSecond * angle.first * angle.second
                + angularFirst * angle.third
        )
    }

    private func signedSquareRootDifferential(
        _ discriminant: ScalarDifferential,
        fraction: Double,
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
        case .boundedAngularInterval:
            branchSign = sin(2.0 * Double.pi * fraction) < 0.0 ? -1.0 : 1.0
        case .apexReducedAngularInterval:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An apex-reduced cone-cone curve does not use a square-root branch."
            )
        }
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedDiscriminantFactorDifferential(
                at: angleDifferential(at: fraction).value,
                configuration: configuration,
                tolerance: tolerance
            )
            guard factor.value > 0.0, factor.value.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "A bounded cone-cone component lost its positive regularized discriminant factor."
                )
            }
            let root = sqrt(factor.value)
            let rootByAngle = ScalarDifferential(
                value: root,
                first: factor.first / (2.0 * root),
                second: factor.second / (2.0 * root)
                    - factor.first * factor.first
                        / (4.0 * root * root * root),
                third: factor.third / (2.0 * root)
                    - 3.0 * factor.first * factor.second
                        / (4.0 * root * root * root)
                    + 3.0 * factor.first * factor.first * factor.first
                        / (8.0 * pow(root, 5.0))
            )
            let angle = angleDifferential(at: fraction)
            let rootByFraction = ScalarDifferential(
                value: rootByAngle.value,
                first: rootByAngle.first * angle.first,
                second: rootByAngle.second * angle.first * angle.first
                    + rootByAngle.first * angle.second,
                third: rootByAngle.third
                        * angle.first * angle.first * angle.first
                    + 3.0 * rootByAngle.second * angle.first * angle.second
                    + rootByAngle.first * angle.third
            )
            let period = 2.0 * Double.pi
            let phase = period * fraction
            let sine = ScalarDifferential(
                value: sin(phase),
                first: period * cos(phase),
                second: -period * period * sin(phase),
                third: -period * period * period * cos(phase)
            )
            let result = Self.product(sine, rootByFraction).scaled(
                by: (upperAngle - lowerAngle) * 0.5
            )
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded cone-cone regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        guard discriminant.value >= -classificationTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -discriminant.value,
                tolerance: tolerance,
                message: "A cone-cone evaluator left its certified non-negative discriminant interval."
            )
        }
        let magnitude = sqrt(max(discriminant.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A cone-cone square-root differential is singular."
            )
        }
        let signedValue = branchSign * magnitude
        return ScalarDifferential(
            value: signedValue,
            first: discriminant.first / (2.0 * signedValue),
            second: discriminant.second / (2.0 * signedValue)
                - discriminant.first * discriminant.first
                    / (4.0 * signedValue * signedValue * signedValue),
            third: discriminant.third / (2.0 * signedValue)
                - 3.0 * discriminant.first * discriminant.second
                    / (4.0 * signedValue * signedValue * signedValue)
                + 3.0 * discriminant.first * discriminant.first
                    * discriminant.first / (8.0 * pow(signedValue, 5.0))
        )
    }

    private func regularizedDiscriminantFactorDifferential(
        at angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let span = upperAngle - lowerAngle
        let lowerDistance = angle - lowerAngle
        let upperDistance = upperAngle - angle
        guard span > tolerance.angle,
              lowerDistance >= -tolerance.angle,
              upperDistance >= -tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: min(lowerDistance, upperDistance),
                tolerance: tolerance,
                message: "A bounded cone-cone regularized factor was evaluated outside its certified angular component."
            )
        }
        let discriminant = configuration.discriminantPolynomial
        let lowerValue = discriminant.value(at: lowerAngle)
        let upperValue = discriminant.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = Self.trigonometricDividedDifference(
            discriminant,
            value: angle,
            endpoint: endpoint
        )
        let numerator = usesLowerEndpoint
            ? dividedDifference.adding(.constant(-correctionSlope))
            : ScalarDifferential.constant(correctionSlope)
                .subtracting(dividedDifference)
        let denominator = usesLowerEndpoint
            ? ScalarDifferential(
                value: upperAngle - angle,
                first: -1.0,
                second: 0.0,
                third: 0.0
            )
            : ScalarDifferential(
                value: angle - lowerAngle,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
        return try Self.differentialQuotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded cone-cone regularized factor lost its opposite-endpoint denominator."
        )
    }

    private static func trigonometricDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ) -> ScalarDifferential {
        var result = ScalarDifferential.constant(0.0)
        for harmonic in [
            (
                order: 1.0,
                cosine: polynomial.cosine,
                sine: polynomial.sine
            ),
            (
                order: 2.0,
                cosine: polynomial.cosineDouble,
                sine: polynomial.sineDouble
            ),
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
                ),
                third: -halfOrder * halfOrder * halfOrder * (
                    -harmonic.cosine * cos(midpoint)
                        - harmonic.sine * sin(midpoint)
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
        let thirdByValue: Double
        if abs(value) <= 0.25 {
            var accumulatedValue = 0.0
            var accumulatedFirst = 0.0
            var accumulatedSecond = 0.0
            var accumulatedThird = 0.0
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
                if exponent > 2 {
                    accumulatedThird += coefficient
                        * Double(exponent * (exponent - 1) * (exponent - 2))
                        * pow(value, Double(exponent - 3))
                }
                coefficient /= -Double(
                    (2 * index + 2) * (2 * index + 3)
                )
            }
            valueResult = accumulatedValue
            firstByValue = accumulatedFirst
            secondByValue = accumulatedSecond
            thirdByValue = accumulatedThird
        } else {
            let sine = sin(value)
            let cosine = cos(value)
            let squared = value * value
            valueResult = sine / value
            firstByValue = (value * cosine - sine) / squared
            secondByValue = -sine / value
                - 2.0 * cosine / squared
                + 2.0 * sine / (squared * value)
            thirdByValue = -cosine / value
                + 3.0 * sine / squared
                + 6.0 * cosine / (squared * value)
                - 6.0 * sine / (squared * squared)
        }
        return ScalarDifferential(
            value: valueResult,
            first: firstByValue * derivativeScale,
            second: secondByValue * derivativeScale * derivativeScale,
            third: thirdByValue * derivativeScale * derivativeScale
                * derivativeScale
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
                + first.value * second.second,
            third: first.third * second.value
                + 3.0 * first.second * second.first
                + 3.0 * first.first * second.second
                + first.value * second.third
        )
    }

    private static func differentialQuotient(
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
        let inverseThird = -6.0 * denominator.first * denominator.first
                * denominator.first * pow(inverse, 4.0)
            + 6.0 * denominator.first * denominator.second
                * inverse * inverse * inverse
            - denominator.third * inverse * inverse
        return product(
            numerator,
            ScalarDifferential(
                value: inverse,
                first: inverseFirst,
                second: inverseSecond,
                third: inverseThird
            )
        )
    }

    private func quotient(
        _ numerator: ScalarDifferential,
        by denominator: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> ScalarDifferential {
        let denominatorTolerance = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
        guard abs(denominator.value) > denominatorTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(denominator.value),
                tolerance: tolerance,
                message: "A cone-cone evaluator reached an asymptotic ruling."
            )
        }
        let inverse = 1.0 / denominator.value
        let value = numerator.value * inverse
        let first = numerator.first * inverse
            - numerator.value * denominator.first * inverse * inverse
        let second = numerator.second * inverse
            - numerator.value * denominator.second * inverse * inverse
            - 2.0 * numerator.first * denominator.first * inverse * inverse
            + 2.0 * numerator.value * denominator.first * denominator.first
                * inverse * inverse * inverse
        let third = numerator.third * inverse
            - 3.0 * numerator.second * denominator.first
                * inverse * inverse
            + 6.0 * numerator.first * denominator.first
                * denominator.first * inverse * inverse * inverse
            - 3.0 * numerator.first * denominator.second
                * inverse * inverse
            - 6.0 * numerator.value * denominator.first
                * denominator.first * denominator.first * pow(inverse, 4.0)
            + 6.0 * numerator.value * denominator.first
                * denominator.second * inverse * inverse * inverse
            - numerator.value * denominator.third * inverse * inverse
        return ScalarDifferential(
            value: value,
            first: first,
            second: second,
            third: third
        )
    }

    private static func makeConfiguration(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        try referenceSurface.validate(tolerance: tolerance)
        try parameterizedSurface.validate(tolerance: tolerance)
        guard case let .cone(referenceCanonical) = CanonicalAnalyticSurface(referenceSurface),
              case let .cone(parameterizedCanonical) = CanonicalAnalyticSurface(parameterizedSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified cone-cone curve requires two exact cone surfaces."
            )
        }
        let reference = try canonicalCone(referenceCanonical, tolerance: tolerance)
        let parameterized = try canonicalCone(parameterizedCanonical, tolerance: tolerance)
        let basis = try analyticOrthonormalBasis(
            parameterized.axis,
            tolerance: tolerance
        )
        let referenceBasis = try analyticOrthonormalBasis(
            reference.axis,
            tolerance: tolerance
        )
        let baseOffset = parameterized.apex - reference.apex
        let metricScale = 1.0 / pow(cos(reference.halfAngle), 2.0)
        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - metricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }
        func direction(at angle: Double) -> Vector3D {
            parameterized.axis * cos(parameterized.halfAngle)
                + (basis.u * cos(angle) + basis.v * sin(angle))
                    * sin(parameterized.halfAngle)
        }
        let constant = metric(baseOffset, baseOffset)
        let halfLinear = trigonometricPolynomial { angle in
            metric(baseOffset, direction(at: angle))
        }
        let quadratic = trigonometricPolynomial { angle in
            let generator = direction(at: angle)
            return metric(generator, generator)
        }
        let discriminant = trigonometricPolynomial { angle in
            let generator = direction(at: angle)
            let linear = metric(baseOffset, generator)
            return linear * linear - metric(generator, generator) * constant
        }
        return Configuration(
            reference: reference,
            parameterized: parameterized,
            referenceBasisU: referenceBasis.u,
            referenceBasisV: referenceBasis.v,
            parameterizedBasisU: basis.u,
            parameterizedBasisV: basis.v,
            baseOffset: baseOffset,
            referenceMetricScale: metricScale,
            constantTerm: constant,
            halfLinearPolynomial: halfLinear,
            quadraticPolynomial: quadratic,
            discriminantPolynomial: discriminant
        )
    }

    private static func canonicalCone(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ) throws -> Cone {
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Cone(apex: cone.apex, axis: axis, halfAngle: cone.halfAngle)
    }

    private static func trigonometricPolynomial(
        valueAt: (Double) -> Double
    ) -> TrigonometricPolynomial {
        let zero = valueAt(0.0)
        let half = valueAt(Double.pi)
        let quarter = valueAt(Double.pi * 0.5)
        let threeQuarter = valueAt(Double.pi * 1.5)
        let diagonal = valueAt(Double.pi * 0.25)
        let constantPlusDouble = (zero + half) * 0.5
        let constantMinusDouble = (quarter + threeQuarter) * 0.5
        let constant = (constantPlusDouble + constantMinusDouble) * 0.5
        let cosineDouble = (constantPlusDouble - constantMinusDouble) * 0.5
        let cosine = (zero - half) * 0.5
        let sine = (quarter - threeQuarter) * 0.5
        let sineDouble = diagonal
            - constant
            - (cosine + sine) / sqrt(2.0)
        return TrigonometricPolynomial(
            constant: constant,
            cosine: cosine,
            sine: sine,
            cosineDouble: cosineDouble,
            sineDouble: sineDouble
        )
    }

    private static func roots(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let normalizedResidual = max(
            Double.ulpOfOne * 1_024.0,
            residualTolerance / polynomial.coefficientScale
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 0.25, Double.ulpOfOne * 1_024.0),
            residualTolerance: normalizedResidual,
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        var values = try solver.realRoots(
            coefficients: polynomial.tangentHalfAngleCoefficients
        ).map { normalizedAngle(2.0 * atan($0)) }
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            values.append(Double.pi)
        }
        values = values.map { value in
            refinedAngle(
                value,
                polynomial: polynomial,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )
        }.filter { value in
            abs(polynomial.value(at: value)) <= residualTolerance * 16.0
        }.sorted()
        var result: [Double] = []
        for value in values where
            result.last.map({ angularDistance($0, value) <= tolerance.angle }) != true {
            result.append(value)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           angularDistance(first, last) <= tolerance.angle {
            result.removeLast()
        }
        return result
    }

    private static func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let values = ([0.0] + (try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        ))).map(polynomial.value)
        return maximum
            ? values.max() ?? polynomial.value(at: 0.0)
            : values.min() ?? polynomial.value(at: 0.0)
    }

    private static func maximumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        max(
            abs(try extremum(
                of: polynomial,
                maximum: false,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )),
            abs(try extremum(
                of: polynomial,
                maximum: true,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            ))
        )
    }

    private static func minimumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let minimum = try extremum(
            of: polynomial,
            maximum: false,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        let maximum = try extremum(
            of: polynomial,
            maximum: true,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        guard minimum > 0.0 || maximum < 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: min(abs(minimum), abs(maximum)),
                tolerance: tolerance,
                message: "A cone-cone parameterization crosses an asymptotic ruling."
            )
        }
        return min(abs(minimum), abs(maximum))
    }

    private static func validIntervals(
        boundaries: [Double],
        polynomial: TrigonometricPolynomial,
        classificationTolerance: Double
    ) -> [(lower: Double, upper: Double)] {
        guard boundaries.isEmpty == false else { return [] }
        return boundaries.indices.compactMap { index in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return polynomial.value(at: lower + (upper - lower) * 0.5)
                > classificationTolerance
                ? (lower, upper)
                : nil
        }
    }

    private static func boundedAngleRange(
        phaseLower: Double,
        phaseUpper: Double,
        lowerAngle: Double,
        upperAngle: Double
    ) -> (lower: Double, upper: Double) {
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
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
            (values.min() ?? lowerAngle).nextDown,
            (values.max() ?? upperAngle).nextUp
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
            }
        }
        return result.nextUp
    }

    private static func residualUpperBound(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0
        if componentKind == .apexReducedAngularInterval {
            let result = apexReductionResidualUpperBound(
                configuration: configuration
            ) + machineBound
            guard result <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result,
                    tolerance: tolerance,
                    message: "Cone-cone apex reduction does not certify the requested geometric tolerance."
                )
            }
            return result
        }
        guard componentKind == .boundedAngularInterval else {
            return machineBound
        }
        let minimumQuadratic = try minimumAbsoluteValue(
            of: configuration.quadraticPolynomial,
            residualTolerance: classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let rootResidual = max(
            abs(configuration.discriminantPolynomial.value(at: lowerAngle)),
            abs(configuration.discriminantPolynomial.value(at: upperAngle))
        )
        let endpointClosureBound = sqrt(rootResidual / minimumQuadratic)
        let result = endpointClosureBound + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Cone-cone boundary roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }

    private static func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = configuration.characteristicLength
        let algebraicScale = max(
            configuration.discriminantPolynomial.coefficientScale,
            scale * scale
        )
        return max(
            Double.ulpOfOne * algebraicScale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private static func quadraticTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.angle * 8.0,
            Double.ulpOfOne
                * configuration.quadraticPolynomial.coefficientScale
                * 2_048.0
        )
    }

    private static func piecewiseSpatialDifferentialBounds(
        configuration: Configuration,
        branchSign: Double,
        tolerance: ModelingTolerance
    ) throws -> PiecewiseDifferentialBounds {
        let cellCount = 1_024
        let period = 2.0 * Double.pi
        let discriminant = configuration.discriminantPolynomial
        let discriminantFirst = discriminant.derivativePolynomial
        let discriminantSecond = discriminantFirst.derivativePolynomial
        let discriminantThird = discriminantSecond.derivativePolynomial
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearFirst = halfLinear.derivativePolynomial
        let halfLinearSecond = halfLinearFirst.derivativePolynomial
        let halfLinearThird = halfLinearSecond.derivativePolynomial
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirst = quadratic.derivativePolynomial
        let quadraticSecond = quadraticFirst.derivativePolynomial
        let quadraticThird = quadraticSecond.derivativePolynomial
        var maximumAngularFirst = 0.0
        var maximumAngularSecond = 0.0
        var maximumAngularThird = 0.0
        var angularCells: [FullBranchDifferentialBoundsPreparation.Cell] = []
        angularCells.reserveCapacity(cellCount)

        for index in 0..<cellCount {
            let lower = period * Double(index) / Double(cellCount)
            let upper = period * Double(index + 1) / Double(cellCount)
            let discriminantRange = try polynomialRange(
                discriminant,
                derivativeBound: discriminantFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            guard discriminantRange.lower > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A root-free cone-cone interval lost its positive discriminant margin."
                )
            }
            let root = CertifiedInterval(
                lower: sqrt(discriminantRange.lower).nextDown,
                upper: sqrt(discriminantRange.upper).nextUp
            )
            let discriminantFirstRange = try polynomialRange(
                discriminantFirst,
                derivativeBound: discriminantSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let discriminantSecondRange = try polynomialRange(
                discriminantSecond,
                derivativeBound: discriminantThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let discriminantThirdRange = try polynomialRange(
                discriminantThird,
                derivativeBound: discriminantThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let rootFirst = try divided(
                discriminantFirstRange,
                by: scaled(root, by: 2.0, tolerance: tolerance),
                tolerance: tolerance
            )
            let rootSecond = try subtracting(
                divided(
                    discriminantSecondRange,
                    by: scaled(root, by: 2.0, tolerance: tolerance),
                    tolerance: tolerance
                ),
                divided(
                    multiplied(
                        discriminantFirstRange,
                        discriminantFirstRange,
                        tolerance: tolerance
                    ),
                    by: scaled(
                        multiplied(
                            multiplied(root, root, tolerance: tolerance),
                            root,
                            tolerance: tolerance
                        ),
                        by: 4.0,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            let rootSquared = try multiplied(
                root,
                root,
                tolerance: tolerance
            )
            let rootCubed = try multiplied(
                rootSquared,
                root,
                tolerance: tolerance
            )
            let rootFifth = try multiplied(
                rootCubed,
                rootSquared,
                tolerance: tolerance
            )
            let rootThird = try adding(
                subtracting(
                    divided(
                        discriminantThirdRange,
                        by: scaled(
                            root,
                            by: 2.0,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    divided(
                        scaled(
                            multiplied(
                                discriminantFirstRange,
                                discriminantSecondRange,
                                tolerance: tolerance
                            ),
                            by: 3.0,
                            tolerance: tolerance
                        ),
                        by: scaled(
                            rootCubed,
                            by: 4.0,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                divided(
                    scaled(
                        multiplied(
                            discriminantFirstRange,
                            multiplied(
                                discriminantFirstRange,
                                discriminantFirstRange,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        by: 3.0,
                        tolerance: tolerance
                    ),
                    by: scaled(
                        rootFifth,
                        by: 8.0,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )

            let halfLinearRange = try polynomialRange(
                halfLinear,
                derivativeBound: halfLinearFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let halfLinearFirstRange = try polynomialRange(
                halfLinearFirst,
                derivativeBound: halfLinearSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let halfLinearSecondRange = try polynomialRange(
                halfLinearSecond,
                derivativeBound: halfLinearThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let halfLinearThirdRange = try polynomialRange(
                halfLinearThird,
                derivativeBound: halfLinearThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let numerator = try adding(
                scaled(halfLinearRange, by: -1.0, tolerance: tolerance),
                scaled(root, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )
            let numeratorFirst = try adding(
                scaled(halfLinearFirstRange, by: -1.0, tolerance: tolerance),
                scaled(rootFirst, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )
            let numeratorSecond = try adding(
                scaled(halfLinearSecondRange, by: -1.0, tolerance: tolerance),
                scaled(rootSecond, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )
            let numeratorThird = try adding(
                scaled(halfLinearThirdRange, by: -1.0, tolerance: tolerance),
                scaled(rootThird, by: branchSign, tolerance: tolerance),
                tolerance: tolerance
            )

            let denominator = try polynomialRange(
                quadratic,
                derivativeBound: quadraticFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let denominatorFirst = try polynomialRange(
                quadraticFirst,
                derivativeBound: quadraticSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let denominatorSecond = try polynomialRange(
                quadraticSecond,
                derivativeBound: quadraticThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            let denominatorThird = try polynomialRange(
                quadraticThird,
                derivativeBound: quadraticThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            )
            guard denominator.lower > 0.0 || denominator.upper < 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A root-free cone-cone interval lost its ruling denominator margin."
                )
            }
            let denominatorSquared = try multiplied(
                denominator,
                denominator,
                tolerance: tolerance
            )
            let denominatorCubed = try multiplied(
                denominatorSquared,
                denominator,
                tolerance: tolerance
            )
            let slant = try divided(
                numerator,
                by: denominator,
                tolerance: tolerance
            )
            let slantFirst = try subtracting(
                divided(
                    numeratorFirst,
                    by: denominator,
                    tolerance: tolerance
                ),
                divided(
                    multiplied(
                        numerator,
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    by: denominatorSquared,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            let slantSecond = try adding(
                subtracting(
                    subtracting(
                        divided(
                            numeratorSecond,
                            by: denominator,
                            tolerance: tolerance
                        ),
                        divided(
                            multiplied(
                                numerator,
                                denominatorSecond,
                                tolerance: tolerance
                            ),
                            by: denominatorSquared,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    divided(
                        scaled(
                            multiplied(
                                numeratorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            by: 2.0,
                            tolerance: tolerance
                        ),
                        by: denominatorSquared,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                divided(
                    scaled(
                        multiplied(
                            numerator,
                            multiplied(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        by: 2.0,
                        tolerance: tolerance
                    ),
                    by: denominatorCubed,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            let slantThird = try quotientThirdDerivative(
                numerator: numerator,
                numeratorFirst: numeratorFirst,
                numeratorSecond: numeratorSecond,
                numeratorThird: numeratorThird,
                denominator: denominator,
                denominatorFirst: denominatorFirst,
                denominatorSecond: denominatorSecond,
                denominatorThird: denominatorThird,
                tolerance: tolerance
            )

            let generatorDerivative = sin(
                configuration.parameterized.halfAngle
            ).nextUp
            let angularFirst = (
                generatorDerivative * slant.absoluteUpperBound
                    + slantFirst.absoluteUpperBound
            ).nextUp
            let angularSecond = (
                generatorDerivative * slant.absoluteUpperBound
                    + 2.0 * generatorDerivative
                        * slantFirst.absoluteUpperBound
                    + slantSecond.absoluteUpperBound
            ).nextUp
            let angularThird = (
                generatorDerivative * slant.absoluteUpperBound
                    + 3.0 * generatorDerivative
                        * slantFirst.absoluteUpperBound
                    + 3.0 * generatorDerivative
                        * slantSecond.absoluteUpperBound
                    + slantThird.absoluteUpperBound
            ).nextUp
            maximumAngularFirst = max(maximumAngularFirst, angularFirst)
            maximumAngularSecond = max(maximumAngularSecond, angularSecond)
            maximumAngularThird = max(maximumAngularThird, angularThird)
            angularCells.append(FullBranchDifferentialBoundsPreparation.Cell(
                spatial: SpatialDifferentialMagnitudeBounds(
                    first: angularFirst,
                    second: angularSecond,
                    third: angularThird
                ),
                parameterizedVFirst: slantFirst.absoluteUpperBound,
                parameterizedVSecond: slantSecond.absoluteUpperBound,
                parameterizedVThird: slantThird.absoluteUpperBound
            ))
        }
        let periodSquared = (period.nextUp * period.nextUp).nextUp
        let periodCubed = (periodSquared * period.nextUp).nextUp
        let cells = angularCells.map { cell in
            FullBranchDifferentialBoundsPreparation.Cell(
                spatial: SpatialDifferentialMagnitudeBounds(
                    first: (period.nextUp * cell.spatial.first).nextUp,
                    second: (periodSquared * cell.spatial.second).nextUp,
                    third: cell.spatial.third.map {
                        (periodCubed * $0).nextUp
                    }
                ),
                parameterizedVFirst: (
                    period.nextUp * cell.parameterizedVFirst
                ).nextUp,
                parameterizedVSecond: (
                    periodSquared * cell.parameterizedVSecond
                ).nextUp,
                parameterizedVThird: (
                    periodCubed * cell.parameterizedVThird
                ).nextUp
            )
        }
        return PiecewiseDifferentialBounds(
            aggregate: SpatialDifferentialMagnitudeBounds(
                first: (period.nextUp * maximumAngularFirst).nextUp,
                second: (periodSquared * maximumAngularSecond).nextUp,
                third: (periodCubed * maximumAngularThird).nextUp
            ),
            cells: cells
        )
    }

    private static func polynomialRange(
        _ polynomial: TrigonometricPolynomial,
        derivativeBound: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let midpoint = lower + (upper - lower) * 0.5
        let halfWidth = ((upper - lower) * 0.5).nextUp
        let center = polynomial.value(at: midpoint)
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 65_536.0
        ).nextUp
        let radius = (
            derivativeBound.nextUp * halfWidth + arithmeticEnvelope
        ).nextUp
        return try certifiedInterval(
            lower: center - radius,
            upper: center + radius,
            tolerance: tolerance
        )
    }

    private static func restrictedPolynomialRange(
        _ polynomial: TrigonometricPolynomial,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        let residualTolerance = max(
            arithmeticEnvelope,
            Double.ulpOfOne * polynomial.coefficientScale * 4_096.0
        )
        var values = [
            polynomial.value(at: lower),
            polynomial.value(at: upper),
        ]
        let period = 2.0 * Double.pi
        for root in try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        ) {
            for winding in -1...2 {
                let angle = root + Double(winding) * period
                if angle > lower, angle < upper {
                    values.append(polynomial.value(at: angle))
                }
            }
        }
        return (
            ((values.min() ?? 0.0) - arithmeticEnvelope).nextDown,
            ((values.max() ?? 0.0) + arithmeticEnvelope).nextUp
        )
    }

    private static func adding(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        try certifiedInterval(
            lower: (first.lower + second.lower).nextDown,
            upper: (first.upper + second.upper).nextUp,
            tolerance: tolerance
        )
    }

    private static func subtracting(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        try certifiedInterval(
            lower: (first.lower - second.upper).nextDown,
            upper: (first.upper - second.lower).nextUp,
            tolerance: tolerance
        )
    }

    private static func multiplied(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let products = [
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ]
        guard let lower = products.min(), let upper = products.max() else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone interval multiplication produced no bounds."
            )
        }
        return try certifiedInterval(
            lower: lower.nextDown,
            upper: upper.nextUp,
            tolerance: tolerance
        )
    }

    private static func divided(
        _ numerator: CertifiedInterval,
        by denominator: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        guard denominator.lower > 0.0 || denominator.upper < 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone interval division crossed zero."
            )
        }
        let reciprocal = try certifiedInterval(
            lower: min(
                1.0 / denominator.lower,
                1.0 / denominator.upper
            ).nextDown,
            upper: max(
                1.0 / denominator.lower,
                1.0 / denominator.upper
            ).nextUp,
            tolerance: tolerance
        )
        return try multiplied(
            numerator,
            reciprocal,
            tolerance: tolerance
        )
    }

    private static func scaled(
        _ interval: CertifiedInterval,
        by scale: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let first = interval.lower * scale
        let second = interval.upper * scale
        return try certifiedInterval(
            lower: min(first, second).nextDown,
            upper: max(first, second).nextUp,
            tolerance: tolerance
        )
    }

    private static func quotientThirdDerivative(
        numerator: CertifiedInterval,
        numeratorFirst: CertifiedInterval,
        numeratorSecond: CertifiedInterval,
        numeratorThird: CertifiedInterval,
        denominator: CertifiedInterval,
        denominatorFirst: CertifiedInterval,
        denominatorSecond: CertifiedInterval,
        denominatorThird: CertifiedInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        let denominatorSquared = try multiplied(
            denominator,
            denominator,
            tolerance: tolerance
        )
        let denominatorCubed = try multiplied(
            denominatorSquared,
            denominator,
            tolerance: tolerance
        )
        let denominatorFourth = try multiplied(
            denominatorCubed,
            denominator,
            tolerance: tolerance
        )
        let inverse = try divided(
            CertifiedInterval(lower: 1.0, upper: 1.0),
            by: denominator,
            tolerance: tolerance
        )
        let inverseFirst = try scaled(
            divided(
                denominatorFirst,
                by: denominatorSquared,
                tolerance: tolerance
            ),
            by: -1.0,
            tolerance: tolerance
        )
        let inverseSecond = try subtracting(
            divided(
                scaled(
                    multiplied(
                        denominatorFirst,
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    by: 2.0,
                    tolerance: tolerance
                ),
                by: denominatorCubed,
                tolerance: tolerance
            ),
            divided(
                denominatorSecond,
                by: denominatorSquared,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let inverseThird = try subtracting(
            adding(
                scaled(
                    divided(
                        multiplied(
                            denominatorFirst,
                            multiplied(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        by: denominatorFourth,
                        tolerance: tolerance
                    ),
                    by: -6.0,
                    tolerance: tolerance
                ),
                scaled(
                    divided(
                        multiplied(
                            denominatorFirst,
                            denominatorSecond,
                            tolerance: tolerance
                        ),
                        by: denominatorCubed,
                        tolerance: tolerance
                    ),
                    by: 6.0,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            divided(
                denominatorThird,
                by: denominatorSquared,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return try adding(
            adding(
                multiplied(
                    numeratorThird,
                    inverse,
                    tolerance: tolerance
                ),
                scaled(
                    multiplied(
                        numeratorSecond,
                        inverseFirst,
                        tolerance: tolerance
                    ),
                    by: 3.0,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            adding(
                scaled(
                    multiplied(
                        numeratorFirst,
                        inverseSecond,
                        tolerance: tolerance
                    ),
                    by: 3.0,
                    tolerance: tolerance
                ),
                multiplied(
                    numerator,
                    inverseThird,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
    }

    private static func certifiedInterval(
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedInterval {
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential interval arithmetic exceeded finite ordered bounds."
            )
        }
        return CertifiedInterval(lower: lower, upper: upper)
    }

    private static func polynomialAbsoluteUpperBound(
        _ polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let extremumBound = try maximumAbsoluteValue(
            of: polynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 65_536.0
        ).nextUp
        return try upperSum(
            extremumBound.nextUp,
            arithmeticEnvelope,
            tolerance: tolerance
        )
    }

    private static func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite, second.isFinite,
              first >= 0.0, second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification received an invalid product operand."
            )
        }
        let value = (first * second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite multiplication."
            )
        }
        return value
    }

    private static func upperQuotient(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard numerator.isFinite, denominator.isFinite,
              numerator >= 0.0, denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification received an invalid quotient operand."
            )
        }
        let value = (numerator / denominator).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite division."
            )
        }
        return value
    }

    private static func upperSum(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard first.isFinite, second.isFinite,
              first >= 0.0, second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification received an invalid sum operand."
            )
        }
        let value = (first + second).nextUp
        guard value.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Cone-cone differential certification exceeded finite addition."
            )
        }
        return value
    }

    private static func quotientThirdDerivativeMagnitudeUpperBound(
        numeratorValue: Double,
        numeratorFirst: Double,
        numeratorSecond: Double,
        numeratorThird: Double,
        denominatorLower: Double,
        denominatorFirst: Double,
        denominatorSecond: Double,
        denominatorThird: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let denominatorSquaredLower = (
            denominatorLower * denominatorLower
        ).nextDown
        let denominatorCubedLower = (
            denominatorSquaredLower * denominatorLower
        ).nextDown
        let denominatorFourthLower = (
            denominatorCubedLower * denominatorLower
        ).nextDown
        let inverseFirst = try upperQuotient(
            denominatorFirst,
            denominatorSquaredLower,
            tolerance: tolerance
        )
        let inverseSecond = try upperSum(
            upperQuotient(
                denominatorSecond,
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            upperQuotient(
                upperProduct(
                    2.0,
                    upperProduct(
                        denominatorFirst,
                        denominatorFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                denominatorCubedLower,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let inverseThird = try upperSum(
            upperQuotient(
                denominatorThird,
                denominatorSquaredLower,
                tolerance: tolerance
            ),
            upperSum(
                upperQuotient(
                    upperProduct(
                        6.0,
                        upperProduct(
                            denominatorFirst,
                            denominatorSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorCubedLower,
                    tolerance: tolerance
                ),
                upperQuotient(
                    upperProduct(
                        6.0,
                        upperProduct(
                            denominatorFirst,
                            upperProduct(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            ),
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    denominatorFourthLower,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return try upperSum(
            upperQuotient(
                numeratorThird,
                denominatorLower,
                tolerance: tolerance
            ),
            upperSum(
                upperProduct(
                    3.0,
                    upperProduct(
                        numeratorSecond,
                        inverseFirst,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                upperSum(
                    upperProduct(
                        3.0,
                        upperProduct(
                            numeratorFirst,
                            inverseSecond,
                            tolerance: tolerance
                        ),
                        tolerance: tolerance
                    ),
                    upperProduct(
                        numeratorValue,
                        inverseThird,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            tolerance: tolerance
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

    private static func apexReductionResidualUpperBound(
        configuration: Configuration
    ) -> Double {
        sqrt(abs(configuration.constantTerm))
    }

    private static func isEquivalent(
        _ first: Surface3D,
        to second: Surface3D
    ) -> Bool {
        if first == second { return true }
        guard case let .cone(firstCone) = CanonicalAnalyticSurface(first),
              case let .cone(secondCone) = CanonicalAnalyticSurface(second) else {
            return false
        }
        return firstCone.apex == secondCone.apex
            && firstCone.halfAngle == secondCone.halfAngle
            && (firstCone.axis == secondCone.axis
                || firstCone.axis == -secondCone.axis)
    }

    private static func refinedAngle(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<64 {
            let value = polynomial.value(at: angle)
            if abs(value) <= proofResidualTolerance { break }
            let derivative = polynomial.firstDerivative(at: angle)
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

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case referenceSurface
        case parameterizedSurface
        case componentKind
        case lowerAngle
        case upperAngle
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .referenceSurface,
                .parameterizedSurface,
                .componentKind,
                .lowerAngle,
                .upperAngle,
                .certificationTolerance,
            ],
            in: decoder
        )
        try self.init(
            referenceSurface: container.decode(Surface3D.self, forKey: .referenceSurface),
            parameterizedSurface: container.decode(Surface3D.self, forKey: .parameterizedSurface),
            componentKind: container.decode(ComponentKind.self, forKey: .componentKind),
            lowerAngle: container.decode(Double.self, forKey: .lowerAngle),
            upperAngle: container.decode(Double.self, forKey: .upperAngle),
            tolerance: container.decode(
                ModelingTolerance.self,
                forKey: .certificationTolerance
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceSurface, forKey: .referenceSurface)
        try container.encode(parameterizedSurface, forKey: .parameterizedSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
