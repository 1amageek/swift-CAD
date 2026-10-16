import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

public struct CertifiedConeConeIntersectionCurve: Hashable, Sendable {
    public enum ComponentKind: String, Hashable, Sendable {
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

        func tangentHalfAngleCoefficients(using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
            return [
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

        private let receipt: OriginalGeometryPreparationReceipt
        private let curve: CertifiedConeConeIntersectionCurve
        private let configuration: Configuration
        private let cells: [Cell]
        private let referenceChart: ReferenceChart

        fileprivate init(
            receipt: OriginalGeometryPreparationReceipt,
            curve: CertifiedConeConeIntersectionCurve,
            configuration: Configuration,
            cells: [Cell],
            referenceChart: ReferenceChart
        ) {
            self.receipt = receipt
            self.curve = curve
            self.configuration = configuration
            self.cells = cells
            self.referenceChart = referenceChart
        }

        func parameterizedParameterDifferential(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> ParameterDifferentialThroughThirdOrder {
            var execution = try receipt.makeExecution()
            return try parameterizedParameterDifferential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }

        func parameterizedParameterDifferential(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialThroughThirdOrder {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try parameterizedParameterDifferentialAssumingAdmitted(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
            }
        }

        private func parameterizedParameterDifferentialAssumingAdmitted(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialThroughThirdOrder {
            try execution.consumeWork(1)
            return try curve.parameterizedParameterDifferential(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }

        func parameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> SurfaceParameter {
            var execution = try receipt.makeExecution()
            return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }

        func parameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try parameterAssumingAdmitted(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
            }
        }

        private func parameterAssumingAdmitted(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
            try execution.consumeWork(1)
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }

        func continuousParameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        ) throws -> SurfaceParameter {
            var execution = try receipt.makeExecution()
            return try continuousParameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }

        func continuousParameter(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try continuousParameterAssumingAdmitted(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
            }
        }

        private func continuousParameterAssumingAdmitted(
            on surface: Surface3D,
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
            try execution.consumeWork(1)
            let parameter = try self.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            guard try CertifiedConeConeIntersectionCurve.isEquivalent(
                surface,
                to: curve.referenceSurface
            , using: &execution) else {
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
            var execution = try receipt.makeExecution()
            return try referenceParameterAndFirstDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        }

        func referenceParameterAndFirstDerivative(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> (parameter: SurfaceParameter, firstDerivative: Point2D) {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try referenceParameterAndFirstDerivativeAssumingAdmitted(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
            }
        }

        private func referenceParameterAndFirstDerivativeAssumingAdmitted(
            atNormalizedFraction fraction: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> (parameter: SurfaceParameter, firstDerivative: Point2D) {
            try execution.consumeWork(1)
            return try curve.referenceParameterAndFirstDerivative(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }

        func bounds(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        ) throws -> SpatialDifferentialMagnitudeBounds {
            var execution = try receipt.makeExecution()
            return try bounds(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
        }

        func bounds(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try boundsAssumingAdmitted(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
            }
        }

        private func boundsAssumingAdmitted(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
            try execution.consumeWork(1)
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
            , using: &execution)
            var first = 0.0
            var second = 0.0
            var third = 0.0
            for index in indices {
                try execution.consumeWork(1)
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
            var execution = try receipt.makeExecution()
            return try parameterizedParameterDifferentialMagnitudeBounds(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
        }

        func parameterizedParameterDifferentialMagnitudeBounds(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialMagnitudeBounds {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
                return try parameterizedParameterDifferentialMagnitudeBoundsAssumingAdmitted(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
            }
        }

        private func parameterizedParameterDifferentialMagnitudeBoundsAssumingAdmitted(
            fromNormalizedFraction lower: Double,
            toNormalizedFraction upper: Double,
            tolerance: ModelingTolerance
        , using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialMagnitudeBounds {
            try execution.consumeWork(1)
            let indices = try overlappingCellIndices(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            , using: &execution)
            var vFirst = 0.0
            var vSecond = 0.0
            var vThird = 0.0
            for index in indices {
                try execution.consumeWork(1)
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
        , using execution: inout OriginalQueryExecution) throws -> ClosedRange<Int> {
            try execution.consumeWork(1)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(referenceSurface: referenceSurface, parameterizedSurface: parameterizedSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }

    public init(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
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
        , using: &execution)
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        try validate(tolerance: tolerance, using: &execution)
    }

    static func apexContactTopology(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ApexContactTopology? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try apexContactTopology(referenceSurface: referenceSurface, parameterizedSurface: parameterizedSurface, tolerance: tolerance, using: &execution)
    }

    static func apexContactTopology(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ApexContactTopology? {
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        , using: &execution)
        guard try apexReductionResidualUpperBound(
            configuration: configuration
        , using: &execution) <= tolerance.distance else {
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
        , using: &execution)
        guard maximumHalfLinear > halfLinearTolerance else {
            return .isolatedPoint
        }
        let boundaries = try roots(
            of: configuration.halfLinearPolynomial,
            residualTolerance: halfLinearTolerance,
            tolerance: tolerance
        , using: &execution)
        guard boundaries.isEmpty == false else {
            return .isolatedPointAndLoop
        }
        let intervals = try CertifiedAnalyticCurveEvaluation.map(boundaries.indices, using: &execution) {index, execution in
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            return lower...upper
        }
        return .nodeIntervals(intervals)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
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
        , using: &execution)
        guard lowerAngle.isFinite,
              upperAngle.isFinite,
              upperAngle > lowerAngle,
              upperAngle - lowerAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperAngle - lowerAngle)
        }
        let classificationTolerance = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let boundaries = try Self.roots(
            of: configuration.discriminantPolynomial,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        , using: &execution)
        let minimumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: false,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        , using: &execution)
        let maximumQuadratic = try Self.extremum(
            of: configuration.quadraticPolynomial,
            maximum: true,
            residualTolerance: classificationTolerance,
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)
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
            let matchesCompleteInterval = try Self.validIntervals(
                boundaries: boundaries,
                polynomial: configuration.discriminantPolynomial,
                classificationTolerance: classificationTolerance
            , using: &execution).contains { interval in
                try Self.angularDistance(interval.lower, lowerAngle, using: &execution) <= tolerance.angle
                    && (try Self.angularDistance(interval.upper, upperAngle, using: &execution)) <= tolerance.angle
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
            , using: &execution) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: try Self.apexReductionResidualUpperBound(
                        configuration: configuration
                    , using: &execution),
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
                matchesTopology = try intervals.contains { interval in
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
        , using: &execution)
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
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            let referenceProjection = try referenceSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            let parameterizedProjection = try parameterizedSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution).position
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        let geometry = try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        return try derivativesThroughThirdOrder(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution).thirdDerivative
    }



    private func derivativesThroughThirdOrder(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ThirdOrderDifferentialGeometry {
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        , using: &execution)
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        guard try Self.isEquivalent(surface, to: referenceSurface, using: &execution)
                || (try Self.isEquivalent(surface, to: parameterizedSurface, using: &execution)) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-cone pcurve was requested on an unrelated surface."
            )
        }
        if try Self.isEquivalent(surface, to: parameterizedSurface, using: &execution) {
            let configuration = try Self.makeConfiguration(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            , using: &execution)
            return try parameterizedParameterDifferential(
                atNormalizedFraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution).parameter
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        let projection = try surface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    fileprivate func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        guard try Self.isEquivalent(surface, to: referenceSurface, using: &execution)
                || (try Self.isEquivalent(surface, to: parameterizedSurface, using: &execution)) else {
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
        , using: &execution)
        let point = configuration.parameterized.apex
            + configuration.direction(at: coordinates.angle.value)
                * coordinates.slant.value
        let result: SurfaceParameter
        if try Self.isEquivalent(surface, to: parameterizedSurface, using: &execution) {
            result = SurfaceParameter(
                u: coordinates.angle.value,
                v: coordinates.slant.value
            )
        } else {
            let projection = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            result = SurfaceParameter(u: projection.u, v: projection.v)
        }
        let reconstructed = try surface.point(
            u: result.u,
            v: result.v,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> ParameterDifferentialThroughThirdOrder {
        try execution.consumeWork(1)
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> (parameter: SurfaceParameter, firstDerivative: Point2D) {
        try execution.consumeWork(1)
        let coordinates = try parameterizedCoordinateDifferentials(
            atNormalizedFraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> (angle: ScalarDifferential, slant: ScalarDifferential) {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let normalizedFraction = min(max(fraction, 0.0), 1.0)
        let angle = try angleDifferential(at: normalizedFraction, using: &execution)
        let halfLinear = try composedDifferential(
            configuration.halfLinearPolynomial,
            angle: angle
        , using: &execution)
        let quadratic = try composedDifferential(
            configuration.quadraticPolynomial,
            angle: angle
        , using: &execution)
        let numerator: ScalarDifferential
        if componentKind == .apexReducedAngularInterval {
            numerator = ScalarDifferential(
                value: -2.0 * halfLinear.value,
                first: -2.0 * halfLinear.first,
                second: -2.0 * halfLinear.second,
                third: -2.0 * halfLinear.third
            )
        } else {
            let discriminant = try composedDifferential(
                configuration.discriminantPolynomial,
                angle: angle
            , using: &execution)
            let root = try signedSquareRootDifferential(
                discriminant,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
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
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }

    public func boundingBox(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            tolerance: tolerance
        , using: &execution)
        let minimumQuadratic = try Self.minimumAbsoluteValue(
            of: configuration.quadraticPolynomial,
            residualTolerance: try Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let maximumHalfLinear = try Self.maximumAbsoluteValue(
            of: configuration.halfLinearPolynomial,
            residualTolerance: try Self.classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let maximumDiscriminant = max(
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: true,
                residualTolerance: try Self.classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try fullBranchSpatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
        , using: &execution)
        let classificationEnvelope = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let arithmeticEnvelope = try Self.upperProduct(
            classificationEnvelope,
            32.0,
            tolerance: tolerance
        , using: &execution)
        let minimumDiscriminant = (
            try Self.extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            , using: &execution) - arithmeticEnvelope
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
        , using: &execution)
        let discriminantFirst = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let discriminantSecond = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let discriminantThird = try Self.polynomialAbsoluteUpperBound(
            discriminant.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let rootFirst = try Self.upperQuotient(
            discriminantFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootSquaredLower = (rootLower * rootLower).nextDown
        let rootCubedLower = (rootSquaredLower * rootLower).nextDown
        let rootFifthLower = (
            rootCubedLower * rootSquaredLower
        ).nextDown
        let rootSecond = try Self.upperSum(
            try Self.upperQuotient(
                discriminantSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try Self.upperQuotient(
                try Self.upperProduct(
                    discriminantFirst,
                    discriminantFirst,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootThird = try Self.upperSum(
            try Self.upperQuotient(
                discriminantThird,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperQuotient(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            discriminantFirst,
                            discriminantSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            discriminantFirst,
                            try Self.upperProduct(
                                discriminantFirst,
                                discriminantFirst,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)

        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearThird = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let numeratorValue = try Self.upperSum(
            halfLinearValue,
            sqrt(discriminantValue).nextUp,
            tolerance: tolerance
        , using: &execution)
        let numeratorFirst = try Self.upperSum(
            halfLinearFirst,
            rootFirst,
            tolerance: tolerance
        , using: &execution)
        let numeratorSecond = try Self.upperSum(
            halfLinearSecond,
            rootSecond,
            tolerance: tolerance
        , using: &execution)
        let numeratorThird = try Self.upperSum(
            halfLinearThird,
            rootThird,
            tolerance: tolerance
        , using: &execution)

        let quadratic = configuration.quadraticPolynomial
        let quadraticFirst = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let quadraticSecond = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let quadraticThird = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            , using: &execution) - (try Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution))
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
        , using: &execution)
        let slantFirst = try Self.upperSum(
            try Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            try Self.upperQuotient(
                try Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                , using: &execution),
                denominatorSquaredLower,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let slantSecond = try Self.upperSum(
            try Self.upperSum(
                try Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        , using: &execution),
                        quadraticFirst,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        , using: &execution),
                        try Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    denominatorCubedLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)

        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let angularFirst = try Self.upperSum(
            try Self.upperProduct(
                generatorDerivative,
                slantValue,
                tolerance: tolerance
            , using: &execution),
            slantFirst,
            tolerance: tolerance
        , using: &execution)
        let angularSecond = try Self.upperSum(
            try Self.upperSum(
                try Self.upperProduct(
                    generatorDerivative,
                    slantValue,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    try Self.upperProduct(
                        2.0,
                        generatorDerivative,
                        tolerance: tolerance
                    , using: &execution),
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            slantSecond,
            tolerance: tolerance
        , using: &execution)
        let angularThird = try Self.upperSum(
            try Self.upperSum(
                try Self.upperProduct(
                    generatorDerivative,
                    slantValue,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        generatorDerivative,
                        tolerance: tolerance
                    , using: &execution),
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        generatorDerivative,
                        tolerance: tolerance
                    , using: &execution),
                    slantSecond,
                    tolerance: tolerance
                , using: &execution),
                slantThird,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try Self.upperProduct(
            period,
            period,
            tolerance: tolerance
        , using: &execution)
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        , using: &execution)
        let coarseBounds = SpatialDifferentialMagnitudeBounds(
            first: try Self.upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            , using: &execution),
            second: try Self.upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            , using: &execution),
            third: try Self.upperProduct(
                periodCubed,
                angularThird,
                tolerance: tolerance
            , using: &execution)
        )
        let piecewiseBounds = try Self.piecewiseSpatialDifferentialBounds(
            configuration: configuration,
            branchSign: componentKind == .negativeFullBranch ? -1.0 : 1.0,
            tolerance: tolerance
        , using: &execution).aggregate
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try fullBranchSpatialDifferentialMagnitudeBounds(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        return try prepareFullBranchDifferentialBounds(
            tolerance: tolerance
        , using: &execution).bounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            tolerance: tolerance, using: &execution
        )
    }

    func prepareFullBranchDifferentialBounds(
        tolerance: ModelingTolerance
    ) throws -> FullBranchDifferentialBoundsPreparation {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try prepareFullBranchDifferentialBounds(tolerance: tolerance, using: &execution)
    }

    func prepareFullBranchDifferentialBounds(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> FullBranchDifferentialBoundsPreparation {
        let prepared = try execution.withPreparationScope { execution in
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
        , using: &execution)
        let piecewiseBounds = try Self.piecewiseSpatialDifferentialBounds(
            configuration: configuration,
            branchSign: componentKind == .negativeFullBranch ? -1.0 : 1.0,
            tolerance: tolerance
        , using: &execution)
        let referenceChart = try prepareReferenceChart(
            configuration: configuration,
            cells: piecewiseBounds.cells,
            tolerance: tolerance
        , using: &execution)
        return (configuration, piecewiseBounds.cells, referenceChart)
        }
        let receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: prepared.depth, using: &execution)
        return FullBranchDifferentialBoundsPreparation(receipt: receipt,
            curve: self, configuration: prepared.result.0,
            cells: prepared.result.1, referenceChart: prepared.result.2)
    }



    private func prepareReferenceChart(
        configuration: Configuration,
        cells: [FullBranchDifferentialBoundsPreparation.Cell],
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> FullBranchDifferentialBoundsPreparation.ReferenceChart {
        try execution.consumeWork(1)
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
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(count, in: &maximumUVariations, using: &execution)
        for index in 0..<count {
            try execution.consumeWork(1)
            let middleFraction = (Double(index) + 0.5) * inverseCount
            let middle = try parameter(
                on: referenceSurface,
                atNormalizedFraction: middleFraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
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
        , using: &execution).u
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        var uNodes = [first]
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(count + 1, in: &uNodes, using: &execution)
        for index in 1...count {
            try execution.consumeWork(1)
            let principal = try parameter(
                on: referenceSurface,
                atNormalizedFraction: Double(index) * inverseCount,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution).u
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try apexReducedBranchSpatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }

    func apexReducedBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
        , using: &execution)
        let classificationEnvelope = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let halfLinear = configuration.halfLinearPolynomial
        let halfLinearValue = try Self.polynomialAbsoluteUpperBound(
            halfLinear,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearFirst = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearSecond = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let halfLinearThird = try Self.polynomialAbsoluteUpperBound(
            halfLinear.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let quadratic = configuration.quadraticPolynomial
        let quadraticFirstByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let quadraticSecondByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let quadraticThirdByAngle = try Self.polynomialAbsoluteUpperBound(
            quadratic.derivativePolynomial.derivativePolynomial
                .derivativePolynomial,
            residualTolerance: classificationEnvelope,
            tolerance: tolerance
        , using: &execution)
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: classificationEnvelope,
                tolerance: tolerance
            , using: &execution) - (try Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution))
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
        , using: &execution)
        let spanCubed = try Self.upperProduct(
            spanSquared,
            span,
            tolerance: tolerance
        , using: &execution)
        let numeratorValue = try Self.upperProduct(
            2.0,
            halfLinearValue,
            tolerance: tolerance
        , using: &execution)
        let numeratorFirst = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearFirst,
                tolerance: tolerance
            , using: &execution),
            span,
            tolerance: tolerance
        , using: &execution)
        let numeratorSecond = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearSecond,
                tolerance: tolerance
            , using: &execution),
            spanSquared,
            tolerance: tolerance
        , using: &execution)
        let numeratorThird = try Self.upperProduct(
            try Self.upperProduct(
                2.0,
                halfLinearThird,
                tolerance: tolerance
            , using: &execution),
            spanCubed,
            tolerance: tolerance
        , using: &execution)
        let quadraticFirst = try Self.upperProduct(
            quadraticFirstByAngle,
            span,
            tolerance: tolerance
        , using: &execution)
        let quadraticSecond = try Self.upperProduct(
            quadraticSecondByAngle,
            spanSquared,
            tolerance: tolerance
        , using: &execution)
        let quadraticThird = try Self.upperProduct(
            quadraticThirdByAngle,
            spanCubed,
            tolerance: tolerance
        , using: &execution)
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
        , using: &execution)
        let slantFirst = try Self.upperSum(
            try Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            try Self.upperQuotient(
                try Self.upperProduct(
                    numeratorValue,
                    quadraticFirst,
                    tolerance: tolerance
                , using: &execution),
                denominatorSquaredLower,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let slantSecond = try Self.upperSum(
            try Self.upperSum(
                try Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        numeratorValue,
                        quadraticSecond,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        , using: &execution),
                        quadraticFirst,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorValue,
                            tolerance: tolerance
                        , using: &execution),
                        try Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    denominatorCubedLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)
        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let first = try Self.upperSum(
            try Self.upperProduct(
                try Self.upperProduct(
                    generatorDerivative,
                    span,
                    tolerance: tolerance
                , using: &execution),
                slantValue,
                tolerance: tolerance
            , using: &execution),
            slantFirst,
            tolerance: tolerance
        , using: &execution)
        let second = try Self.upperSum(
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        generatorDerivative,
                        spanSquared,
                        tolerance: tolerance
                    , using: &execution),
                    slantValue,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            generatorDerivative,
                            tolerance: tolerance
                        , using: &execution),
                        span,
                        tolerance: tolerance
                    , using: &execution),
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            slantSecond,
            tolerance: tolerance
        , using: &execution)
        let directionFirst = try Self.upperProduct(
            generatorDerivative,
            span,
            tolerance: tolerance
        , using: &execution)
        let directionSecond = try Self.upperProduct(
            generatorDerivative,
            spanSquared,
            tolerance: tolerance
        , using: &execution)
        let directionThird = try Self.upperProduct(
            generatorDerivative,
            spanCubed,
            tolerance: tolerance
        , using: &execution)
        let third = try Self.upperSum(
            try Self.upperSum(
                try Self.upperProduct(
                    directionThird,
                    slantValue,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        directionSecond,
                        tolerance: tolerance
                    , using: &execution),
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        3.0,
                        directionFirst,
                        tolerance: tolerance
                    , using: &execution),
                    slantSecond,
                    tolerance: tolerance
                , using: &execution),
                slantThird,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundedBranchSpatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
        , using: &execution)
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
        , using: &execution)
        let periodCubed = try Self.upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        , using: &execution)
        let phaseLower = period * lower
        let phaseUpper = period * upper
        let angleRange = try Self.boundedAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle
        , using: &execution)
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
            valueRange: { rangeLower, rangeUpper, execution in
                try Self.restrictedPolynomialRange(
                    discriminant,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope,
                    tolerance: tolerance
                , using: &execution)
            },
            tolerance: tolerance,
            label: "Cone-cone bounded branch"
        , using: &execution)
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
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootFifthLower = (rootCubedLower * factor.lower).nextDown
        let rootSecondByAngle = try Self.upperSum(
            try Self.upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try Self.upperQuotient(
                try Self.upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootThirdByAngle = try Self.upperSum(
            try Self.upperQuotient(
                factor.third,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperQuotient(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            factor.first,
                            factor.second,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    (4.0 * rootCubedLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            factor.first,
                            try Self.upperProduct(
                                factor.first,
                                factor.first,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    (8.0 * rootFifthLower).nextDown,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let sineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: Double.pi * 0.5
        , using: &execution)
        let cosineMagnitude = try Self.maximumAbsoluteTrigonometricValue(
            lower: phaseLower,
            upper: phaseUpper,
            phase: 0.0
        , using: &execution)
        let angleFirst = try Self.upperProduct(
            try Self.upperProduct(
                halfSpan,
                period,
                tolerance: tolerance
            , using: &execution),
            sineMagnitude,
            tolerance: tolerance
        , using: &execution)
        let angleSecond = try Self.upperProduct(
            try Self.upperProduct(
                halfSpan,
                periodSquared,
                tolerance: tolerance
            , using: &execution),
            cosineMagnitude,
            tolerance: tolerance
        , using: &execution)
        let angleThird = try Self.upperProduct(
            try Self.upperProduct(
                halfSpan,
                periodCubed,
                tolerance: tolerance
            , using: &execution),
            sineMagnitude,
            tolerance: tolerance
        , using: &execution)
        let rootFirstByFraction = try Self.upperProduct(
            rootFirstByAngle,
            angleFirst,
            tolerance: tolerance
        , using: &execution)
        let rootSecondByFraction = try Self.upperSum(
            try Self.upperProduct(
                rootSecondByAngle,
                try Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperProduct(
                rootFirstByAngle,
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootThirdByFraction = try Self.upperSum(
            try Self.upperProduct(
                rootThirdByAngle,
                try Self.upperProduct(
                    angleFirst,
                    try Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperProduct(
                    3.0,
                    try Self.upperProduct(
                        rootSecondByAngle,
                        try Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    rootFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let signedRootMagnitude = try Self.upperProduct(
            try Self.upperProduct(
                halfSpan,
                sineMagnitude,
                tolerance: tolerance
            , using: &execution),
            rootUpper,
            tolerance: tolerance
        , using: &execution)
        let signedRootFirst = try Self.upperProduct(
            halfSpan,
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        period,
                        cosineMagnitude,
                        tolerance: tolerance
                    , using: &execution),
                    rootUpper,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    try Self.upperProduct(
                        sineMagnitude,
                        rootFirstByAngle,
                        tolerance: tolerance
                    , using: &execution),
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let signedRootSecond = try Self.upperProduct(
            halfSpan,
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        periodSquared,
                        sineMagnitude,
                        tolerance: tolerance
                    , using: &execution),
                    rootUpper,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperSum(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            try Self.upperProduct(
                                2.0,
                                period,
                                tolerance: tolerance
                            , using: &execution),
                            cosineMagnitude,
                            tolerance: tolerance
                        , using: &execution),
                        try Self.upperProduct(
                            rootFirstByAngle,
                            angleFirst,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    try Self.upperProduct(
                        sineMagnitude,
                        try Self.upperSum(
                            try Self.upperProduct(
                                rootSecondByAngle,
                                try Self.upperProduct(
                                    angleFirst,
                                    angleFirst,
                                    tolerance: tolerance
                                , using: &execution),
                                tolerance: tolerance
                            , using: &execution),
                            try Self.upperProduct(
                                rootFirstByAngle,
                                angleSecond,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let signedRootThird = try Self.upperProduct(
            halfSpan,
            try Self.upperSum(
                try Self.upperProduct(
                    try Self.upperProduct(
                        periodCubed,
                        cosineMagnitude,
                        tolerance: tolerance
                    , using: &execution),
                    rootUpper,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperSum(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            try Self.upperProduct(
                                periodSquared,
                                sineMagnitude,
                                tolerance: tolerance
                            , using: &execution),
                            rootFirstByFraction,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    try Self.upperSum(
                        try Self.upperProduct(
                            3.0,
                            try Self.upperProduct(
                                try Self.upperProduct(
                                    period,
                                    cosineMagnitude,
                                    tolerance: tolerance
                                , using: &execution),
                                rootSecondByFraction,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        try Self.upperProduct(
                            sineMagnitude,
                            rootThirdByFraction,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
        , using: &execution)
        let halfLinearSecond = try Self.upperSum(
            try Self.upperProduct(
                halfLinearSecondByAngle,
                try Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperProduct(
                halfLinearFirstByAngle,
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let halfLinearThird = try Self.upperSum(
            try Self.upperProduct(
                halfLinearThirdByAngle,
                try Self.upperProduct(
                    angleFirst,
                    try Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperProduct(
                    3.0,
                    try Self.upperProduct(
                        halfLinearSecondByAngle,
                        try Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    halfLinearFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let numeratorMagnitude = try Self.upperSum(
            halfLinearMagnitude,
            signedRootMagnitude,
            tolerance: tolerance
        , using: &execution)
        let numeratorFirst = try Self.upperSum(
            halfLinearFirst,
            signedRootFirst,
            tolerance: tolerance
        , using: &execution)
        let numeratorSecond = try Self.upperSum(
            halfLinearSecond,
            signedRootSecond,
            tolerance: tolerance
        , using: &execution)
        let numeratorThird = try Self.upperSum(
            halfLinearThird,
            signedRootThird,
            tolerance: tolerance
        , using: &execution)
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
        , using: &execution)
        let quadraticSecond = try Self.upperSum(
            try Self.upperProduct(
                quadraticSecondByAngle,
                try Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperProduct(
                quadraticFirstByAngle,
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let quadraticThird = try Self.upperSum(
            try Self.upperProduct(
                quadraticThirdByAngle,
                try Self.upperProduct(
                    angleFirst,
                    try Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperProduct(
                    3.0,
                    try Self.upperProduct(
                        quadraticSecondByAngle,
                        try Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try Self.upperProduct(
                    quadraticFirstByAngle,
                    angleThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let denominatorLower = (
            try Self.minimumAbsoluteValue(
                of: quadratic,
                residualTolerance: try Self.classificationTolerance(
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution) - (try Self.quadraticTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution))
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
        , using: &execution)
        let slantFirst = try Self.upperSum(
            try Self.upperQuotient(
                numeratorFirst,
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            try Self.upperQuotient(
                try Self.upperProduct(
                    numeratorMagnitude,
                    quadraticFirst,
                    tolerance: tolerance
                , using: &execution),
                denominatorSquaredLower,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let slantSecond = try Self.upperSum(
            try Self.upperSum(
                try Self.upperQuotient(
                    numeratorSecond,
                    denominatorLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        numeratorMagnitude,
                        quadraticSecond,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try Self.upperSum(
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorFirst,
                            tolerance: tolerance
                        , using: &execution),
                        quadraticFirst,
                        tolerance: tolerance
                    , using: &execution),
                    denominatorSquaredLower,
                    tolerance: tolerance
                , using: &execution),
                try Self.upperQuotient(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            numeratorMagnitude,
                            tolerance: tolerance
                        , using: &execution),
                        try Self.upperProduct(
                            quadraticFirst,
                            quadraticFirst,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    denominatorCubedLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
            , using: &execution)
        let generatorDerivative = sin(
            configuration.parameterized.halfAngle
        ).nextUp
        let directionFirst = try Self.upperProduct(
            generatorDerivative,
            angleFirst,
            tolerance: tolerance
        , using: &execution)
        let directionSecond = try Self.upperProduct(
            generatorDerivative,
            try Self.upperSum(
                try Self.upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let directionThird = try Self.upperProduct(
            generatorDerivative,
            try Self.upperSum(
                try Self.upperProduct(
                    angleFirst,
                    try Self.upperProduct(
                        angleFirst,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try Self.upperSum(
                    try Self.upperProduct(
                        3.0,
                        try Self.upperProduct(
                            angleFirst,
                            angleSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    angleThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        return SpatialDifferentialMagnitudeBounds(
            first: try Self.upperSum(
                try Self.upperProduct(
                    directionFirst,
                    slantMagnitude,
                    tolerance: tolerance
                , using: &execution),
                slantFirst,
                tolerance: tolerance
            , using: &execution),
            second: try Self.upperSum(
                try Self.upperSum(
                    try Self.upperProduct(
                        directionSecond,
                        slantMagnitude,
                        tolerance: tolerance
                    , using: &execution),
                    try Self.upperProduct(
                        try Self.upperProduct(
                            2.0,
                            directionFirst,
                            tolerance: tolerance
                        , using: &execution),
                        slantFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                slantSecond,
                tolerance: tolerance
            , using: &execution),
            third: try Self.upperSum(
                try Self.upperSum(
                    try Self.upperProduct(
                        directionThird,
                        slantMagnitude,
                        tolerance: tolerance
                    , using: &execution),
                    try Self.upperProduct(
                        try Self.upperProduct(
                            3.0,
                            directionSecond,
                            tolerance: tolerance
                        , using: &execution),
                        slantFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try Self.upperSum(
                    try Self.upperProduct(
                        try Self.upperProduct(
                            3.0,
                            directionFirst,
                            tolerance: tolerance
                        , using: &execution),
                        slantSecond,
                        tolerance: tolerance
                    , using: &execution),
                    slantThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
        )
    }



    private func angleDifferential(at fraction: Double,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let angularFirst = polynomial.firstDerivative(at: angle.value)
        let angularSecond = polynomial.secondDerivative(at: angle.value)
        return ScalarDifferential(
            value: polynomial.value(at: angle.value),
            first: angularFirst * angle.first,
            second: angularSecond
                * angle.first * angle.first
                + angularFirst * angle.second,
            third: try polynomial.thirdDerivative(at: angle.value)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let classificationTolerance = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
                at: try angleDifferential(at: fraction, using: &execution).value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
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
            let angle = try angleDifferential(at: fraction, using: &execution)
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
            let result = try Self.product(sine, rootByFraction, using: &execution).scaled(
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
        let dividedDifference = try Self.trigonometricDividedDifference(
            discriminant,
            value: angle,
            endpoint: endpoint
        , using: &execution)
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
        , using: &execution)
    }



    private static func trigonometricDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        var result = ScalarDifferential.constant(0.0)
        try execution.retainStorage(count: 2, stride: MemoryLayout<(order: Double, cosine: Double, sine: Double)>.stride)
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
            try execution.consumeWork(1)
            let halfOrder = harmonic.order * 0.5
            let difference = value - endpoint
            let midpoint = (value + endpoint) * halfOrder
            let sinc = try sincDifferential(
                at: difference * halfOrder,
                derivativeScale: halfOrder
            , using: &execution)
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
                try product(sinc, amplitude, using: &execution).scaled(by: harmonic.order)
            )
        }
        return result
    }



    private static func sincDifferential(
        at value: Double,
        derivativeScale: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
                try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        return ScalarDifferential(
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
        return try product(
            numerator,
            ScalarDifferential(
                value: inverse,
                first: inverseFirst,
                second: inverseSecond,
                third: inverseThird
            )
        , using: &execution)
    }



    private func quotient(
        _ numerator: ScalarDifferential,
        by denominator: ScalarDifferential,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.consumeWork(1)
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
        let reference = try canonicalCone(referenceCanonical, tolerance: tolerance, using: &execution)
        let parameterized = try canonicalCone(parameterizedCanonical, tolerance: tolerance, using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Cone {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let normalizedResidual = max(
            Double.ulpOfOne * 1_024.0,
            residualTolerance / polynomial.coefficientScale
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 0.25, Double.ulpOfOne * 1_024.0),
            residualTolerance: normalizedResidual,
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        var values = try CertifiedAnalyticCurveEvaluation.map(solver.realRoots(
            coefficients: (try polynomial.tangentHalfAngleCoefficients(using: &execution))
        , using: &execution), using: &execution) {element, execution in try normalizedAngle(2.0 * atan(element), using: &execution) }
        var valuesCapacity = values.count
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            try CertifiedAnalyticCurveEvaluation.append(Double.pi, to: &values, using: &execution, capacity: &valuesCapacity)
        }
        values = try CertifiedAnalyticCurveEvaluation.map(values, using: &execution) {value, execution in
            try refinedAngle(
                value,
                polynomial: polynomial,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            , using: &execution)
         }
        values = try CertifiedAnalyticCurveEvaluation.filter(values, using: &execution) { value, execution in
            abs(polynomial.value(at: value)) <= residualTolerance * 16.0
        }
        values = try CertifiedAnalyticCurveEvaluation.sorted(values, using: &execution)
        var result: [Double] = []
        var resultCapacity = result.count
        for value in values {
            try execution.consumeWork(1)
            if let last = result.last, try angularDistance(last, value, using: &execution) <= tolerance.angle { continue }
            try CertifiedAnalyticCurveEvaluation.append(value, to: &result, using: &execution, capacity: &resultCapacity)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           try angularDistance(first, last, using: &execution) <= tolerance.angle {
            result.removeLast()
        }
        return result
    }



    private static func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let values = try CertifiedAnalyticCurveEvaluation.map(([0.0] + (try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        , using: &execution))), using: &execution) { element, execution in polynomial.value(at: element) }
        return maximum
            ? values.max() ?? polynomial.value(at: 0.0)
            : values.min() ?? polynomial.value(at: 0.0)
    }



    private static func maximumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
            abs(try extremum(
                of: polynomial,
                maximum: false,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            , using: &execution)),
            abs(try extremum(
                of: polynomial,
                maximum: true,
                residualTolerance: residualTolerance,
                tolerance: tolerance
            , using: &execution))
        )
    }



    private static func minimumAbsoluteValue(
        of polynomial: TrigonometricPolynomial,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let minimum = try extremum(
            of: polynomial,
            maximum: false,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        , using: &execution)
        let maximum = try extremum(
            of: polynomial,
            maximum: true,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> [(lower: Double, upper: Double)] {
        try execution.consumeWork(1)
        guard boundaries.isEmpty == false else { return [] }
        var result: [(lower: Double, upper: Double)] = []
        var capacity = 0
        for index in boundaries.indices {
            try execution.consumeWork(1)
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + 2.0 * Double.pi
            if polynomial.value(at: lower + (upper - lower) * 0.5) > classificationTolerance {
                try CertifiedAnalyticCurveEvaluation.append((lower, upper), to: &result,
                    using: &execution, capacity: &capacity)
            }
        }
        return result
    }



    private static func boundedAngleRange(
        phaseLower: Double,
        phaseUpper: Double,
        lowerAngle: Double,
        upperAngle: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let midpoint = lowerAngle + (upperAngle - lowerAngle) * 0.5
        let halfSpan = (upperAngle - lowerAngle) * 0.5
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var values = [
            midpoint - halfSpan * cos(phaseLower),
            midpoint - halfSpan * cos(phaseUpper),
        ]
        var valuesCapacity = values.count
        for index in 0...2 {
            try execution.consumeWork(1)
            let phase = Double(index) * Double.pi
            if phase > phaseLower, phase < phaseUpper {
                try CertifiedAnalyticCurveEvaluation.append(midpoint - halfSpan * cos(phase), to: &values, using: &execution, capacity: &valuesCapacity)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var result = max(
            abs(cos(lower - phase)),
            abs(cos(upper - phase))
        )
        for index in -2...4 {
            try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 131_072.0
        if componentKind == .apexReducedAngularInterval {
            let result = try apexReductionResidualUpperBound(
                configuration: configuration
            , using: &execution) + machineBound
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
            residualTolerance: try classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
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
    ,
        using execution: inout OriginalQueryExecution) throws -> PiecewiseDifferentialBounds {
        try execution.consumeWork(1)
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
        try CertifiedAnalyticCurveEvaluation.reserveCapacity(cellCount, in: &angularCells, using: &execution)

        for index in 0..<cellCount {
            try execution.visitGeometricCell(depth: 0)
            try execution.consumeWork(1)
            let lower = period * Double(index) / Double(cellCount)
            let upper = period * Double(index + 1) / Double(cellCount)
            let discriminantRange = try polynomialRange(
                discriminant,
                derivativeBound: discriminantFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution)
            let discriminantSecondRange = try polynomialRange(
                discriminantSecond,
                derivativeBound: discriminantThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let discriminantThirdRange = try polynomialRange(
                discriminantThird,
                derivativeBound: discriminantThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let rootFirst = try divided(
                discriminantFirstRange,
                by: try scaled(root, by: 2.0, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)
            let rootSecond = try subtracting(
                try divided(
                    discriminantSecondRange,
                    by: try scaled(root, by: 2.0, tolerance: tolerance, using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try divided(
                    try multiplied(
                        discriminantFirstRange,
                        discriminantFirstRange,
                        tolerance: tolerance
                    , using: &execution),
                    by: try scaled(
                        try multiplied(
                            try multiplied(root, root, tolerance: tolerance, using: &execution),
                            root,
                            tolerance: tolerance
                        , using: &execution),
                        by: 4.0,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
            let rootSquared = try multiplied(
                root,
                root,
                tolerance: tolerance
            , using: &execution)
            let rootCubed = try multiplied(
                rootSquared,
                root,
                tolerance: tolerance
            , using: &execution)
            let rootFifth = try multiplied(
                rootCubed,
                rootSquared,
                tolerance: tolerance
            , using: &execution)
            let rootThird = try adding(
                try subtracting(
                    try divided(
                        discriminantThirdRange,
                        by: try scaled(
                            root,
                            by: 2.0,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    try divided(
                        try scaled(
                            try multiplied(
                                discriminantFirstRange,
                                discriminantSecondRange,
                                tolerance: tolerance
                            , using: &execution),
                            by: 3.0,
                            tolerance: tolerance
                        , using: &execution),
                        by: try scaled(
                            rootCubed,
                            by: 4.0,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try divided(
                    try scaled(
                        try multiplied(
                            discriminantFirstRange,
                            try multiplied(
                                discriminantFirstRange,
                                discriminantFirstRange,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        by: 3.0,
                        tolerance: tolerance
                    , using: &execution),
                    by: try scaled(
                        rootFifth,
                        by: 8.0,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)

            let halfLinearRange = try polynomialRange(
                halfLinear,
                derivativeBound: halfLinearFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let halfLinearFirstRange = try polynomialRange(
                halfLinearFirst,
                derivativeBound: halfLinearSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let halfLinearSecondRange = try polynomialRange(
                halfLinearSecond,
                derivativeBound: halfLinearThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let halfLinearThirdRange = try polynomialRange(
                halfLinearThird,
                derivativeBound: halfLinearThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let numerator = try adding(
                try scaled(halfLinearRange, by: -1.0, tolerance: tolerance, using: &execution),
                try scaled(root, by: branchSign, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)
            let numeratorFirst = try adding(
                try scaled(halfLinearFirstRange, by: -1.0, tolerance: tolerance, using: &execution),
                try scaled(rootFirst, by: branchSign, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)
            let numeratorSecond = try adding(
                try scaled(halfLinearSecondRange, by: -1.0, tolerance: tolerance, using: &execution),
                try scaled(rootSecond, by: branchSign, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)
            let numeratorThird = try adding(
                try scaled(halfLinearThirdRange, by: -1.0, tolerance: tolerance, using: &execution),
                try scaled(rootThird, by: branchSign, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)

            let denominator = try polynomialRange(
                quadratic,
                derivativeBound: quadraticFirst.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let denominatorFirst = try polynomialRange(
                quadraticFirst,
                derivativeBound: quadraticSecond.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let denominatorSecond = try polynomialRange(
                quadraticSecond,
                derivativeBound: quadraticThird.absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
            let denominatorThird = try polynomialRange(
                quadraticThird,
                derivativeBound: quadraticThird.derivativePolynomial
                    .absoluteCoefficientSum,
                lower: lower,
                upper: upper,
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution)
            let denominatorCubed = try multiplied(
                denominatorSquared,
                denominator,
                tolerance: tolerance
            , using: &execution)
            let slant = try divided(
                numerator,
                by: denominator,
                tolerance: tolerance
            , using: &execution)
            let slantFirst = try subtracting(
                try divided(
                    numeratorFirst,
                    by: denominator,
                    tolerance: tolerance
                , using: &execution),
                try divided(
                    try multiplied(
                        numerator,
                        denominatorFirst,
                        tolerance: tolerance
                    , using: &execution),
                    by: denominatorSquared,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
            let slantSecond = try adding(
                try subtracting(
                    try subtracting(
                        try divided(
                            numeratorSecond,
                            by: denominator,
                            tolerance: tolerance
                        , using: &execution),
                        try divided(
                            try multiplied(
                                numerator,
                                denominatorSecond,
                                tolerance: tolerance
                            , using: &execution),
                            by: denominatorSquared,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    try divided(
                        try scaled(
                            try multiplied(
                                numeratorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            , using: &execution),
                            by: 2.0,
                            tolerance: tolerance
                        , using: &execution),
                        by: denominatorSquared,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try divided(
                    try scaled(
                        try multiplied(
                            numerator,
                            try multiplied(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        by: 2.0,
                        tolerance: tolerance
                    , using: &execution),
                    by: denominatorCubed,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution)

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
        let cells = try CertifiedAnalyticCurveEvaluation.map(angularCells, using: &execution) {cell, execution in
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
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
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
        , using: &execution)
    }



    private static func restrictedPolynomialRange(
        _ polynomial: TrigonometricPolynomial,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let residualTolerance = max(
            arithmeticEnvelope,
            Double.ulpOfOne * polynomial.coefficientScale * 4_096.0
        )
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var values = [
            polynomial.value(at: lower),
            polynomial.value(at: upper),
        ]
        var valuesCapacity = values.count
        let period = 2.0 * Double.pi
        for root in try roots(
            of: polynomial.derivativePolynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        , using: &execution) {
            try execution.consumeWork(1)
            for winding in -1...2 {
                try execution.consumeWork(1)
                let angle = root + Double(winding) * period
                if angle > lower, angle < upper {
                    try CertifiedAnalyticCurveEvaluation.append(polynomial.value(at: angle), to: &values, using: &execution, capacity: &valuesCapacity)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
        return try certifiedInterval(
            lower: (first.lower + second.lower).nextDown,
            upper: (first.upper + second.upper).nextUp,
            tolerance: tolerance
        , using: &execution)
    }



    private static func subtracting(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
        return try certifiedInterval(
            lower: (first.lower - second.upper).nextDown,
            upper: (first.upper - second.lower).nextUp,
            tolerance: tolerance
        , using: &execution)
    }



    private static func multiplied(
        _ first: CertifiedInterval,
        _ second: CertifiedInterval,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
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
        , using: &execution)
    }



    private static func divided(
        _ numerator: CertifiedInterval,
        by denominator: CertifiedInterval,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
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
        , using: &execution)
        return try multiplied(
            numerator,
            reciprocal,
            tolerance: tolerance
        , using: &execution)
    }



    private static func scaled(
        _ interval: CertifiedInterval,
        by scale: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
        let first = interval.lower * scale
        let second = interval.upper * scale
        return try certifiedInterval(
            lower: min(first, second).nextDown,
            upper: max(first, second).nextUp,
            tolerance: tolerance
        , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
        let denominatorSquared = try multiplied(
            denominator,
            denominator,
            tolerance: tolerance
        , using: &execution)
        let denominatorCubed = try multiplied(
            denominatorSquared,
            denominator,
            tolerance: tolerance
        , using: &execution)
        let denominatorFourth = try multiplied(
            denominatorCubed,
            denominator,
            tolerance: tolerance
        , using: &execution)
        let inverse = try divided(
            CertifiedInterval(lower: 1.0, upper: 1.0),
            by: denominator,
            tolerance: tolerance
        , using: &execution)
        let inverseFirst = try scaled(
            try divided(
                denominatorFirst,
                by: denominatorSquared,
                tolerance: tolerance
            , using: &execution),
            by: -1.0,
            tolerance: tolerance
        , using: &execution)
        let inverseSecond = try subtracting(
            try divided(
                try scaled(
                    try multiplied(
                        denominatorFirst,
                        denominatorFirst,
                        tolerance: tolerance
                    , using: &execution),
                    by: 2.0,
                    tolerance: tolerance
                , using: &execution),
                by: denominatorCubed,
                tolerance: tolerance
            , using: &execution),
            try divided(
                denominatorSecond,
                by: denominatorSquared,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let inverseThird = try subtracting(
            try adding(
                try scaled(
                    try divided(
                        try multiplied(
                            denominatorFirst,
                            try multiplied(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        by: denominatorFourth,
                        tolerance: tolerance
                    , using: &execution),
                    by: -6.0,
                    tolerance: tolerance
                , using: &execution),
                try scaled(
                    try divided(
                        try multiplied(
                            denominatorFirst,
                            denominatorSecond,
                            tolerance: tolerance
                        , using: &execution),
                        by: denominatorCubed,
                        tolerance: tolerance
                    , using: &execution),
                    by: 6.0,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try divided(
                denominatorThird,
                by: denominatorSquared,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        return try adding(
            try adding(
                try multiplied(
                    numeratorThird,
                    inverse,
                    tolerance: tolerance
                , using: &execution),
                try scaled(
                    try multiplied(
                        numeratorSecond,
                        inverseFirst,
                        tolerance: tolerance
                    , using: &execution),
                    by: 3.0,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            try adding(
                try scaled(
                    try multiplied(
                        numeratorFirst,
                        inverseSecond,
                        tolerance: tolerance
                    , using: &execution),
                    by: 3.0,
                    tolerance: tolerance
                , using: &execution),
                try multiplied(
                    numerator,
                    inverseThird,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
    }



    private static func certifiedInterval(
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> CertifiedInterval {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let extremumBound = try maximumAbsoluteValue(
            of: polynomial,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        , using: &execution)
        let arithmeticEnvelope = (
            Double.ulpOfOne * polynomial.coefficientScale * 65_536.0
        ).nextUp
        return try upperSum(
            extremumBound.nextUp,
            arithmeticEnvelope,
            tolerance: tolerance
        , using: &execution)
    }



    private static func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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
        , using: &execution)
        let inverseSecond = try upperSum(
            try upperQuotient(
                denominatorSecond,
                denominatorSquaredLower,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    2.0,
                    try upperProduct(
                        denominatorFirst,
                        denominatorFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                denominatorCubedLower,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let inverseThird = try upperSum(
            try upperQuotient(
                denominatorThird,
                denominatorSquaredLower,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                try upperQuotient(
                    try upperProduct(
                        6.0,
                        try upperProduct(
                            denominatorFirst,
                            denominatorSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    denominatorCubedLower,
                    tolerance: tolerance
                , using: &execution),
                try upperQuotient(
                    try upperProduct(
                        6.0,
                        try upperProduct(
                            denominatorFirst,
                            try upperProduct(
                                denominatorFirst,
                                denominatorFirst,
                                tolerance: tolerance
                            , using: &execution),
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    denominatorFourthLower,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        return try upperSum(
            try upperQuotient(
                numeratorThird,
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                try upperProduct(
                    3.0,
                    try upperProduct(
                        numeratorSecond,
                        inverseFirst,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                try upperSum(
                    try upperProduct(
                        3.0,
                        try upperProduct(
                            numeratorFirst,
                            inverseSecond,
                            tolerance: tolerance
                        , using: &execution),
                        tolerance: tolerance
                    , using: &execution),
                    try upperProduct(
                        numeratorValue,
                        inverseThird,
                        tolerance: tolerance
                    , using: &execution),
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return sqrt(abs(configuration.constantTerm))
    }



    private static func isEquivalent(
        _ first: Surface3D,
        to second: Surface3D
    ,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var angle = try normalizedAngle(initial, using: &execution)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<64 {
            try execution.consumeWork(1)
            let value = polynomial.value(at: angle)
            if abs(value) <= proofResidualTolerance { break }
            let derivative = polynomial.firstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle * polynomial.coefficientScale else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = try normalizedAngle(angle - step, using: &execution)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
    }



    private static func normalizedAngle(_ angle: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }



    private static func angularDistance(_ first: Double, _ second: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let difference = abs(first - second).truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case referenceSurface
        case parameterizedSurface
        case componentKind
        case lowerAngle
        case upperAngle
        case certificationTolerance
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
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
        , using: &execution)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(referenceSurface, forKey: .referenceSurface)
        try container.encode(parameterizedSurface, forKey: .parameterizedSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedConeConeIntersectionCurve: Codable {}
extension CertifiedConeConeIntersectionCurve.ComponentKind: Codable {}
#endif
