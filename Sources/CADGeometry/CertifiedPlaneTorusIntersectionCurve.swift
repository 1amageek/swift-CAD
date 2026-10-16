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
import Synchronization

public struct CertifiedPlaneTorusIntersectionCurve: Hashable, Sendable {
    public enum ComponentKind: String, Hashable, Sendable {
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

    private struct ThirdOrderDifferentialGeometry {
        let position: Point3D
        let firstDerivative: Vector3D
        let secondDerivative: Vector3D
        let thirdDerivative: Vector3D
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

        var fourthDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 16.0 * abs(cosineDouble)
            ).nextUp
        }

        var globalLowerBound: Double {
            var result = constant.nextDown
            for magnitude in [abs(cosine), abs(sine), abs(cosineDouble)] {
                result = (result - magnitude.nextUp).nextDown
            }
            return result
        }

        func tangentHalfAngleCoefficients(using execution: inout OriginalQueryExecution) throws -> [Double] {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
            return [
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
        let third: Double

        static func constant(_ value: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value,
                first: 0.0,
                second: 0.0,
                third: 0.0
            )
        }

        func adding(
            _ other: ScalarDifferential
        ) -> ScalarDifferential {
            ScalarDifferential(
                value: value + other.value,
                first: first + other.first,
                second: second + other.second,
                third: third + other.third
            )
        }

        func subtracting(
            _ other: ScalarDifferential
        ) -> ScalarDifferential {
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

    private struct InnerTangencyCertificate {
        let minorAngle: Double
        let contactResidualUpperBound: Double
    }

    private struct ValidationCacheKey: Hashable, Sendable {
        let curve: CertifiedPlaneTorusIntersectionCurve
        let tolerance: ModelingTolerance
    }

    // Successful immutable validation retains its actual depth authority.
    private enum ValidationCache {
        struct State: Sendable {
            var entries: [ValidationCacheKey: OriginalGeometryPreparationReceipt] = [:]
            var hasCapacity = false
            var allocatingCapacity = false
        }
        static let storage = Mutex(State())
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try regularComponents(planeSurface: planeSurface, torusSurface: torusSurface, options: options, tolerance: tolerance, using: &execution)
    }

    public static func regularComponents(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [CertifiedPlaneTorusIntersectionCurve] {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        let configuration = try makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let classificationTolerance = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        if let innerTangency = try Self.innerTangencyCertificate(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) {
            try execution.retainStorage(count: 2, stride: MemoryLayout<ComponentKind>.stride)
            return try CertifiedAnalyticCurveEvaluation.map([
                ComponentKind.negativeInnerTangencyBranch,
                .positiveInnerTangencyBranch,
            ], using: &execution) {componentKind, execution in
                try CertifiedPlaneTorusIntersectionCurve(
                    planeSurface: planeSurface,
                    torusSurface: torusSurface,
                    componentKind: componentKind,
                    lowerMinorAngle: innerTangency.minorAngle,
                    upperMinorAngle: innerTangency.minorAngle + 2.0 * Double.pi,
                    tolerance: tolerance
                , using: &execution)
            }
        }
        let boundaries = try boundaryAngles(
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            options: options,
            tolerance: tolerance
        , using: &execution)
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
                , using: &execution),
                CertifiedPlaneTorusIntersectionCurve(
                    planeSurface: planeSurface,
                    torusSurface: torusSurface,
                    componentKind: .positiveFullBranch,
                    lowerMinorAngle: 0.0,
                    upperMinorAngle: 2.0 * Double.pi,
                    tolerance: tolerance
                , using: &execution),
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
        , using: &execution)
        return try CertifiedAnalyticCurveEvaluation.map(intervals, using: &execution) {interval, execution in
            try CertifiedPlaneTorusIntersectionCurve(
                planeSurface: planeSurface,
                torusSurface: torusSurface,
                componentKind: .boundedMinorAngle,
                lowerMinorAngle: interval.lower,
                upperMinorAngle: interval.upper,
                tolerance: tolerance
            , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(planeSurface: planeSurface, torusSurface: torusSurface, componentKind: componentKind, lowerMinorAngle: lowerMinorAngle, upperMinorAngle: upperMinorAngle, tolerance: tolerance, using: &execution)
    }

    public init(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        componentKind: ComponentKind,
        lowerMinorAngle: Double,
        upperMinorAngle: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
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
        , using: &execution)
        maximumResidualUpperBound = try Self.residualUpperBound(
            componentKind: componentKind,
            lowerMinorAngle: lowerMinorAngle,
            upperMinorAngle: upperMinorAngle,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try GeometryStructuralComparisonWork.charge(surface: planeSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: torusSurface, using: &execution)
        let key = ValidationCacheKey(curve: self, tolerance: tolerance)
        if let receipt = ValidationCache.storage.withLock({ $0.entries[key] }) {
            try receipt.withContributionScopes(using: &execution) { execution in
                try receipt.admit(tolerance: tolerance, using: &execution)
            }
            return
        }
        let prepared = try execution.withPreparationScope { execution in
            try validateUncached(tolerance: tolerance, using: &execution)
        }
        let receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: prepared.depth, using: &execution)
        let allocation = ValidationCache.storage.withLock { state -> Bool? in
            if state.allocatingCapacity { return nil }
            if !state.hasCapacity {
                state.allocatingCapacity = true
                return true
            }
            return false
        }
        // A concurrent validated query can skip this optional cache insertion.
        guard let allocation else { return }
        if allocation {
            do {
                try execution.retainStorage(count: 256,
                    stride: MemoryLayout<(ValidationCacheKey, OriginalGeometryPreparationReceipt)>.stride)
                ValidationCache.storage.withLock { state in
                    state.entries.reserveCapacity(256)
                    state.hasCapacity = true
                    state.allocatingCapacity = false
                }
            } catch {
                ValidationCache.storage.withLock { $0.allocatingCapacity = false }
                throw error
            }
        }
        ValidationCache.storage.withLock { state in
            if state.entries.count >= 256 { state.entries.removeAll(keepingCapacity: true) }
            state.entries[key] = receipt
        }
    }

    private func validateUncached(tolerance: ModelingTolerance,
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
                message: "A plane-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        guard lowerMinorAngle.isFinite,
              upperMinorAngle.isFinite,
              upperMinorAngle > lowerMinorAngle,
              upperMinorAngle - lowerMinorAngle <= 2.0 * Double.pi + tolerance.angle else {
            throw GeometryError.invalidAngle(upperMinorAngle - lowerMinorAngle)
        }
        let classificationTolerance = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let certifiedBoundaries = try Self.boundaryAngles(
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution)
            let lowerResidual = abs(configuration.discriminant.value(at: lowerMinorAngle))
            let upperResidual = abs(configuration.discriminant.value(at: upperMinorAngle))
            let midpoint = lowerMinorAngle + (upperMinorAngle - lowerMinorAngle) * 0.5
            let certifiedIntervals = try Self.validIntervals(
                boundaries: certifiedBoundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance,
                tolerance: tolerance
            , using: &execution)
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
            guard let certificate = try Self.innerTangencyCertificate(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution),
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
        , using: &execution)
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
        try execution.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
        for parameter in [
            0.0,
            Double.pi * 0.5,
            Double.pi,
            Double.pi * 1.5,
            2.0 * Double.pi,
        ] {
            try execution.consumeWork(1)
            let point = try point(at: parameter, tolerance: tolerance, using: &execution)
            let planeProjection = try planeSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            let torusProjection = try torusSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func point(
        at parameter: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return try differentialGeometry(at: parameter, tolerance: tolerance, using: &execution).position
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differentialGeometry(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        let geometry = try derivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance
        , using: &execution)
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative,
            secondDerivative: geometry.secondDerivative
        )
    }

    func thirdDerivative(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(at: parameter, tolerance: tolerance, using: &execution)
    }

    func thirdDerivative(
        at parameter: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.consumeWork(1)
        return try derivativesThroughThirdOrder(
            at: parameter,
            tolerance: tolerance
        , using: &execution).thirdDerivative
    }



    private func derivativesThroughThirdOrder(
        at parameter: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ThirdOrderDifferentialGeometry {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let curveParameter: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            curveParameter = try Self.normalizedAngle(parameter, using: &execution)
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard parameterDomain.contains(parameter, tolerance: tolerance.angle) else {
                throw GeometryError.invalidDistance(parameter)
            }
            curveParameter = min(max(parameter, 0.0), 2.0 * Double.pi)
        }
        let minor = try minorAngleDifferential(at: curveParameter, using: &execution)
        let radialScale = configuration.torus.majorRadius
            + configuration.torus.minorRadius * cos(minor.value)
        let radialScaleFirst = -configuration.torus.minorRadius
            * sin(minor.value) * minor.first
        let radialScaleSecond = -configuration.torus.minorRadius * (
            cos(minor.value) * minor.first * minor.first
                + sin(minor.value) * minor.second
        )
        let radialScaleThird = configuration.torus.minorRadius * (
            sin(minor.value) * minor.first * minor.first * minor.first
                - 3.0 * cos(minor.value) * minor.first * minor.second
                - sin(minor.value) * minor.third
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
        let axialTermThird = configuration.torus.minorRadius
            * configuration.axialNormal * (
                -cos(minor.value) * minor.first * minor.first * minor.first
                    - 3.0 * sin(minor.value) * minor.first * minor.second
                    + cos(minor.value) * minor.third
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
        let radialDiscriminantThird = 2.0
            * pow(configuration.radialNormalLength, 2.0)
            * (3.0 * radialScaleFirst * radialScaleSecond
                + radialScale * radialScaleThird)
            - 2.0 * (3.0 * axialTermFirst * axialTermSecond
                + axialTerm * axialTermThird)
        let transverse = try signedSquareRootDifferential(
            value: radialDiscriminant,
            first: radialDiscriminantFirst,
            second: radialDiscriminantSecond,
            third: radialDiscriminantThird,
            minorAngle: minor.value,
            parameter: curveParameter,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let inverseRadialNormalLength = 1.0 / configuration.radialNormalLength
        let along = ScalarDifferential(
            value: -axialTerm * inverseRadialNormalLength,
            first: -axialTermFirst * inverseRadialNormalLength,
            second: -axialTermSecond * inverseRadialNormalLength,
            third: -axialTermThird * inverseRadialNormalLength
        )
        let across = ScalarDifferential(
            value: transverse.value * inverseRadialNormalLength,
            first: transverse.first * inverseRadialNormalLength,
            second: transverse.second * inverseRadialNormalLength,
            third: transverse.third * inverseRadialNormalLength
        )
        let height = ScalarDifferential(
            value: configuration.torus.minorRadius * sin(minor.value),
            first: configuration.torus.minorRadius * cos(minor.value) * minor.first,
            second: configuration.torus.minorRadius * (
                -sin(minor.value) * minor.first * minor.first
                    + cos(minor.value) * minor.second
            ),
            third: configuration.torus.minorRadius * (
                -cos(minor.value) * minor.first * minor.first * minor.first
                    - 3.0 * sin(minor.value) * minor.first * minor.second
                    + cos(minor.value) * minor.third
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
        let thirdDerivative = configuration.radialNormal * along.third
            + configuration.radialPerpendicular * across.third
            + configuration.torus.axis * height.third
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified plane-torus component has a singular differential."
            )
        }
        guard thirdDerivative.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "A certified plane-torus third differential exceeded finite arithmetic."
            )
        }
        return ThirdOrderDifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            thirdDerivative: thirdDerivative
        )
    }

    public func surfaceParameters(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> (plane: SurfaceParameter, torus: SurfaceParameter) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try surfaceParameters(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func surfaceParameters(
        at parameter: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> (plane: SurfaceParameter, torus: SurfaceParameter) {
        try execution.consumeWork(1)
        let point = try point(at: parameter, tolerance: tolerance, using: &execution)
        let planeProjection = try planeSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
        let curveParameter: Double
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            curveParameter = try Self.normalizedAngle(parameter, using: &execution)
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
            majorAngle = try Self.normalizedAngle(rawMajorAngle, using: &execution)
            minorAngle = try Self.normalizedAngle(atan2(
                height,
                radial.length - configuration.torus.majorRadius
            ), using: &execution)
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
            majorAngle = try Self.unwrappedAngle(rawMajorAngle, nearest: nodeMajorAngle, using: &execution)
            minorAngle = lowerMinorAngle + curveParameter
        }
        return (
            SurfaceParameter(u: planeProjection.u, v: planeProjection.v),
            SurfaceParameter(u: majorAngle, v: minorAngle)
        )
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }

    public func boundingBox(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
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
                message: "Plane-torus full-branch differential bounds require a root-free full component."
            )
        }
        let configuration = try Self.makeConfiguration(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            tolerance: tolerance
        , using: &execution)
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
        let discriminantThird =
            discriminant.thirdDerivativeAbsoluteUpperBound
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
        let rootFifthLower = (
            minimumDiscriminant * minimumDiscriminant * rootLower
        ).nextDown
        let rootThird = (
            discriminantThird / (2.0 * rootLower).nextDown
                + 3.0 * discriminantFirst * discriminantSecond
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * discriminantFirst * discriminantFirst
                    * discriminantFirst
                    / (8.0 * rootFifthLower).nextDown
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
        let alongThird = alongFirst
        let acrossFirst = (
            rootFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            rootSecond * inverseRadialNormalLength
        ).nextUp
        let acrossThird = (
            rootThird * inverseRadialNormalLength
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
        let third = hypot(
            hypot(alongThird, acrossThird),
            heightDerivative
        ).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Plane-torus full-branch differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }

    func spatialDifferentialMagnitudeBounds(
        fromParameter lower: Double,
        toParameter upper: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromParameter: lower, toParameter: upper, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromParameter lower: Double,
        toParameter upper: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard lower.isFinite, upper.isFinite, upper > lower else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        switch parameterDomain {
        case let .periodic(period):
            if upper - lower >= period - tolerance.angle {
                return try spatialDifferentialMagnitudeBounds(
                    fromNormalizedFraction: 0.0,
                    toNormalizedFraction: 1.0,
                    tolerance: tolerance
                , using: &execution)
            }
            return try spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: try Self.normalizedAngle(lower, using: &execution) / period,
                toNormalizedFraction: try Self.normalizedAngle(upper, using: &execution) / period,
                tolerance: tolerance
            , using: &execution)
        case let .bounded(domainLower, domainUpper):
            guard parameterDomain.contains(lower, tolerance: tolerance.angle),
                  parameterDomain.contains(upper, tolerance: tolerance.angle) else {
                throw GeometryError.invalidDistance(upper - lower)
            }
            let width = domainUpper - domainLower
            guard width.isFinite, width > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A bounded plane-torus curve requires a finite positive parameter-domain width."
                )
            }
            return try spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(max(
                    (lower - domainLower) / width,
                    0.0
                ), 1.0),
                toNormalizedFraction: min(max(
                    (upper - domainLower) / width,
                    0.0
                ), 1.0),
                tolerance: tolerance
            , using: &execution)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A plane-torus curve cannot have an unbounded parameter domain."
            )
        }
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
                , using: &execution)
                let tail = try spatialDifferentialMagnitudeBounds(
                    fromNormalizedFraction: 0.0,
                    toNormalizedFraction: upperFraction,
                    tolerance: tolerance
                , using: &execution)
                guard let headThird = head.third,
                      let tailThird = tail.third else {
                    throw Self.resourceFailure(
                        tolerance: tolerance,
                        message: "A plane-torus seam span lost its third-order differential certificate."
                    )
                }
                return SpatialDifferentialMagnitudeBounds(
                    first: max(head.first, tail.first),
                    second: max(head.second, tail.second),
                    third: max(headThird, tailThird)
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
            , using: &execution)
        case .boundedMinorAngle:
            return try boundedBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: max(lowerFraction, 0.0),
                toNormalizedFraction: min(upperFraction, 1.0),
                tolerance: tolerance
            , using: &execution)
        case .negativeInnerTangencyBranch,
             .positiveInnerTangencyBranch:
            return try innerTangencyBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            , using: &execution)
        }
    }



    private func innerTangencyBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
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
        , using: &execution)
        guard try Self.innerTangencyCertificate(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) != nil else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "An inner-tangency plane-torus branch lost its nodal certificate."
            )
        }
        let factor = try Self.periodicDoubleRootFactor(
            configuration.discriminant,
            rootAngle: lowerMinorAngle
        , using: &execution)
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
        let rootFifthLower = (
            factorLower * factorLower * rootLower
        ).nextDown
        let rootThird = (
            factorDerivative / (2.0 * rootLower).nextDown
                + 3.0 * factorDerivative * factorDerivative
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factorDerivative * factorDerivative
                    * factorDerivative
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let distanceMagnitude = 2.0.nextUp
        let distanceFirst = 1.0.nextUp
        let distanceSecond = 0.5.nextUp
        let distanceThird = 0.25.nextUp
        let transverseFirst = (
            distanceFirst * rootUpper
                + distanceMagnitude * rootFirst
        ).nextUp
        let transverseSecond = (
            distanceSecond * rootUpper
                + 2.0 * distanceFirst * rootFirst
                + distanceMagnitude * rootSecond
        ).nextUp
        let transverseThird = (
            distanceThird * rootUpper
                + 3.0 * distanceSecond * rootFirst
                + 3.0 * distanceFirst * rootSecond
                + distanceMagnitude * rootThird
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
        let alongThird = alongFirst
        let acrossFirst = (
            transverseFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            transverseSecond * inverseRadialNormalLength
        ).nextUp
        let acrossThird = (
            transverseThird * inverseRadialNormalLength
        ).nextUp
        let heightFirst = configuration.torus.minorRadius.nextUp
        let heightSecond = heightFirst
        let heightThird = heightFirst
        let first = hypot(
            hypot(alongFirst, acrossFirst),
            heightFirst
        ).nextUp
        let second = hypot(
            hypot(alongSecond, acrossSecond),
            heightSecond
        ).nextUp
        let third = hypot(
            hypot(alongThird, acrossThird),
            heightThird
        ).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Inner-tangency plane-torus spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }



    private func boundedBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
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
        , using: &execution)
        let discriminant = configuration.discriminant
        let arithmeticEnvelope = (
            Double.ulpOfOne * discriminant.coefficientScale * 131_072.0
        ).nextUp
        let phaseLower = 2.0 * Double.pi * lowerFraction
        let phaseUpper = 2.0 * Double.pi * upperFraction
        let minorRange = try Self.boundedMinorAngleRange(
            phaseLower: phaseLower,
            phaseUpper: phaseUpper,
            lowerMinorAngle: lowerMinorAngle,
            upperMinorAngle: upperMinorAngle
        , using: &execution)
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
            fourthDerivativeMagnitudeUpperBound:
                discriminant.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { lower, upper, execution in
                try Self.discriminantRange(
                    discriminant,
                    lower: lower,
                    upper: upper,
                    arithmeticEnvelope: arithmeticEnvelope
                , using: &execution)
            },
            tolerance: tolerance,
            label: "Plane-torus bounded branch"
        , using: &execution)
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
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThird = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let halfSpan = (
            (upperMinorAngle - lowerMinorAngle) * 0.5
        ).nextUp
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
        let minorFirst = (
            halfSpan * sineMagnitude
        ).nextUp
        let minorSecond = (
            halfSpan * cosineMagnitude
        ).nextUp
        let minorThird = minorFirst
        let rootByParameterFirst = (rootFirst * minorFirst).nextUp
        let rootByParameterSecond = (
            rootSecond * minorFirst * minorFirst
                + rootFirst * minorSecond
        ).nextUp
        let rootByParameterThird = (
            rootThird * minorFirst * minorFirst * minorFirst
                + 3.0 * rootSecond * minorFirst * minorSecond
                + rootFirst * minorThird
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
        let transverseThird = (
            halfSpan * (
                cosineMagnitude * rootUpper
                    + 3.0 * sineMagnitude * rootByParameterFirst
                    + 3.0 * cosineMagnitude * rootByParameterSecond
                    + sineMagnitude * rootByParameterThird
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
        let alongThird = (
            axialScale
                * (
                    minorFirst * minorFirst * minorFirst
                        + 3.0 * minorFirst * minorSecond
                        + minorThird
                ) * inverseRadialNormalLength
        ).nextUp
        let acrossFirst = (
            transverseFirst * inverseRadialNormalLength
        ).nextUp
        let acrossSecond = (
            transverseSecond * inverseRadialNormalLength
        ).nextUp
        let acrossThird = (
            transverseThird * inverseRadialNormalLength
        ).nextUp
        let heightFirst = (
            configuration.torus.minorRadius * minorFirst
        ).nextUp
        let heightSecond = (
            configuration.torus.minorRadius
                * (minorFirst * minorFirst + minorSecond)
        ).nextUp
        let heightThird = (
            configuration.torus.minorRadius
                * (
                    minorFirst * minorFirst * minorFirst
                        + 3.0 * minorFirst * minorSecond
                        + minorThird
                )
        ).nextUp
        let first = hypot(
            hypot(alongFirst, acrossFirst),
            heightFirst
        ).nextUp
        let second = hypot(
            hypot(alongSecond, acrossSecond),
            heightSecond
        ).nextUp
        let third = hypot(
            hypot(alongThird, acrossThird),
            heightThird
        ).nextUp
        guard first.isFinite, second.isFinite, third.isFinite else {
            throw Self.resourceFailure(
                tolerance: tolerance,
                message: "Bounded plane-torus spatial differentiation exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }



    private func minorAngleDifferential(at parameter: Double,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return ScalarDifferential(
                value: parameter,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
        case .boundedMinorAngle:
            let midpoint = lowerMinorAngle
                + (upperMinorAngle - lowerMinorAngle) * 0.5
            let halfSpan = (upperMinorAngle - lowerMinorAngle) * 0.5
            return ScalarDifferential(
                value: midpoint - halfSpan * cos(parameter),
                first: halfSpan * sin(parameter),
                second: halfSpan * cos(parameter),
                third: -halfSpan * sin(parameter)
            )
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            return ScalarDifferential(
                value: lowerMinorAngle + parameter,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
        }
    }



    private func signedSquareRootDifferential(
        value: Double,
        first: Double,
        second: Double,
        third: Double,
        minorAngle: Double,
        parameter: Double,
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
            , using: &execution)
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
                        / (4.0 * root * root * root),
                third: factor.third / (2.0 * root)
                    - 3.0 * factor.first * factor.second
                        / (4.0 * root * root * root)
                    + 3.0 * factor.first * factor.first * factor.first
                        / (8.0 * pow(root, 5.0))
            )
            let minor = try minorAngleDifferential(at: parameter, using: &execution)
            let rootByParameter = ScalarDifferential(
                value: rootByMinor.value,
                first: rootByMinor.first * minor.first,
                second: rootByMinor.second * minor.first * minor.first
                    + rootByMinor.first * minor.second,
                third: rootByMinor.third
                        * minor.first * minor.first * minor.first
                    + 3.0 * rootByMinor.second
                        * minor.first * minor.second
                    + rootByMinor.first * minor.third
            )
            let sine = ScalarDifferential(
                value: sin(parameter),
                first: cos(parameter),
                second: -sin(parameter),
                third: -cos(parameter)
            )
            let result = try Self.product(
                sine,
                rootByParameter
            , using: &execution).scaled(
                by: (upperMinorAngle - lowerMinorAngle) * 0.5
            )
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
                throw Self.resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded plane-torus regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        if componentKind == .negativeInnerTangencyBranch
            || componentKind == .positiveInnerTangencyBranch {
            let factorPolynomial = try Self.periodicDoubleRootFactor(
                configuration.discriminant,
                rootAngle: lowerMinorAngle
            , using: &execution)
            let factor = ScalarDifferential(
                value: factorPolynomial.value(at: parameter),
                first: factorPolynomial.derivative(at: parameter),
                second: factorPolynomial.secondDerivative(at: parameter),
                third: try factorPolynomial.thirdDerivative(at: parameter)
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
                        / (4.0 * root * root * root),
                third: factor.third / (2.0 * root)
                    - 3.0 * factor.first * factor.second
                        / (4.0 * root * root * root)
                    + 3.0 * factor.first * factor.first * factor.first
                        / (8.0 * pow(root, 5.0))
            )
            let halfParameter = parameter * 0.5
            let periodicDistance = ScalarDifferential(
                value: 2.0 * sin(halfParameter),
                first: cos(halfParameter),
                second: -0.5 * sin(halfParameter),
                third: -0.25 * cos(halfParameter)
            )
            let result = try Self.product(
                periodicDistance,
                rootDifferential
            , using: &execution).scaled(by: branchSign)
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
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
                - first * first / (4.0 * signedValue * signedValue * signedValue),
            third: third / (2.0 * signedValue)
                - 3.0 * first * second
                    / (4.0 * signedValue * signedValue * signedValue)
                + 3.0 * first * first * first
                    / (8.0 * pow(signedValue, 5.0))
        )
    }



    private func regularizedDiscriminantFactorDifferential(
        at minorAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
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
        let dividedDifference = try Self.trigonometricDividedDifference(
            discriminant,
            value: minorAngle,
            endpoint: endpoint
        , using: &execution)
        let numerator = usesLowerEndpoint
            ? dividedDifference.adding(.constant(-correctionSlope))
            : ScalarDifferential.constant(correctionSlope)
                .subtracting(dividedDifference)
        let denominator = usesLowerEndpoint
            ? ScalarDifferential(
                value: upperMinorAngle - minorAngle,
                first: -1.0,
                second: 0.0,
                third: 0.0
            )
            : ScalarDifferential(
                value: minorAngle - lowerMinorAngle,
                first: 1.0,
                second: 0.0,
                third: 0.0
            )
        return try Self.quotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded plane-torus regularized factor lost its opposite-endpoint denominator."
        , using: &execution)
    }



    private static func periodicDoubleRootFactor(
        _ polynomial: TrigonometricPolynomial,
        rootAngle: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> TrigonometricPolynomial {
        try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        var result = ScalarDifferential.constant(0.0)
        try execution.retainStorage(count: 2, stride: MemoryLayout<(order: Double, cosine: Double, sine: Double)>.stride)
        for harmonic in [
            (order: 1.0, cosine: polynomial.cosine, sine: polynomial.sine),
            (order: 2.0, cosine: polynomial.cosineDouble, sine: 0.0),
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



    private static func quotient(
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



    private static func makeConfiguration(
        planeSurface: Surface3D,
        torusSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.consumeWork(1)
        try planeSurface.validate(tolerance: tolerance, using: &execution)
        try torusSurface.validate(tolerance: tolerance, using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
    }



    private static func innerTangencyCertificate(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> InnerTangencyCertificate? {
        try execution.consumeWork(1)
        let radialSupport = configuration.torus.majorRadius
            * configuration.radialNormalLength
        let innerSupport = radialSupport - configuration.torus.minorRadius
        guard innerSupport > tolerance.distance else { return nil }

        let arithmeticLengthTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 32_768.0
        let offsetResidual = abs(abs(configuration.centerDistance) - innerSupport)
        guard offsetResidual <= arithmeticLengthTolerance else { return nil }

        let centerSign = configuration.centerDistance >= 0.0 ? 1.0 : -1.0
        let minorAngle = try normalizedAngle(atan2(
            centerSign * configuration.axialNormal,
            -configuration.radialNormalLength
        ), using: &execution)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
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
            coefficients: (try polynomial.tangentHalfAngleCoefficients(using: &execution))
        , using: &execution)
        guard tangentRoots.count <= options.maximumSeedCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Plane-torus section exceeded its quartic boundary-root limit."
            )
        }
        var values = try CertifiedAnalyticCurveEvaluation.map(tangentRoots, using: &execution) {element, execution in
            try normalizedAngle(2.0 * atan(element.value), using: &execution)
        }
        var valuesCapacity = values.count
        if abs(polynomial.value(at: Double.pi)) <= classificationTolerance {
            try CertifiedAnalyticCurveEvaluation.append(Double.pi, to: &values, using: &execution, capacity: &valuesCapacity)
        }
        values = try CertifiedAnalyticCurveEvaluation.map(values, using: &execution) {element, execution in
            try refinedAngle(
                element,
                polynomial: polynomial,
                maximumIterations: options.maximumIterations,
                residualTolerance: classificationTolerance * 1.0e-8,
                tolerance: tolerance
            , using: &execution)
         }
        values = try CertifiedAnalyticCurveEvaluation.filter(values, using: &execution) { value, execution in
            abs(polynomial.value(at: value)) <= classificationTolerance * 16.0
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
        let derivativeThreshold = max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne
                * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
        for angle in result {
            try execution.consumeWork(1)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> [(lower: Double, upper: Double)] {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        var result: [(lower: Double, upper: Double)] = []
        var resultCapacity = result.count
        for index in boundaries.indices {
            try execution.consumeWork(1)
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + period
            let midpoint = lower + (upper - lower) * 0.5
            let value = configuration.discriminant.value(at: midpoint)
            if value > classificationTolerance {
                try CertifiedAnalyticCurveEvaluation.append((lower, upper), to: &result, using: &execution, capacity: &resultCapacity)
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let machineBound = Double.ulpOfOne
            * configuration.characteristicLength * 65_536.0
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            return machineBound
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            guard let certificate = try innerTangencyCertificate(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) else {
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
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var angle = try normalizedAngle(initial, using: &execution)
        let effectiveResidual = max(
            residualTolerance,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<maximumIterations {
            try execution.consumeWork(1)
            let value = polynomial.value(at: angle)
            if abs(value) <= effectiveResidual { break }
            let derivative = polynomial.derivative(at: angle)
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



    private static func boundedMinorAngleRange(
        phaseLower: Double,
        phaseUpper: Double,
        lowerMinorAngle: Double,
        upperMinorAngle: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let midpoint = lowerMinorAngle
            + (upperMinorAngle - lowerMinorAngle) * 0.5
        let halfSpan = (upperMinorAngle - lowerMinorAngle) * 0.5
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
            (values.min() ?? lowerMinorAngle).nextDown,
            (values.max() ?? upperMinorAngle).nextUp
        )
    }



    private static func discriminantRange(
        _ discriminant: TrigonometricPolynomial,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
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
                break
            }
        }
        return result.nextUp
    }



    private static func normalizedAngle(_ angle: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }



    private static func unwrappedAngle(_ angle: Double, nearest reference: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        return angle + round((reference - angle) / period) * period
    }



    private static func angularDistance(_ first: Double, _ second: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case planeSurface
        case torusSurface
        case componentKind
        case lowerMinorAngle
        case upperMinorAngle
        case certificationTolerance
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
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
        , using: &execution)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planeSurface, forKey: .planeSurface)
        try container.encode(torusSurface, forKey: .torusSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerMinorAngle, forKey: .lowerMinorAngle)
        try container.encode(upperMinorAngle, forKey: .upperMinorAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedPlaneTorusIntersectionCurve: Codable {}
extension CertifiedPlaneTorusIntersectionCurve.ComponentKind: Codable {}
#endif
