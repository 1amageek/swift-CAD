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

public struct CertifiedSphereConeIntersectionCurve: Hashable, Sendable {
    public enum ComponentKind: String, Hashable, Sendable {
        case negativeFullBranch
        case positiveFullBranch
        case boundedAngularInterval
        case negativeOpenAngularInterval
        case positiveOpenAngularInterval
        case apexReducedAngularInterval
    }

    enum ApexContactTopology {
        case isolatedPointAndLoop
        case nodeIntervals([ClosedRange<Double>])
    }

    private enum OpenEndpointStructure: Equatable {
        case rootFree
        case lowerSimpleRoot
        case upperSimpleRoot
        case twoSimpleRoots
        case lowerDoubleRoot
        case upperDoubleRoot
        case twoDoubleRoots
        case lowerSimpleUpperDouble
        case lowerDoubleUpperSimple
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

        var firstDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 2.0 * abs(cosineDouble)
                    + 2.0 * abs(sineDouble)
            ).nextUp
        }

        var absoluteUpperBound: Double {
            (
                abs(constant)
                    + abs(cosine)
                    + abs(sine)
                    + abs(cosineDouble)
                    + abs(sineDouble)
            ).nextUp
        }

        var secondDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 4.0 * abs(cosineDouble)
                    + 4.0 * abs(sineDouble)
            ).nextUp
        }

        var thirdDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 8.0 * abs(cosineDouble)
                    + 8.0 * abs(sineDouble)
            ).nextUp
        }

        var fourthDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 16.0 * abs(cosineDouble)
                    + 16.0 * abs(sineDouble)
            ).nextUp
        }

        var fifthDerivativeAbsoluteUpperBound: Double {
            (
                abs(cosine)
                    + abs(sine)
                    + 32.0 * abs(cosineDouble)
                    + 32.0 * abs(sineDouble)
            ).nextUp
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }

        func derivative(at angle: Double) -> Double {
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

        func derivative(order: Int, at angle: Double) -> Double {
            guard order > 0 else { return value(at: angle) }
            let phase = Double(order) * Double.pi * 0.5
            return cosine * cos(angle + phase)
                + sine * sin(angle + phase)
                + pow(2.0, Double(order)) * (
                cosineDouble * cos(2.0 * angle + phase)
                    + sineDouble * sin(2.0 * angle + phase)
            )
        }
    }

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let cone: Cone
        let axialCenter: Double
        let radialCosine: Double
        let radialSine: Double
        let quadraticA: Double
        let quadraticC: Double

        var radialAmplitude: Double {
            hypot(radialCosine, radialSine)
        }

        var slope: Double {
            tan(cone.halfAngle)
        }

        var characteristicLength: Double {
            max(
                (sphere.center - cone.apex).length,
                sphere.radius,
                1.0
            )
        }

        var radicandPolynomial: TrigonometricPolynomial {
            let cosine = slope * radialCosine
            let sine = slope * radialSine
            return TrigonometricPolynomial(
                constant: axialCenter * axialCenter
                    + (cosine * cosine + sine * sine) * 0.5
                    - quadraticA * quadraticC,
                cosine: 2.0 * axialCenter * cosine,
                sine: 2.0 * axialCenter * sine,
                cosineDouble: (cosine * cosine - sine * sine) * 0.5,
                sineDouble: cosine * sine
            )
        }

        func halfLinear(at angle: Double) -> Double {
            axialCenter + slope * (
                radialCosine * cos(angle) + radialSine * sin(angle)
            )
        }

        func halfLinearFirstDerivative(at angle: Double) -> Double {
            slope * (-radialCosine * sin(angle) + radialSine * cos(angle))
        }

        func halfLinearSecondDerivative(at angle: Double) -> Double {
            slope * (-radialCosine * cos(angle) - radialSine * sin(angle))
        }

        func radicand(at angle: Double) -> Double {
            let linear = halfLinear(at: angle)
            return linear * linear - quadraticA * quadraticC
        }

        func radicandFirstDerivative(at angle: Double) -> Double {
            2.0 * halfLinear(at: angle)
                * halfLinearFirstDerivative(at: angle)
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

        func scaled(by scale: Double) -> ScalarDifferential {
            ScalarDifferential(
                value: value * scale,
                first: first * scale,
                second: second * scale,
                third: third * scale
            )
        }
    }

    private struct PoleContact {
        let angle: Double
        let branch: Double
    }

    public let sphereSurface: Surface3D
    public let coneSurface: Surface3D
    public let componentKind: ComponentKind
    public let lowerAngle: Double
    public let upperAngle: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double
    public let originalNodeTraversal: OriginalSphereConeNodeTraversal?

    public init(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(sphereSurface: sphereSurface, coneSurface: coneSurface, componentKind: componentKind, lowerAngle: lowerAngle, upperAngle: upperAngle, tolerance: tolerance, using: &execution)
    }

    public init(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        originalNodeTraversal=nil
        self.sphereSurface = sphereSurface
        self.coneSurface = coneSurface
        self.componentKind = componentKind
        self.lowerAngle = lowerAngle
        self.upperAngle = upperAngle
        certificationTolerance = tolerance
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
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

    init<A:ExactScalarAdmission & ~Copyable>(node:OriginalSphereConeNodeTraversal,tolerance:ModelingTolerance,
        using a:inout A) throws {
        try a.checkpoint();try tolerance.validate();try a.admitDepth(value:node.proofDepth.value,coefficient:node.proofDepth.coefficient)
        let input=node.source.original
        sphereSurface=node.source.sphereIsFirst ? input.first:input.second
        coneSurface=node.source.sphereIsFirst ? input.second:input.first
        componentKind = .apexReducedAngularInterval
        lowerAngle=Double(node.branch)*Double.pi;upperAngle=Double(node.branch+1)*Double.pi
        certificationTolerance=tolerance;originalNodeTraversal=node
        // Reuse fixed numerical metadata; the retained source theorem owns equality.
        try a.consumeWork(1)
        let configuration=try Self.makeConfiguration(sphereSurface:sphereSurface,coneSurface:coneSurface,tolerance:tolerance,using:&a)
        maximumResidualUpperBound=try Self.residualUpperBound(componentKind:componentKind,lowerAngle:lowerAngle,
            upperAngle:upperAngle,configuration:configuration,tolerance:tolerance,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self));try a.checkpoint()
    }

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [(angle: Double, branch: Double)] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try poleSplitNodes(sphereSurface: sphereSurface, coneSurface: coneSurface, tolerance: tolerance, using: &execution)
    }

    static func poleSplitNodes(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [(angle: Double, branch: Double)] {
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        try rejectConeApexContact(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        return try CertifiedAnalyticCurveEvaluation.map(spherePoleContacts(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution), using: &execution) {element, execution in (angle: element.angle, branch: element.branch) }
    }

    static func apexContactTopology(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ApexContactTopology? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try apexContactTopology(sphereSurface: sphereSurface, coneSurface: coneSurface, tolerance: tolerance, using: &execution)
    }

    static func apexContactTopology(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ApexContactTopology? {
        try execution.consumeWork(1)
        let configuration = try makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let residualBound = try apexReductionResidualUpperBound(
            configuration: configuration
        , using: &execution)
        guard residualBound <= tolerance.distance else {
            return nil
        }
        let boundaries = try apexBoundaryAngles(
            configuration: configuration,
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
                message: "A sphere-cone curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        if let node=originalNodeTraversal {
            let input=node.source.original
            guard sphereSurface==(node.source.sphereIsFirst ? input.first:input.second),
                coneSurface==(node.source.sphereIsFirst ? input.second:input.first),
                componentKind == .apexReducedAngularInterval,node.branch==0 || node.branch==1,
                lowerAngle==Double(node.branch)*Double.pi,upperAngle==Double(node.branch+1)*Double.pi,
                maximumResidualUpperBound.isFinite,maximumResidualUpperBound<=tolerance.distance else {
                throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,message:"A generated node curve must retain its original normalized traversal.")
            }
            return
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        if componentKind != .apexReducedAngularInterval {
            try Self.rejectConeApexContact(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }
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
        let boundaries = try Self.boundaryAngles(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let branch = componentKind == .negativeFullBranch ? -1.0 : 1.0
            let hasSpherePoleContact = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution).contains { $0.branch == branch }
            let minimumRadicand = try Self.minimumRadicand(configuration: configuration, using: &execution)
            guard abs(lowerAngle) <= tolerance.angle,
                  abs(upperAngle - 2.0 * Double.pi) <= tolerance.angle,
                  boundaries.isEmpty,
                  hasSpherePoleContact == false,
                  minimumRadicand > classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: minimumRadicand,
                    tolerance: tolerance,
                    message: "A full sphere-cone branch requires a positive root-free, sphere-pole-free radicand domain."
                )
            }
        case .boundedAngularInterval:
            let validIntervals = try Self.validIntervals(
                boundaries: boundaries,
                configuration: configuration,
                classificationTolerance: classificationTolerance
            , using: &execution)
            let matchesCompleteInterval = validIntervals.contains { interval in
                abs(interval.lower - lowerAngle) <= tolerance.angle
                    && abs(interval.upper - upperAngle) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerSlope = abs(configuration.radicandFirstDerivative(at: lowerAngle))
            let upperSlope = abs(configuration.radicandFirstDerivative(at: upperAngle))
            let containsSpherePole = try Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution).contains { contact in
                let adjusted = try Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                , using: &execution)
                return adjusted >= lowerAngle - tolerance.angle
                    && adjusted <= upperAngle + tolerance.angle
            }
            guard matchesCompleteInterval,
                  lowerResidual <= classificationTolerance * 16.0,
                  upperResidual <= classificationTolerance * 16.0,
                  lowerSlope > classificationTolerance,
                  upperSlope > classificationTolerance,
                  containsSpherePole == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(lowerResidual, upperResidual),
                    tolerance: tolerance,
                    message: "A bounded sphere-cone component is not a complete simple-root interval."
                )
            }
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let branch = componentKind == .negativeOpenAngularInterval ? -1.0 : 1.0
            let contacts = try CertifiedAnalyticCurveEvaluation.filter(Self.spherePoleContacts(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution), using: &execution) {element, execution in element.branch == branch }
            let lowerIsPole = try contacts.contains {
                try Self.angularDistance($0.angle, lowerAngle, using: &execution) <= tolerance.angle
            }
            let upperIsPole = try contacts.contains {
                try Self.angularDistance($0.angle, upperAngle, using: &execution) <= tolerance.angle
            }
            let lowerResidual = abs(configuration.radicand(at: lowerAngle))
            let upperResidual = abs(configuration.radicand(at: upperAngle))
            let lowerIsRoot = lowerResidual <= classificationTolerance * 16.0
            let upperIsRoot = upperResidual <= classificationTolerance * 16.0
            let hasInteriorPole = try contacts.contains { contact in
                let adjusted = try Self.adjustedAngle(
                    contact.angle,
                    inside: lowerAngle...upperAngle
                , using: &execution)
                return adjusted > lowerAngle + tolerance.angle
                    && adjusted < upperAngle - tolerance.angle
            }
            let minimumRadicand = try Self.minimumRadicand(
                from: lowerAngle,
                to: upperAngle,
                configuration: configuration
            , using: &execution)
            guard lowerIsPole || lowerIsRoot,
                  upperIsPole || upperIsRoot,
                  hasInteriorPole == false,
                  minimumRadicand >= -classificationTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: max(
                        max(lowerResidual, upperResidual),
                        max(0.0, -minimumRadicand)
                    ),
                    tolerance: tolerance,
                    message: "An open sphere-cone branch is not one complete nonnegative interval between consecutive certified graph nodes."
                )
            }
            let endpointStructure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            guard endpointStructure != .twoDoubleRoots,
                  endpointStructure != .lowerSimpleUpperDouble,
                  endpointStructure != .lowerDoubleUpperSimple else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "A regular sphere-cone pole-split graph edge cannot combine endpoint root multiplicities."
                )
            }
        case .apexReducedAngularInterval:
            guard let topology = try Self.apexContactTopology(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            , using: &execution) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: try Self.apexReductionResidualUpperBound(
                        configuration: configuration
                    , using: &execution),
                    tolerance: tolerance,
                    message: "An apex-reduced sphere-cone component requires a certified cone-apex contact."
                )
            }
            let matchesTopology: Bool
            switch topology {
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
                    message: "An apex-reduced sphere-cone component must cover one complete non-apex root interval."
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
                message: "A sphere-cone curve exceeded its certified geometric residual."
            )
        }
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            try execution.consumeWork(1)
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            let sphereProjection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            let coneProjection = try coneSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            let residual = max(sphereProjection.residual, coneProjection.residual)
            guard residual <= maximumResidualUpperBound else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A sphere-cone curve failed its algebraic reconstruction check."
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
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let normalizedFraction = min(max(fraction, 0.0), 1.0)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let angle = try angleDifferential(
            at: normalizedFraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let slant = try slantDifferential(
            angle: angle,
            fraction: normalizedFraction,
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
                message: "A certified sphere-cone curve reaches the cone apex."
            )
        }
        let basis = try analyticOrthonormalBasis(
            configuration.cone.axis,
            tolerance: tolerance
        )
        let cosine = cos(configuration.cone.halfAngle)
        let sine = sin(configuration.cone.halfAngle)
        let radial = basis.u * cos(angle.value) + basis.v * sin(angle.value)
        let radialFirst = -basis.u * sin(angle.value) + basis.v * cos(angle.value)
        let radialSecond = -radial
        let radialThird = -radialFirst
        let generator = configuration.cone.axis * cosine + radial * sine
        let generatorFirst = radialFirst * sine
        let generatorSecond = radialSecond * sine
        let generatorThird = radialThird * sine
        let composedGeneratorFirst = generatorFirst * angle.first
        let composedGeneratorSecond = generatorSecond
                * (angle.first * angle.first)
            + generatorFirst * angle.second
        let composedGeneratorThird = generatorThird
                * (angle.first * angle.first * angle.first)
            + generatorSecond * (3.0 * angle.first * angle.second)
            + generatorFirst * angle.third
        let position:Point3D
        if originalNodeTraversal != nil && (normalizedFraction==0 || normalizedFraction==1) { position=configuration.cone.apex }
        else { position=configuration.cone.apex + generator * slant.value }
        let firstDerivative = composedGeneratorFirst * slant.value
            + generator * slant.first
        let secondDerivative = composedGeneratorSecond * slant.value
            + composedGeneratorFirst * (2.0 * slant.first)
            + generator * slant.second
        let thirdDerivative = composedGeneratorThird * slant.value
            + composedGeneratorSecond * (3.0 * slant.first)
            + composedGeneratorFirst * (3.0 * slant.second)
            + generator * slant.third
        guard firstDerivative.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: firstDerivative.length,
                tolerance: tolerance,
                message: "A certified sphere-cone component has a singular differential."
            )
        }
        guard thirdDerivative.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A certified sphere-cone third differential exceeded finite arithmetic."
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
        guard surface == sphereSurface || surface == coneSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A sphere-cone pcurve was requested on an unrelated surface."
            )
        }
        if surface == coneSurface {
            let normalizedFraction = min(max(fraction, 0.0), 1.0)
            let configuration = try Self.makeConfiguration(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            , using: &execution)
            let angle = try angleDifferential(
                at: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let slant = try slantDifferential(
                angle: angle,
                fraction: normalizedFraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            return SurfaceParameter(u: angle.value, v: slant.value)
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
        if surface == sphereSurface {
            return try sphereParameter(
                for: point,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
        throw KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "A sphere-cone pcurve was requested on an unrelated surface."
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
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let radius = configuration.sphere.radius + tolerance.distance
        return try BoundingBox3D(
            minimum: Point3D(
                x: configuration.sphere.center.x - radius,
                y: configuration.sphere.center.y - radius,
                z: configuration.sphere.center.z - radius
            ),
            maximum: Point3D(
                x: configuration.sphere.center.x + radius,
                y: configuration.sphere.center.y + radius,
                z: configuration.sphere.center.z + radius
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
                message: "Root-free sphere-cone differential bounds require a full branch."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let arithmeticEnvelope = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let minimumRadicand = (
            try Self.minimumRadicand(configuration: configuration, using: &execution)
                - arithmeticEnvelope
        ).nextDown
        guard minimumRadicand > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone differential certificate lost its positive radicand lower bound."
            )
        }

        let amplitude = configuration.radialAmplitude.nextUp
        let harmonicMagnitude = try upperProduct(
            abs(configuration.slope),
            amplitude,
            tolerance: tolerance
        , using: &execution)
        let halfLinearMagnitude = try upperSum(
            abs(configuration.axialCenter),
            harmonicMagnitude,
            tolerance: tolerance
        , using: &execution)
        let radicandConstantMagnitude = try upperProduct(
            configuration.quadraticA,
            abs(configuration.quadraticC),
            tolerance: tolerance
        , using: &execution)
        let maximumRadicand = try upperSum(
            try upperProduct(
                halfLinearMagnitude,
                halfLinearMagnitude,
                tolerance: tolerance
            , using: &execution),
            radicandConstantMagnitude,
            tolerance: tolerance
        , using: &execution)
        let radicandFirst = try upperProduct(
            2.0,
            try upperProduct(
                halfLinearMagnitude,
                harmonicMagnitude,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let radicandSecond = try upperProduct(
            2.0,
            try upperSum(
                try upperProduct(
                    harmonicMagnitude,
                    harmonicMagnitude,
                    tolerance: tolerance
                , using: &execution),
                try upperProduct(
                    halfLinearMagnitude,
                    harmonicMagnitude,
                    tolerance: tolerance
                , using: &execution),
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let radicandThird = (
            2.0 * (
                3.0 * harmonicMagnitude * harmonicMagnitude
                    + halfLinearMagnitude * harmonicMagnitude
            )
        ).nextUp
        let rootLower = sqrt(minimumRadicand).nextDown
        let rootUpper = sqrt(maximumRadicand).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone square-root certificate lost its finite positive margin."
            )
        }
        let rootFirst = try upperQuotient(
            radicandFirst,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (
            (rootLower * rootLower).nextDown * rootLower
        ).nextDown
        let rootSecond = try upperSum(
            try upperQuotient(
                radicandSecond,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    radicandFirst,
                    radicandFirst,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            minimumRadicand * minimumRadicand * rootLower
        ).nextDown
        let rootThird = (
            radicandThird / (2.0 * rootLower).nextDown
                + 3.0 * radicandFirst * radicandSecond
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * radicandFirst * radicandFirst * radicandFirst
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp

        let rawDenominator = configuration.quadraticA
            * cos(configuration.cone.halfAngle)
        let denominatorEnvelope = max(
            Double.ulpOfOne * abs(rawDenominator) * 4_096.0,
            tolerance.relative * abs(rawDenominator) * 1.0e-6
        )
        let denominatorLower = (
            abs(rawDenominator) - denominatorEnvelope
        ).nextDown
        guard denominatorLower > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free sphere-cone slant denominator lost its positive margin."
            )
        }
        let slantMagnitude = try upperQuotient(
            try upperSum(
                halfLinearMagnitude,
                rootUpper,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantFirst = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootFirst,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantSecond = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootSecond,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantThird = try upperQuotient(
            try upperSum(
                harmonicMagnitude,
                rootThird,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)

        let sine = sin(configuration.cone.halfAngle).nextUp
        let angularFirst = hypot(
            try upperProduct(
                sine,
                slantMagnitude,
                tolerance: tolerance
            , using: &execution),
            slantFirst
        ).nextUp
        let angularSecond = try upperSum(
            try upperProduct(
                sine,
                slantMagnitude,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                try upperProduct(
                    2.0 * sine,
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                slantSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let angularThird = (
            sine * slantMagnitude
                + 3.0 * sine * slantFirst
                + 3.0 * sine * slantSecond
                + slantThird
        ).nextUp
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = try upperProduct(
            period,
            period,
            tolerance: tolerance
        , using: &execution)
        let periodCubed = try upperProduct(
            periodSquared,
            period,
            tolerance: tolerance
        , using: &execution)
        return SpatialDifferentialMagnitudeBounds(
            first: try upperProduct(
                period,
                angularFirst,
                tolerance: tolerance
            , using: &execution),
            second: try upperProduct(
                periodSquared,
                angularSecond,
                tolerance: tolerance
            , using: &execution),
            third: try upperProduct(
                periodCubed,
                angularThird,
                tolerance: tolerance
            , using: &execution)
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
                message: "Bounded sphere-cone differential bounds require a valid complete simple-root source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = (period * period).nextUp
        let periodCubed = (periodSquared * period).nextUp
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
            lowerValue: radicand.value(at: lowerAngle),
            upperValue: radicand.value(at: upperAngle),
            lowerDerivative: radicand.derivative(at: lowerAngle),
            upperDerivative: radicand.derivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper, execution in
                try Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                , using: &execution)
            },
            tolerance: tolerance,
            label: "Sphere-cone bounded branch"
        , using: &execution)
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A bounded sphere-cone regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
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
        let angleFirst = (
            halfSpan * period * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * periodSquared * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * periodCubed * sineMagnitude
        ).nextUp
        let signedRootMagnitude = (
            halfSpan * sineMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            halfSpan * (
                period * cosineMagnitude * rootUpper
                    + sineMagnitude * rootFirstByAngle * angleFirst
            )
        ).nextUp
        let signedRootSecond = (
            halfSpan * (
                periodSquared * sineMagnitude * rootUpper
                    + 2.0 * period * cosineMagnitude
                        * rootFirstByAngle * angleFirst
                    + sineMagnitude * (
                        rootSecondByAngle * angleFirst * angleFirst
                            + rootFirstByAngle * angleSecond
                    )
            )
        ).nextUp
        let rootByFractionFirst = (
            rootFirstByAngle * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * angleFirst * angleFirst
                + rootFirstByAngle * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * angleFirst * angleFirst * angleFirst
                + 3.0 * rootSecondByAngle * angleFirst * angleSecond
                + rootFirstByAngle * angleThird
        ).nextUp
        let prefixMagnitude = (halfSpan * sineMagnitude).nextUp
        let prefixFirst = (
            halfSpan * period * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * periodSquared * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * periodCubed * cosineMagnitude
        ).nextUp
        let signedRootThird = (
            prefixThird * rootUpper
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixMagnitude * rootByFractionThird
        ).nextUp
        let harmonicMagnitude = (
            abs(configuration.slope) * configuration.radialAmplitude
        ).nextUp
        let halfLinearMagnitude = (
            abs(configuration.axialCenter) + harmonicMagnitude
        ).nextUp
        let halfLinearFirst = (
            harmonicMagnitude * angleFirst
        ).nextUp
        let halfLinearSecond = (
            harmonicMagnitude
                * (angleFirst * angleFirst + angleSecond)
        ).nextUp
        let halfLinearThird = (
            harmonicMagnitude * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let slantMagnitude = try upperQuotient(
            try upperSum(
                halfLinearMagnitude,
                signedRootMagnitude,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantFirst = try upperQuotient(
            try upperSum(
                halfLinearFirst,
                signedRootFirst,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantSecond = try upperQuotient(
            try upperSum(
                halfLinearSecond,
                signedRootSecond,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        let slantThird = try upperQuotient(
            try upperSum(
                halfLinearThird,
                signedRootThird,
                tolerance: tolerance
            , using: &execution),
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            slantMagnitude: slantMagnitude,
            slantFirst: slantFirst,
            slantSecond: slantSecond,
            slantThird: slantThird,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
                message: "Apex-reduced sphere-cone differential bounds require a certified apex-contact component."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let angleFirst = (upperAngle - lowerAngle).nextUp
        let harmonicMagnitude = (
            abs(configuration.slope) * configuration.radialAmplitude
        ).nextUp
        let halfLinearMagnitude = (
            abs(configuration.axialCenter) + harmonicMagnitude
        ).nextUp
        let halfLinearFirst = (
            harmonicMagnitude * angleFirst
        ).nextUp
        let halfLinearSecond = (
            harmonicMagnitude * angleFirst * angleFirst
        ).nextUp
        let halfLinearThird = (
            harmonicMagnitude * angleFirst * angleFirst * angleFirst
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let scale = try upperQuotient(
            2.0,
            denominatorLower,
            tolerance: tolerance
        , using: &execution)
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: 0.0,
            angleThird: 0.0,
            slantMagnitude: try upperProduct(
                scale,
                halfLinearMagnitude,
                tolerance: tolerance
            , using: &execution),
            slantFirst: try upperProduct(
                scale,
                halfLinearFirst,
                tolerance: tolerance
            , using: &execution),
            slantSecond: try upperProduct(
                scale,
                halfLinearSecond,
                tolerance: tolerance
            , using: &execution),
            slantThird: try upperProduct(
                scale,
                halfLinearThird,
                tolerance: tolerance
            , using: &execution),
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try openBranchSpatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func openBranchSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard componentKind == .negativeOpenAngularInterval
                || componentKind == .positiveOpenAngularInterval,
              lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction > lowerFraction else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Open sphere-cone differential bounds require a valid certified graph-edge source range."
            )
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let lower = max(lowerFraction, 0.0)
        let upper = min(upperFraction, 1.0)
        switch try openEndpointStructure(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) {
        case .rootFree:
            return try rootFreeOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .lowerSimpleRoot:
            return try oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: true,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .upperSimpleRoot:
            return try oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: false,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .twoSimpleRoots:
            return try twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .lowerDoubleRoot:
            return try oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: true,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .upperDoubleRoot:
            return try oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
                rootAtLower: false,
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        case .twoDoubleRoots, .lowerSimpleUpperDouble,
             .lowerDoubleUpperSimple:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A validated regular sphere-cone open branch reached an inconsistent endpoint-root structure."
            )
        }
    }



    private func rootFreeOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let span = (upperAngle - lowerAngle).nextUp
        let requestedLower = lowerAngle + span * lowerFraction
        let requestedUpper = lowerAngle + span * upperFraction
        let envelope = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let minimum = (
            try Self.minimumRadicand(
                from: requestedLower,
                to: requestedUpper,
                configuration: configuration
            , using: &execution) - envelope
        ).nextDown
        let radicand = configuration.radicandPolynomial
        let maximum = (
            radicand.absoluteUpperBound + envelope
        ).nextUp
        guard minimum > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A root-free open sphere-cone differential certificate lost its positive radicand margin."
            )
        }
        let rootLower = sqrt(minimum).nextDown
        let rootUpper = sqrt(maximum).nextUp
        let rootFirstByAngle = try upperQuotient(
            radicand.firstDerivativeAbsoluteUpperBound,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (minimum * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                radicand.secondDerivativeAbsoluteUpperBound,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    radicand.firstDerivativeAbsoluteUpperBound,
                    radicand.firstDerivativeAbsoluteUpperBound,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            minimum * minimum * rootLower
        ).nextDown
        let rootThirdByAngle = (
            radicand.thirdDerivativeAbsoluteUpperBound
                    / (2.0 * rootLower).nextDown
                + 3.0 * radicand.firstDerivativeAbsoluteUpperBound
                    * radicand.secondDerivativeAbsoluteUpperBound
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * pow(
                    radicand.firstDerivativeAbsoluteUpperBound,
                    3.0
                ) / (8.0 * rootFifthLower).nextDown
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: span,
            angleSecond: 0.0,
            angleThird: 0.0,
            rootMagnitude: rootUpper,
            rootFirst: try upperProduct(
                rootFirstByAngle,
                span,
                tolerance: tolerance
            , using: &execution),
            rootSecond: try upperProduct(
                rootSecondByAngle,
                try upperProduct(span, span, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution),
            rootThird: (
                rootThirdByAngle * span * span * span
            ).nextUp,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }



    private func oneSidedDoubleRootOpenSpatialDifferentialMagnitudeBounds(
        rootAtLower: Bool,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let span = (upperAngle - lowerAngle).nextUp
        let requestedLower = lowerAngle + span * lowerFraction
        let requestedUpper = lowerAngle + span * upperFraction
        let rootAngle = rootAtLower ? lowerAngle : upperAngle
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let factor = try EndpointRegularizedFactorBounder()
            .oneSidedDoubleRootBounds(
                componentLower: lowerAngle,
                componentUpper: upperAngle,
                requestedLower: requestedLower.nextDown,
                requestedUpper: requestedUpper.nextUp,
                rootAtLower: rootAtLower,
                endpointValue: radicand.value(at: rootAngle),
                endpointDerivative: radicand.derivative(at: rootAngle),
                endpointSecondDerivative: radicand.secondDerivative(
                    at: rootAngle
                ),
                firstDerivativeMagnitudeUpperBound:
                    radicand.firstDerivativeAbsoluteUpperBound,
                secondDerivativeMagnitudeUpperBound:
                    radicand.secondDerivativeAbsoluteUpperBound,
                thirdDerivativeMagnitudeUpperBound:
                    radicand.thirdDerivativeAbsoluteUpperBound,
                fourthDerivativeMagnitudeUpperBound:
                    radicand.fourthDerivativeAbsoluteUpperBound,
                fifthDerivativeMagnitudeUpperBound:
                    radicand.fifthDerivativeAbsoluteUpperBound,
                arithmeticEnvelope: arithmeticEnvelope,
                valueRange: { rangeLower, rangeUpper, execution in
                    try Self.radicandRange(
                        configuration: configuration,
                        lower: rangeLower,
                        upper: rangeUpper,
                        arithmeticEnvelope: arithmeticEnvelope
                    , using: &execution)
                },
                tolerance: tolerance,
                label: "Sphere-cone double-root open branch"
            , using: &execution)
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A double-root sphere-cone regularized factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let distanceMagnitude = span
        let signedRootMagnitude = (
            distanceMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            span * rootUpper
                + distanceMagnitude * rootFirstByAngle * span
        ).nextUp
        let signedRootSecond = (
            2.0 * span * rootFirstByAngle * span
                + distanceMagnitude * rootSecondByAngle * span * span
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * span * span
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * span * span * span
        ).nextUp
        let signedRootThird = (
            3.0 * span * rootByFractionSecond
                + distanceMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: span,
            angleSecond: 0.0,
            angleThird: 0.0,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }



    private func oneSidedSimpleRootOpenSpatialDifferentialMagnitudeBounds(
        rootAtLower: Bool,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let lowerDifferential = try angleDifferential(
            at: lowerFraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let upperDifferential = try angleDifferential(
            at: upperFraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let requestedLower = min(
            lowerDifferential.value,
            upperDifferential.value
        )
        let requestedUpper = max(
            lowerDifferential.value,
            upperDifferential.value
        )
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let rootAngle = rootAtLower ? lowerAngle : upperAngle
        let factor = try EndpointRegularizedFactorBounder().oneSidedBounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower.nextDown,
            requestedUpper: requestedUpper.nextUp,
            rootAtLower: rootAtLower,
            endpointValue: radicand.value(at: rootAngle),
            endpointDerivative: radicand.derivative(at: rootAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            orientedValueRange: { rangeLower, rangeUpper, execution in
                let range = try Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                , using: &execution)
                return range
            },
            tolerance: tolerance,
            label: "Sphere-cone one-sided open branch"
        , using: &execution)
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A one-sided sphere-cone regularized square-root factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let phaseScale = (Double.pi * 0.5).nextUp
        let phaseLower = phaseScale * lowerFraction
        let phaseUpper = phaseScale * upperFraction
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
        let span = (upperAngle - lowerAngle).nextUp
        let angleFirst = rootAtLower
            ? (span * phaseScale * sineMagnitude).nextUp
            : (span * phaseScale * cosineMagnitude).nextUp
        let angleSecond = rootAtLower
            ? (span * phaseScale * phaseScale * cosineMagnitude).nextUp
            : (span * phaseScale * phaseScale * sineMagnitude).nextUp
        let angleThird = rootAtLower
            ? (span * pow(phaseScale, 3.0) * sineMagnitude).nextUp
            : (span * pow(phaseScale, 3.0) * cosineMagnitude).nextUp
        let distanceRootScale = sqrt(2.0 * span).nextUp
        let distanceRootMagnitude = sqrt(span).nextUp
        let halfPhaseScale = (phaseScale * 0.5).nextUp
        let distanceRootFirst = (
            distanceRootScale * halfPhaseScale
        ).nextUp
        let distanceRootSecond = (
            distanceRootScale * halfPhaseScale * halfPhaseScale
        ).nextUp
        let distanceRootThird = (
            distanceRootScale * pow(halfPhaseScale, 3.0)
        ).nextUp
        let signedRootMagnitude = (
            distanceRootMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            distanceRootFirst * rootUpper
                + distanceRootMagnitude
                    * rootFirstByAngle * angleFirst
        ).nextUp
        let signedRootSecond = (
            distanceRootSecond * rootUpper
                + 2.0 * distanceRootFirst
                    * rootFirstByAngle * angleFirst
                + distanceRootMagnitude * (
                    rootSecondByAngle * angleFirst * angleFirst
                        + rootFirstByAngle * angleSecond
                )
        ).nextUp
        let rootByFractionFirst = (
            rootFirstByAngle * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * angleFirst * angleFirst
                + rootFirstByAngle * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * angleFirst * angleFirst * angleFirst
                + 3.0 * rootSecondByAngle * angleFirst * angleSecond
                + rootFirstByAngle * angleThird
        ).nextUp
        let signedRootThird = (
            distanceRootThird * rootUpper
                + 3.0 * distanceRootSecond * rootByFractionFirst
                + 3.0 * distanceRootFirst * rootByFractionSecond
                + distanceRootMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }



    private func twoSimpleRootOpenSpatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let radicand = configuration.radicandPolynomial
        let arithmeticEnvelope = (
            Double.ulpOfOne * radicand.coefficientScale * 131_072.0
        ).nextUp
        let requestedLower = try angleDifferential(
            at: lowerFraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution).value
        let requestedUpper = try angleDifferential(
            at: upperFraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution).value
        let factor = try EndpointRegularizedFactorBounder().bounds(
            componentLower: lowerAngle,
            componentUpper: upperAngle,
            requestedLower: requestedLower.nextDown,
            requestedUpper: requestedUpper.nextUp,
            lowerValue: radicand.value(at: lowerAngle),
            upperValue: radicand.value(at: upperAngle),
            lowerDerivative: radicand.derivative(at: lowerAngle),
            upperDerivative: radicand.derivative(at: upperAngle),
            firstDerivativeMagnitudeUpperBound:
                radicand.firstDerivativeAbsoluteUpperBound,
            secondDerivativeMagnitudeUpperBound:
                radicand.secondDerivativeAbsoluteUpperBound,
            thirdDerivativeMagnitudeUpperBound:
                radicand.thirdDerivativeAbsoluteUpperBound,
            fourthDerivativeMagnitudeUpperBound:
                radicand.fourthDerivativeAbsoluteUpperBound,
            arithmeticEnvelope: arithmeticEnvelope,
            valueRange: { rangeLower, rangeUpper, execution in
                try Self.radicandRange(
                    configuration: configuration,
                    lower: rangeLower,
                    upper: rangeUpper,
                    arithmeticEnvelope: arithmeticEnvelope
                , using: &execution)
            },
            tolerance: tolerance,
            label: "Sphere-cone two-root open branch"
        , using: &execution)
        let rootLower = sqrt(factor.lower).nextDown
        let rootUpper = sqrt(factor.upper).nextUp
        guard rootLower > 0.0, rootUpper.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A two-root open sphere-cone regularized factor lost its positive margin."
            )
        }
        let rootFirstByAngle = try upperQuotient(
            factor.first,
            (2.0 * rootLower).nextDown,
            tolerance: tolerance
        , using: &execution)
        let rootCubedLower = (factor.lower * rootLower).nextDown
        let rootSecondByAngle = try upperSum(
            try upperQuotient(
                factor.second,
                (2.0 * rootLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            try upperQuotient(
                try upperProduct(
                    factor.first,
                    factor.first,
                    tolerance: tolerance
                , using: &execution),
                (4.0 * rootCubedLower).nextDown,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let rootFifthLower = (
            factor.lower * factor.lower * rootLower
        ).nextDown
        let rootThirdByAngle = (
            factor.third / (2.0 * rootLower).nextDown
                + 3.0 * factor.first * factor.second
                    / (4.0 * rootCubedLower).nextDown
                + 3.0 * factor.first * factor.first * factor.first
                    / (8.0 * rootFifthLower).nextDown
        ).nextUp
        let phaseScale = Double.pi.nextUp
        let phaseLower = phaseScale * lowerFraction
        let phaseUpper = phaseScale * upperFraction
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
        let halfSpan = ((upperAngle - lowerAngle) * 0.5).nextUp
        let angleFirst = (
            halfSpan * phaseScale * sineMagnitude
        ).nextUp
        let angleSecond = (
            halfSpan * phaseScale * phaseScale * cosineMagnitude
        ).nextUp
        let angleThird = (
            halfSpan * pow(phaseScale, 3.0) * sineMagnitude
        ).nextUp
        let signedRootMagnitude = (
            halfSpan * sineMagnitude * rootUpper
        ).nextUp
        let signedRootFirst = (
            halfSpan * (
                phaseScale * cosineMagnitude * rootUpper
                    + sineMagnitude * rootFirstByAngle * angleFirst
            )
        ).nextUp
        let signedRootSecond = (
            halfSpan * (
                phaseScale * phaseScale * sineMagnitude * rootUpper
                    + 2.0 * phaseScale * cosineMagnitude
                        * rootFirstByAngle * angleFirst
                    + sineMagnitude * (
                        rootSecondByAngle * angleFirst * angleFirst
                            + rootFirstByAngle * angleSecond
                    )
            )
        ).nextUp
        let rootByFractionFirst = (
            rootFirstByAngle * angleFirst
        ).nextUp
        let rootByFractionSecond = (
            rootSecondByAngle * angleFirst * angleFirst
                + rootFirstByAngle * angleSecond
        ).nextUp
        let rootByFractionThird = (
            rootThirdByAngle * angleFirst * angleFirst * angleFirst
                + 3.0 * rootSecondByAngle * angleFirst * angleSecond
                + rootFirstByAngle * angleThird
        ).nextUp
        let prefixMagnitude = (halfSpan * sineMagnitude).nextUp
        let prefixFirst = (
            halfSpan * phaseScale * cosineMagnitude
        ).nextUp
        let prefixSecond = (
            halfSpan * phaseScale * phaseScale * sineMagnitude
        ).nextUp
        let prefixThird = (
            halfSpan * pow(phaseScale, 3.0) * cosineMagnitude
        ).nextUp
        let signedRootThird = (
            prefixThird * rootUpper
                + 3.0 * prefixSecond * rootByFractionFirst
                + 3.0 * prefixFirst * rootByFractionSecond
                + prefixMagnitude * rootByFractionThird
        ).nextUp
        return try spatialBoundsFromSignedRoot(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            rootMagnitude: signedRootMagnitude,
            rootFirst: signedRootFirst,
            rootSecond: signedRootSecond,
            rootThird: signedRootThird,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    func normalizedFractionCandidates(
        forConeAngle angle: Double,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try normalizedFractionCandidates(forConeAngle: angle, tolerance: tolerance, using: &execution)
    }

    func normalizedFractionCandidates(
        forConeAngle angle: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch:
            let normalized = try Self.normalizedAngle(angle, using: &execution)
            let fraction = normalized / period
            return normalized == 0.0 ? try CertifiedAnalyticCurveEvaluation.values(0.0, 1.0, using: &execution) : try CertifiedAnalyticCurveEvaluation.values(fraction, using: &execution)
        case .boundedAngularInterval:
            let adjusted = try Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            , using: &execution)
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            let normalized = min(
                max((adjusted - lowerAngle) / (upperAngle - lowerAngle), 0.0),
                1.0
            )
            let phase = acos(1.0 - 2.0 * normalized)
            let fraction = phase / period
            return try CertifiedAnalyticCurveEvaluation.values(fraction, 1.0 - fraction, using: &execution)
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let adjusted = try Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            , using: &execution)
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            let normalized = min(
                max((adjusted - lowerAngle) / (upperAngle - lowerAngle), 0.0),
                1.0
            )
            let configuration = try Self.makeConfiguration(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            , using: &execution)
            switch try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) {
            case .twoSimpleRoots:
                return try CertifiedAnalyticCurveEvaluation.values(acos(1.0 - 2.0 * normalized) / Double.pi, using: &execution)
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                return try CertifiedAnalyticCurveEvaluation.values(acos(1.0 - normalized) / (Double.pi * 0.5), using: &execution)
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                return try CertifiedAnalyticCurveEvaluation.values(asin(normalized) / (Double.pi * 0.5), using: &execution)
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                return try CertifiedAnalyticCurveEvaluation.values(normalized, using: &execution)
            }
        case .apexReducedAngularInterval:
            let adjusted = try Self.adjustedAngle(
                angle,
                inside: lowerAngle...upperAngle
            , using: &execution)
            guard adjusted <= upperAngle + tolerance.angle else { return [] }
            return try CertifiedAnalyticCurveEvaluation.values((adjusted - lowerAngle) / (upperAngle - lowerAngle), using: &execution)
        }
    }



    private func sphereParameter(
        for point: Point3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        , using: &execution)
        let offset = point - configuration.sphere.center
        let axial = offset.dot(.unitZ)
        let horizontal = offset - Vector3D.unitZ * axial
        let poleThreshold = max(
            Double.ulpOfOne * configuration.sphere.radius * 4_096.0,
            tolerance.distance * 1.0e-6
        )
        guard horizontal.length <= poleThreshold else {
            let projection = try sphereSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            , using: &execution)
            return SurfaceParameter(u: projection.u, v: projection.v)
        }
        let endpointTolerance = try Self.endpointFractionTolerance(
            tolerance: tolerance
        , using: &execution)
        let direction: Vector3D
        if fraction <= endpointTolerance {
            direction = try differential(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            , using: &execution).firstDerivative
        } else if fraction >= 1.0 - endpointTolerance {
            direction = -(try differential(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            , using: &execution).firstDerivative)
        } else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: horizontal.length,
                tolerance: tolerance,
                message: "A pole-split sphere-cone pcurve reached a spherical pole away from a certified endpoint."
            )
        }
        let horizontalDirection = direction
            - Vector3D.unitZ * direction.dot(.unitZ)
        let normalized = try horizontalDirection.normalized(
            tolerance: tolerance.distance
        )
        let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
        return SurfaceParameter(
            u: try Self.normalizedAngle(atan2(
                normalized.dot(basis.v),
                normalized.dot(basis.u)
            ), using: &execution),
            v: axial >= 0.0 ? Double.pi * 0.5 : -Double.pi * 0.5
        )
    }



    private func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a negative or non-finite factor."
            )
        }
        let result = (first * second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }



    private func upperQuotient(
        _ numerator: Double,
        _ denominator: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard numerator.isFinite,
              denominator.isFinite,
              numerator >= 0.0,
              denominator > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a non-positive divisor."
            )
        }
        let result = (numerator / denominator).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }



    private func upperSum(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard first.isFinite,
              second.isFinite,
              first >= 0.0,
              second >= 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification received a negative or non-finite summand."
            )
        }
        let result = (first + second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Sphere-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }



    private func slantDenominatorLowerBound(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let raw = abs(
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        let envelope = max(
            Double.ulpOfOne * raw * 4_096.0,
            tolerance.relative * raw * 1.0e-6
        )
        let result = (raw - envelope).nextDown
        guard result > 0.0 else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "A sphere-cone slant denominator lost its positive margin."
            )
        }
        return result
    }



    private func spatialBounds(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        slantMagnitude: Double,
        slantFirst: Double,
        slantSecond: Double,
        slantThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let sine = sin(configuration.cone.halfAngle).nextUp
        let first = try upperSum(
            try upperProduct(
                try upperProduct(
                    sine,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                slantMagnitude,
                tolerance: tolerance
            , using: &execution),
            slantFirst,
            tolerance: tolerance
        , using: &execution)
        let generatorSecond = try upperProduct(
            sine,
            try upperSum(
                try upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let second = try upperSum(
            try upperProduct(
                generatorSecond,
                slantMagnitude,
                tolerance: tolerance
            , using: &execution),
            try upperSum(
                try upperProduct(
                    try upperProduct(
                        2.0 * sine,
                        angleFirst,
                        tolerance: tolerance
                    , using: &execution),
                    slantFirst,
                    tolerance: tolerance
                , using: &execution),
                slantSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let generatorThird = (
            sine * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let third = (
            generatorThird * slantMagnitude
                + 3.0 * generatorSecond * slantFirst
                + 3.0 * sine * angleFirst * slantSecond
                + slantThird
        ).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: first,
            second: second,
            third: third
        )
    }



    private func spatialBoundsFromSignedRoot(
        angleFirst: Double,
        angleSecond: Double,
        angleThird: Double,
        rootMagnitude: Double,
        rootFirst: Double,
        rootSecond: Double,
        rootThird: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.consumeWork(1)
        let harmonicMagnitude = try upperProduct(
            abs(configuration.slope),
            configuration.radialAmplitude.nextUp,
            tolerance: tolerance
        , using: &execution)
        let halfLinearMagnitude = try upperSum(
            abs(configuration.axialCenter),
            harmonicMagnitude,
            tolerance: tolerance
        , using: &execution)
        let halfLinearFirst = try upperProduct(
            harmonicMagnitude,
            angleFirst,
            tolerance: tolerance
        , using: &execution)
        let halfLinearSecond = try upperProduct(
            harmonicMagnitude,
            try upperSum(
                try upperProduct(
                    angleFirst,
                    angleFirst,
                    tolerance: tolerance
                , using: &execution),
                angleSecond,
                tolerance: tolerance
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
        let halfLinearThird = (
            harmonicMagnitude * (
                angleFirst * angleFirst * angleFirst
                    + 3.0 * angleFirst * angleSecond
                    + angleThird
            )
        ).nextUp
        let denominatorLower = try slantDenominatorLowerBound(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        return try spatialBounds(
            angleFirst: angleFirst,
            angleSecond: angleSecond,
            angleThird: angleThird,
            slantMagnitude: try upperQuotient(
                try upperSum(
                    halfLinearMagnitude,
                    rootMagnitude,
                    tolerance: tolerance
                , using: &execution),
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            slantFirst: try upperQuotient(
                try upperSum(
                    halfLinearFirst,
                    rootFirst,
                    tolerance: tolerance
                , using: &execution),
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            slantSecond: try upperQuotient(
                try upperSum(
                    halfLinearSecond,
                    rootSecond,
                    tolerance: tolerance
                , using: &execution),
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            slantThird: try upperQuotient(
                try upperSum(
                    halfLinearThird,
                    rootThird,
                    tolerance: tolerance
                , using: &execution),
                denominatorLower,
                tolerance: tolerance
            , using: &execution),
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
    }

    private func resourceFailure(
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



    private func openEndpointStructure(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> OpenEndpointStructure {
        try execution.consumeWork(1)
        let classificationTolerance = try Self.classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let lowerIsRoot = abs(configuration.radicand(at: lowerAngle))
            <= classificationTolerance * 16.0
        let upperIsRoot = abs(configuration.radicand(at: upperAngle))
            <= classificationTolerance * 16.0
        let lowerIsSimple = lowerIsRoot
            && abs(configuration.radicandFirstDerivative(at: lowerAngle))
                > classificationTolerance
        let upperIsSimple = upperIsRoot
            && abs(configuration.radicandFirstDerivative(at: upperAngle))
                > classificationTolerance
        if lowerIsRoot == false, upperIsRoot == false {
            return .rootFree
        }
        if lowerIsRoot, upperIsRoot == false {
            return lowerIsSimple ? .lowerSimpleRoot : .lowerDoubleRoot
        }
        if lowerIsRoot == false, upperIsRoot {
            return upperIsSimple ? .upperSimpleRoot : .upperDoubleRoot
        }
        if lowerIsSimple, upperIsSimple {
            return .twoSimpleRoots
        }
        if lowerIsSimple {
            return .lowerSimpleUpperDouble
        }
        if upperIsSimple {
            return .lowerDoubleUpperSimple
        }
        return .twoDoubleRoots
    }



    private func angleDifferential(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
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
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let normalized: ScalarDifferential
            switch try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) {
            case .twoSimpleRoots:
                let phase = Double.pi * fraction
                normalized = ScalarDifferential(
                    value: 0.5 - 0.5 * cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.5 * cos(phase),
                    third: -pow(Double.pi, 3.0) * 0.5 * sin(phase)
                )
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: 1.0 - cos(phase),
                    first: Double.pi * 0.5 * sin(phase),
                    second: Double.pi * Double.pi * 0.25 * cos(phase),
                    third: -pow(Double.pi * 0.5, 3.0) * sin(phase)
                )
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                let phase = Double.pi * 0.5 * fraction
                normalized = ScalarDifferential(
                    value: sin(phase),
                    first: Double.pi * 0.5 * cos(phase),
                    second: -Double.pi * Double.pi * 0.25 * sin(phase),
                    third: -pow(Double.pi * 0.5, 3.0) * cos(phase)
                )
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                normalized = ScalarDifferential(
                    value: fraction,
                    first: 1.0,
                    second: 0.0,
                    third: 0.0
                )
            }
            let span = upperAngle - lowerAngle
            return ScalarDifferential(
                value: lowerAngle + span * normalized.value,
                first: span * normalized.first,
                second: span * normalized.second,
                third: span * normalized.third
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



    private func angleFourthDerivative(
        at fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        switch componentKind {
        case .negativeFullBranch, .positiveFullBranch,
             .apexReducedAngularInterval:
            return 0.0
        case .boundedAngularInterval:
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            return -halfSpan * pow(period, 4.0) * cos(period * fraction)
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            let normalizedFourth: Double
            switch try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution) {
            case .twoSimpleRoots:
                normalizedFourth = -0.5 * pow(Double.pi, 4.0)
                    * cos(Double.pi * fraction)
            case .lowerSimpleRoot, .lowerSimpleUpperDouble:
                let scale = Double.pi * 0.5
                normalizedFourth = -pow(scale, 4.0)
                    * cos(scale * fraction)
            case .upperSimpleRoot, .lowerDoubleUpperSimple:
                let scale = Double.pi * 0.5
                normalizedFourth = pow(scale, 4.0)
                    * sin(scale * fraction)
            case .rootFree, .lowerDoubleRoot, .upperDoubleRoot,
                 .twoDoubleRoots:
                normalizedFourth = 0.0
            }
            return (upperAngle - lowerAngle) * normalizedFourth
        }
    }



    private func radicandFourthDerivative(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let polynomial = configuration.radicandPolynomial
        let firstAngular = polynomial.derivative(at: angle.value)
        let secondAngular = polynomial.secondDerivative(at: angle.value)
        let thirdAngular = try polynomial.thirdDerivative(at: angle.value)
        let fourthAngular = polynomial.derivative(order: 4, at: angle.value)
        let angleFourth = try angleFourthDerivative(
            at: fraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        return fourthAngular * pow(angle.first, 4.0)
            + 6.0 * thirdAngular * angle.first * angle.first * angle.second
            + 3.0 * secondAngular * angle.second * angle.second
            + 4.0 * secondAngular * angle.first * angle.third
            + firstAngular * angleFourth
    }



    private func slantDifferential(
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let halfLinearAngularFirst = configuration.halfLinearFirstDerivative(
            at: angle.value
        )
        let halfLinearAngularSecond = configuration.halfLinearSecondDerivative(
            at: angle.value
        )
        let halfLinear = ScalarDifferential(
            value: configuration.halfLinear(at: angle.value),
            first: halfLinearAngularFirst * angle.first,
            second: halfLinearAngularSecond * angle.first * angle.first
                + halfLinearAngularFirst * angle.second,
            third: -halfLinearAngularFirst
                    * angle.first * angle.first * angle.first
                + 3.0 * halfLinearAngularSecond * angle.first * angle.second
                + halfLinearAngularFirst * angle.third
        )
        let inverseQuadraticCosine = 1.0 / (
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        if componentKind == .apexReducedAngularInterval {
            let scale = 2.0 * inverseQuadraticCosine
            return ScalarDifferential(
                value: halfLinear.value * scale,
                first: halfLinear.first * scale,
                second: halfLinear.second * scale,
                third: halfLinear.third * scale
            )
        }
        let radicand = ScalarDifferential(
            value: halfLinear.value * halfLinear.value
                - configuration.quadraticA * configuration.quadraticC,
            first: 2.0 * halfLinear.value * halfLinear.first,
            second: 2.0 * (
                halfLinear.first * halfLinear.first
                    + halfLinear.value * halfLinear.second
            ),
            third: 2.0 * (
                3.0 * halfLinear.first * halfLinear.second
                    + halfLinear.value * halfLinear.third
            )
        )
        let root = try signedSquareRootDifferential(
            radicand,
            angle: angle,
            fraction: fraction,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        return ScalarDifferential(
            value: (halfLinear.value + root.value) * inverseQuadraticCosine,
            first: (halfLinear.first + root.first) * inverseQuadraticCosine,
            second: (halfLinear.second + root.second) * inverseQuadraticCosine,
            third: (halfLinear.third + root.third) * inverseQuadraticCosine
        )
    }



    private func signedSquareRootDifferential(
        _ radicand: ScalarDifferential,
        angle: ScalarDifferential,
        fraction: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let algebraicTolerance = try Self.classificationTolerance(
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
        case .negativeOpenAngularInterval:
            branchSign = -1.0
        case .positiveOpenAngularInterval:
            branchSign = 1.0
        case .apexReducedAngularInterval:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An apex-reduced sphere-cone component does not use a square-root branch."
            )
        }
        if componentKind == .boundedAngularInterval {
            let factor = try regularizedRadicandFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            guard factor.value > 0.0, factor.value.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: factor.value,
                    tolerance: tolerance,
                    message: "A bounded sphere-cone component lost its positive regularized radicand factor."
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
            let phase = 2.0 * Double.pi * fraction
            let sine = ScalarDifferential(
                value: sin(phase),
                first: 2.0 * Double.pi * cos(phase),
                second: -4.0 * Double.pi * Double.pi * sin(phase),
                third: -8.0 * pow(Double.pi, 3.0) * cos(phase)
            )
            let result = try Self.product(
                sine,
                rootByFraction
            , using: &execution).scaled(by: (upperAngle - lowerAngle) * 0.5)
            guard result.value.isFinite,
                  result.first.isFinite,
                  result.second.isFinite,
                  result.third.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "A bounded sphere-cone regularized square-root differential exceeded finite arithmetic."
                )
            }
            return result
        }
        if componentKind == .negativeOpenAngularInterval
            || componentKind == .positiveOpenAngularInterval {
            let structure = try openEndpointStructure(
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            switch structure {
            case .lowerSimpleRoot, .upperSimpleRoot, .twoSimpleRoots,
                 .lowerDoubleRoot, .upperDoubleRoot:
                return try openRegularizedSquareRootDifferential(
                    structure: structure,
                    angle: angle,
                    fraction: fraction,
                    branchSign: branchSign,
                    configuration: configuration,
                    tolerance: tolerance
                , using: &execution)
            case .rootFree, .twoDoubleRoots, .lowerSimpleUpperDouble,
                 .lowerDoubleUpperSimple:
                break
            }
        }
        let endpointTolerance = try Self.endpointFractionTolerance(
            tolerance: tolerance
        , using: &execution)
        let isLowerEndpoint = fraction <= endpointTolerance
        let isUpperEndpoint = fraction >= 1.0 - endpointTolerance
        let isCertifiedRootEndpoint: Bool
        switch componentKind {
        case .boundedAngularInterval:
            isCertifiedRootEndpoint = abs(sin(2.0 * Double.pi * fraction))
                <= max(tolerance.angle, Double.ulpOfOne * 256.0)
        case .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            isCertifiedRootEndpoint = isLowerEndpoint || isUpperEndpoint
        case .negativeFullBranch, .positiveFullBranch:
            isCertifiedRootEndpoint = false
        case .apexReducedAngularInterval:
            isCertifiedRootEndpoint = false
        }
        if isCertifiedRootEndpoint,
           abs(radicand.value) <= algebraicTolerance * 32.0 {
            let squaredSlope = radicand.second * 0.5
            guard squaredSlope > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: squaredSlope,
                    tolerance: tolerance,
                    message: "A sphere-cone radicand endpoint has no regular square-root continuation."
                )
            }
            let endpointDirection: Double
            switch componentKind {
            case .boundedAngularInterval:
                endpointDirection = cos(2.0 * Double.pi * fraction) < 0.0
                    ? -1.0
                    : 1.0
            case .negativeOpenAngularInterval,
                 .positiveOpenAngularInterval:
                endpointDirection = isUpperEndpoint ? -1.0 : 1.0
            case .negativeFullBranch, .positiveFullBranch:
                endpointDirection = 1.0
            case .apexReducedAngularInterval:
                endpointDirection = 1.0
            }
            let signedEndpointDirection = componentKind == .boundedAngularInterval
                ? endpointDirection
                : branchSign * endpointDirection
            let signedFirst = signedEndpointDirection * sqrt(squaredSlope)
            let second = radicand.third / (6.0 * signedFirst)
            let fourth = try radicandFourthDerivative(
                angle: angle,
                fraction: fraction,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let third = (fourth - 6.0 * second * second)
                / (8.0 * signedFirst)
            return ScalarDifferential(
                value: 0.0,
                first: signedFirst,
                second: second,
                third: third
            )
        }
        guard radicand.value >= -algebraicTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: -radicand.value,
                tolerance: tolerance,
                message: "A sphere-cone evaluator left its certified non-negative radicand interval."
            )
        }
        let magnitude = sqrt(max(radicand.value, 0.0))
        guard magnitude > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: magnitude,
                tolerance: tolerance,
                message: "A sphere-cone square-root differential is singular at normalized fraction \(fraction) for \(componentKind.rawValue)."
            )
        }
        let signedValue = branchSign * magnitude
        return ScalarDifferential(
            value: signedValue,
            first: radicand.first / (2.0 * signedValue),
            second: radicand.second / (2.0 * signedValue)
                - radicand.first * radicand.first
                    / (4.0 * signedValue * signedValue * signedValue),
            third: radicand.third / (2.0 * signedValue)
                - 3.0 * radicand.first * radicand.second
                    / (4.0 * signedValue * signedValue * signedValue)
                + 3.0 * radicand.first * radicand.first * radicand.first
                    / (8.0 * pow(signedValue, 5.0))
        )
    }



    private func openRegularizedSquareRootDifferential(
        structure: OpenEndpointStructure,
        angle: ScalarDifferential,
        fraction: Double,
        branchSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let factor: ScalarDifferential
        let distanceRoot: ScalarDifferential
        switch structure {
        case .lowerSimpleRoot, .upperSimpleRoot:
            let rootAtLower = structure == .lowerSimpleRoot
            let dividedDifference = try Self.trigonometricDividedDifference(
                configuration.radicandPolynomial,
                value: angle.value,
                endpoint: rootAtLower ? lowerAngle : upperAngle
            , using: &execution)
            factor = rootAtLower
                ? dividedDifference
                : dividedDifference.scaled(by: -1.0)
            let phaseScale = Double.pi * 0.5
            let phase = phaseScale * fraction
            let halfPhaseScale = phaseScale * 0.5
            let argument = rootAtLower
                ? phase * 0.5
                : Double.pi * 0.25 - phase * 0.5
            let derivativeSign = rootAtLower ? 1.0 : -1.0
            let scale = sqrt(2.0 * (upperAngle - lowerAngle))
            distanceRoot = ScalarDifferential(
                value: scale * sin(argument),
                first: derivativeSign * scale * halfPhaseScale
                    * cos(argument),
                second: -scale * halfPhaseScale * halfPhaseScale
                    * sin(argument),
                third: -scale * pow(
                    derivativeSign * halfPhaseScale,
                    3.0
                ) * cos(argument)
            )
        case .twoSimpleRoots:
            factor = try regularizedRadicandFactorDifferential(
                at: angle.value,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let phase = Double.pi * fraction
            let halfSpan = (upperAngle - lowerAngle) * 0.5
            distanceRoot = ScalarDifferential(
                value: halfSpan * sin(phase),
                first: halfSpan * Double.pi * cos(phase),
                second: -halfSpan * Double.pi * Double.pi * sin(phase),
                third: -halfSpan * pow(Double.pi, 3.0) * cos(phase)
            )
        case .lowerDoubleRoot, .upperDoubleRoot:
            let rootAtLower = structure == .lowerDoubleRoot
            factor = try Self.trigonometricSecondDividedDifference(
                configuration.radicandPolynomial,
                value: angle.value,
                endpoint: rootAtLower ? lowerAngle : upperAngle
            , using: &execution)
            let span = upperAngle - lowerAngle
            distanceRoot = ScalarDifferential(
                value: rootAtLower
                    ? span * fraction
                    : span * (1.0 - fraction),
                first: rootAtLower ? span : -span,
                second: 0.0,
                third: 0.0
            )
        case .rootFree, .twoDoubleRoots, .lowerSimpleUpperDouble,
             .lowerDoubleUpperSimple:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested sphere-cone endpoint structure does not use simple-root regularization."
            )
        }
        guard factor.value > 0.0, factor.value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: factor.value,
                tolerance: tolerance,
                message: "An open sphere-cone component lost its positive regularized radicand factor."
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
        let result = try Self.product(
            distanceRoot,
            rootByFraction
        , using: &execution).scaled(by: branchSign)
        guard result.value.isFinite,
              result.first.isFinite,
              result.second.isFinite,
              result.third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "An open sphere-cone regularized square-root differential exceeded finite arithmetic."
            )
        }
        return result
    }



    private func regularizedRadicandFactorDifferential(
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
                message: "A bounded sphere-cone regularized factor was evaluated outside its certified angular component."
            )
        }
        let radicand = configuration.radicandPolynomial
        let lowerValue = radicand.value(at: lowerAngle)
        let upperValue = radicand.value(at: upperAngle)
        let correctionSlope = (upperValue - lowerValue) / span
        let usesLowerEndpoint = lowerDistance <= upperDistance
        let endpoint = usesLowerEndpoint ? lowerAngle : upperAngle
        let dividedDifference = try Self.trigonometricDividedDifference(
            radicand,
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
        return try Self.quotient(
            numerator,
            denominator,
            tolerance: tolerance,
            message: "A bounded sphere-cone regularized factor lost its opposite-endpoint denominator."
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



    private static func trigonometricSecondDividedDifference(
        _ polynomial: TrigonometricPolynomial,
        value: Double,
        endpoint: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarDifferential {
        try execution.consumeWork(1)
        let difference = value - endpoint
        if abs(difference) <= 0.25 {
            var result = 0.0
            var first = 0.0
            var second = 0.0
            var third = 0.0
            var factorial = 1.0
            for order in 1...24 {
                try execution.consumeWork(1)
                factorial *= Double(order)
                guard order >= 2 else { continue }
                let coefficient = polynomial.derivative(
                    order: order,
                    at: endpoint
                ) / factorial
                let exponent = order - 2
                result += coefficient * pow(
                    difference,
                    Double(exponent)
                )
                if exponent > 0 {
                    first += coefficient * Double(exponent)
                        * pow(difference, Double(exponent - 1))
                }
                if exponent > 1 {
                    second += coefficient
                        * Double(exponent * (exponent - 1))
                        * pow(difference, Double(exponent - 2))
                }
                if exponent > 2 {
                    third += coefficient
                        * Double(exponent * (exponent - 1) * (exponent - 2))
                        * pow(difference, Double(exponent - 3))
                }
            }
            return ScalarDifferential(
                value: result,
                first: first,
                second: second,
                third: third
            )
        }
        let endpointValue = polynomial.value(at: endpoint)
        let endpointFirst = polynomial.derivative(at: endpoint)
        let numerator = polynomial.value(at: value)
            - endpointValue - endpointFirst * difference
        let numeratorFirst = polynomial.derivative(at: value)
            - endpointFirst
        let numeratorSecond = polynomial.secondDerivative(at: value)
        let numeratorThird = try polynomial.thirdDerivative(at: value)
        let squared = difference * difference
        let cubed = squared * difference
        let fourth = squared * squared
        let fifth = fourth * difference
        return ScalarDifferential(
            value: numerator / squared,
            first: numeratorFirst / squared - 2.0 * numerator / cubed,
            second: numeratorSecond / squared
                - 4.0 * numeratorFirst / cubed
                + 6.0 * numerator / fourth,
            third: numeratorThird / squared
                - 6.0 * numeratorSecond / cubed
                + 18.0 * numeratorFirst / fourth
                - 24.0 * numerator / fifth
        )
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



    private static func endpointFractionTolerance(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        // Root-regularizing angular maps move by O(fraction squared), so values
        // within sqrt(ulp) of an endpoint can round to the endpoint exactly.
        return max(tolerance.relative, 2.0 * sqrt(Double.ulpOfOne))
    }



    private static func makeConfiguration(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Configuration {
        try execution.consumeWork(1)
        try sphereSurface.validate(tolerance: tolerance, using: &execution)
        try coneSurface.validate(tolerance: tolerance, using: &execution)
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(sphereSurface),
              case let .cone(coneCanonical) = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified sphere-cone curve requires exact sphere and cone surfaces."
            )
        }
        let cone = try canonicalCone(coneCanonical, tolerance: tolerance, using: &execution)
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter
        let zeroPoint = try cone.surface.point(
            u: 0.0,
            v: 1.0,
            tolerance: tolerance
        , using: &execution)
        let quarterPoint = try cone.surface.point(
            u: Double.pi * 0.5,
            v: 1.0,
            tolerance: tolerance
        , using: &execution)
        let axialStep = cone.axis * cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let zeroRadial = (zeroPoint - cone.apex - axialStep) / sine
        let quarterRadial = (quarterPoint - cone.apex - axialStep) / sine
        let slope = tan(cone.halfAngle)
        return Configuration(
            sphere: sphere,
            cone: cone,
            axialCenter: axialCenter,
            radialCosine: radialCenter.dot(zeroRadial),
            radialSine: radialCenter.dot(quarterRadial),
            quadraticA: 1.0 + slope * slope,
            quadraticC: centerOffset.dot(centerOffset)
                - sphere.radius * sphere.radius
        )
    }

    private static func makeConfiguration<A: ExactScalarAdmission & ~Copyable>(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ,
        using execution: inout A) throws -> Configuration {
        try execution.consumeWork(1)
        guard case let .analytic(spherePrimitive) = sphereSurface,
              case let .analytic(conePrimitive) = coneSurface else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        try spherePrimitive.validate(tolerance: tolerance, using: &execution)
        try conePrimitive.validate(tolerance: tolerance, using: &execution)
        guard case let .sphere(sphere) = CanonicalAnalyticSurface(sphereSurface),
              case let .cone(coneCanonical) = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified sphere-cone curve requires exact sphere and cone surfaces."
            )
        }
        let cone = try canonicalCone(coneCanonical, tolerance: tolerance, using: &execution)
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter
        guard case let .analytic(canonicalConePrimitive) = cone.surface else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        let zeroPoint = try canonicalConePrimitive.point(
            u: 0.0,
            v: 1.0,
            tolerance: tolerance
        , using: &execution)
        let quarterPoint = try canonicalConePrimitive.point(
            u: Double.pi * 0.5,
            v: 1.0,
            tolerance: tolerance
        , using: &execution)
        let axialStep = cone.axis * cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let zeroRadial = (zeroPoint - cone.apex - axialStep) / sine
        let quarterRadial = (quarterPoint - cone.apex - axialStep) / sine
        let slope = tan(cone.halfAngle)
        return Configuration(
            sphere: sphere,
            cone: cone,
            axialCenter: axialCenter,
            radialCosine: radialCenter.dot(zeroRadial),
            radialSine: radialCenter.dot(quarterRadial),
            quadraticA: 1.0 + slope * slope,
            quadraticC: centerOffset.dot(centerOffset)
                - sphere.radius * sphere.radius
        )
    }



    private static func canonicalCone<A: ExactScalarAdmission & ~Copyable>(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ,
        using execution: inout A) throws -> Cone {
        try execution.consumeWork(1)
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        return Cone(apex: cone.apex, axis: axis, halfAngle: cone.halfAngle)
    }



    private static func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let product = configuration.quadraticA * configuration.quadraticC
        let numericalThreshold = try classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        guard product >= -numericalThreshold else { return [] }
        let root = sqrt(max(0.0, product))
        let linearThreshold = sqrt(numericalThreshold)
        let targets = root <= linearThreshold
            ? try CertifiedAnalyticCurveEvaluation.values(0.0, using: &execution)
            : try CertifiedAnalyticCurveEvaluation.values(root, -root, using: &execution)
        let harmonicAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        guard harmonicAmplitude > tolerance.distance else { return [] }
        let phase = atan2(configuration.radialSine, configuration.radialCosine)
        var values: [Double] = []
        var valuesCapacity = values.count
        for target in targets {
            try execution.consumeWork(1)
            let ratio = (target - configuration.axialCenter) / harmonicAmplitude
            let ratioTolerance = linearThreshold / harmonicAmplitude
            guard ratio >= -1.0 - ratioTolerance,
                  ratio <= 1.0 + ratioTolerance else {
                continue
            }
            let offset = acos(min(max(ratio, -1.0), 1.0))
            try CertifiedAnalyticCurveEvaluation.append(try normalizedAngle(phase - offset, using: &execution), to: &values, using: &execution, capacity: &valuesCapacity)
            try CertifiedAnalyticCurveEvaluation.append(try normalizedAngle(phase + offset, using: &execution), to: &values, using: &execution, capacity: &valuesCapacity)
        }
        values = try CertifiedAnalyticCurveEvaluation.sorted(CertifiedAnalyticCurveEvaluation.map(values, using: &execution) {element, execution in try refinedBoundaryAngle(
            element,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution) }, using: &execution)
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



    private static func validIntervals(
        boundaries: [Double],
        configuration: Configuration,
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
            if configuration.radicand(at: lower + (upper - lower) * 0.5) > classificationTolerance {
                try CertifiedAnalyticCurveEvaluation.append((lower, upper), to: &result,
                    using: &execution, capacity: &capacity)
            }
        }
        return result
    }



    private static func minimumRadicand(configuration: Configuration,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let lower = configuration.axialCenter
            - abs(configuration.slope) * configuration.radialAmplitude
        let upper = configuration.axialCenter
            + abs(configuration.slope) * configuration.radialAmplitude
        let minimumAbsoluteLinear: Double
        if lower <= 0.0, upper >= 0.0 {
            minimumAbsoluteLinear = 0.0
        } else {
            minimumAbsoluteLinear = min(abs(lower), abs(upper))
        }
        return minimumAbsoluteLinear * minimumAbsoluteLinear
            - configuration.quadraticA * configuration.quadraticC
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



    private static func radicandRange(
        configuration: Configuration,
        lower: Double,
        upper: Double,
        arithmeticEnvelope: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> (lower: Double, upper: Double) {
        try execution.consumeWork(1)
        let rawAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        let amplitudeLower = max(0.0, rawAmplitude.nextDown)
        let amplitudeUpper = rawAmplitude.nextUp
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var cosineValues = [
            cos(lower - phase),
            cos(upper - phase),
        ]
        var cosineValuesCapacity = cosineValues.count
        let firstExtremum = Int(
            floor((lower - phase) / Double.pi)
        ) - 1
        let lastExtremum = Int(
            ceil((upper - phase) / Double.pi)
        ) + 1
        for index in firstExtremum...lastExtremum {
            try execution.consumeWork(1)
            let angle = phase + Double(index) * Double.pi
            if angle > lower, angle < upper {
                try CertifiedAnalyticCurveEvaluation.append(index.isMultiple(of: 2) ? 1.0 : -1.0, to: &cosineValues, using: &execution, capacity: &cosineValuesCapacity)
            }
        }
        let cosineLower = cosineValues.min() ?? -1.0
        let cosineUpper = cosineValues.max() ?? 1.0
        let harmonicLower = (
            (cosineLower >= 0.0 ? amplitudeLower : amplitudeUpper)
                * cosineLower
        ).nextDown
        let harmonicUpper = (
            (cosineUpper >= 0.0 ? amplitudeUpper : amplitudeLower)
                * cosineUpper
        ).nextUp
        let linearLower = (
            configuration.axialCenter + harmonicLower
        ).nextDown
        let linearUpper = (
            configuration.axialCenter + harmonicUpper
        ).nextUp
        let squareLower: Double
        if linearLower <= 0.0, linearUpper >= 0.0 {
            squareLower = 0.0
        } else {
            squareLower = min(
                linearLower * linearLower,
                linearUpper * linearUpper
            ).nextDown
        }
        let squareUpper = max(
            linearLower * linearLower,
            linearUpper * linearUpper
        ).nextUp
        let product = (
            configuration.quadraticA * configuration.quadraticC
        )
        return (
            (squareLower - product - arithmeticEnvelope).nextDown,
            (squareUpper - product + arithmeticEnvelope).nextUp
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



    private static func residualUpperBound<A: ExactScalarAdmission & ~Copyable>(
        componentKind: ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout A) throws -> Double {
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
                    message: "A sphere-cone apex reduction exceeded the requested geometric tolerance."
                )
            }
            return result
        }
        let hasBoundaryRoots: Bool
        switch componentKind {
        case .boundedAngularInterval,
             .negativeOpenAngularInterval,
             .positiveOpenAngularInterval:
            hasBoundaryRoots = true
        case .negativeFullBranch, .positiveFullBranch:
            hasBoundaryRoots = false
        case .apexReducedAngularInterval:
            hasBoundaryRoots = false
        }
        guard hasBoundaryRoots else {
            return machineBound
        }
        let classificationTolerance = try classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
        let lowerResidual = abs(configuration.radicand(at: lowerAngle))
        let upperResidual = abs(configuration.radicand(at: upperAngle))
        let rootResidual = max(
            lowerResidual <= classificationTolerance * 16.0 ? lowerResidual : 0.0,
            upperResidual <= classificationTolerance * 16.0 ? upperResidual : 0.0
        )
        let denominator = abs(
            configuration.quadraticA * cos(configuration.cone.halfAngle)
        )
        let result = sqrt(rootResidual) / denominator + machineBound
        guard result <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: result,
                tolerance: tolerance,
                message: "Sphere-cone boundary roots do not certify the requested geometric tolerance."
            )
        }
        return result
    }



    private static func classificationTolerance<A: ExactScalarAdmission & ~Copyable>(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout A) throws -> Double {
        try execution.consumeWork(1)
        let scale = configuration.characteristicLength
        return max(
            Double.ulpOfOne * scale * scale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }



    private static func apexReductionResidualUpperBound<A: ExactScalarAdmission & ~Copyable>(
        configuration: Configuration
    ,
        using execution: inout A) throws -> Double {
        try execution.consumeWork(1)
        return abs(configuration.quadraticC) / configuration.sphere.radius
    }



    private static func apexBoundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let harmonicAmplitude = abs(configuration.slope)
            * configuration.radialAmplitude
        guard harmonicAmplitude > tolerance.distance else {
            return []
        }
        let ratio = -configuration.axialCenter / harmonicAmplitude
        let ratioTolerance = try classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        , using: &execution).squareRoot() / harmonicAmplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        let offset = acos(min(max(ratio, -1.0), 1.0))
        let candidates = try CertifiedAnalyticCurveEvaluation.sorted(CertifiedAnalyticCurveEvaluation.map([
            try normalizedAngle(phase - offset, using: &execution),
            try normalizedAngle(phase + offset, using: &execution),
        ], using: &execution) {element, execution in
            try refinedApexBoundaryAngle(
                element,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
        }, using: &execution)
        var result: [Double] = []
        var resultCapacity = result.count
        for candidate in candidates {
            try execution.consumeWork(1)
            let duplicate = try result.contains { existing in
                try execution.consumeWork(1)
                return try angularDistance(existing, candidate, using: &execution) <= tolerance.angle
            }
            guard !duplicate else { continue }
            try CertifiedAnalyticCurveEvaluation.append(candidate, to: &result, using: &execution, capacity: &resultCapacity)
        }
        return result
    }



    private static func refinedApexBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var angle = try normalizedAngle(initial, using: &execution)
        let proofTolerance = Double.ulpOfOne
            * configuration.characteristicLength * 128.0
        for _ in 0..<64 {
            try execution.consumeWork(1)
            let value = configuration.halfLinear(at: angle)
            if abs(value) <= proofTolerance {
                break
            }
            let derivative = configuration.halfLinearFirstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else {
                break
            }
            angle = try normalizedAngle(angle - step, using: &execution)
        }
        return angle
    }



    private static func refinedBoundaryAngle(
        _ initial: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var angle = try normalizedAngle(initial, using: &execution)
        let proofResidualTolerance = max(
            Double.leastNonzeroMagnitude,
            Double.ulpOfOne
                * configuration.characteristicLength
                * configuration.characteristicLength * 128.0
        )
        for _ in 0..<64 {
            try execution.consumeWork(1)
            let value = configuration.radicand(at: angle)
            if abs(value) <= proofResidualTolerance { break }
            let derivative = configuration.radicandFirstDerivative(at: angle)
            guard abs(derivative) > tolerance.angle else { break }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = try normalizedAngle(angle - step, using: &execution)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
    }



    private static func rejectConeApexContact(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let apexResidual = abs(
            (configuration.sphere.center - configuration.cone.apex).length
                - configuration.sphere.radius
        )
        if apexResidual <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "Sphere-cone intersection passes through the cone's singular apex parameter."
            )
        }
    }



    private static func spherePoleContacts(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> [PoleContact] {
        try execution.consumeWork(1)
        var result: [PoleContact] = []
        var resultCapacity = result.count
        let cosine = cos(configuration.cone.halfAngle)
        let sine = sin(configuration.cone.halfAngle)
        let basis = try analyticOrthonormalBasis(
            configuration.cone.axis,
            tolerance: tolerance
        )
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        for sign in [-1.0, 1.0] {
            try execution.consumeWork(1)
            let pole = configuration.sphere.center
                + Vector3D.unitZ * (sign * configuration.sphere.radius)
            let offset = pole - configuration.cone.apex
            let axialDistance = offset.dot(configuration.cone.axis)
            let radial = offset - configuration.cone.axis * axialDistance
            let slant = axialDistance / cosine
            let expectedRadialDistance = abs(slant) * sine
            guard abs(radial.length - expectedRadialDistance)
                <= tolerance.distance else {
                continue
            }
            guard abs(slant) > tolerance.distance else {
                continue
            }
            let signedRadial = radial / (slant * sine)
            let angle = try normalizedAngle(atan2(
                signedRadial.dot(basis.v),
                signedRadial.dot(basis.u)
            ), using: &execution)
            let signedRoot = configuration.quadraticA * cosine * slant
                - configuration.halfLinear(at: angle)
            let branches: [Double]
            if signedRoot > tolerance.distance {
                branches = try CertifiedAnalyticCurveEvaluation.values(1.0, using: &execution)
            } else if signedRoot < -tolerance.distance {
                branches = try CertifiedAnalyticCurveEvaluation.values(-1.0, using: &execution)
            } else {
                branches = try CertifiedAnalyticCurveEvaluation.values(-1.0, 1.0, using: &execution)
            }
            for branch in branches {
                try execution.consumeWork(1)
                let duplicate = try result.contains { existing in
                    try execution.consumeWork(1)
                    return try existing.branch == branch
                        && (angularDistance(existing.angle, angle, using: &execution)) <= tolerance.angle
                }
                guard !duplicate else { continue }
                try CertifiedAnalyticCurveEvaluation.append(PoleContact(
                    angle: angle,
                    branch: branch
                ), to: &result, using: &execution, capacity: &resultCapacity)
            }
        }
        return result
    }



    private static func minimumRadicand(
        from lower: Double,
        to upper: Double,
        configuration: Configuration
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
        var candidateAngles = [lower, upper]
        var candidateAnglesCapacity = candidateAngles.count
        let phase = atan2(
            configuration.radialSine,
            configuration.radialCosine
        )
        try appendPeriodicAngle(
            phase,
            from: lower,
            to: upper,
            result: &candidateAngles, capacity: &candidateAnglesCapacity
        , using: &execution)
        try appendPeriodicAngle(
            phase + Double.pi,
            from: lower,
            to: upper,
            result: &candidateAngles, capacity: &candidateAnglesCapacity
        , using: &execution)
        let harmonicAmplitude = configuration.slope
            * configuration.radialAmplitude
        if abs(harmonicAmplitude) > Double.leastNonzeroMagnitude {
            let ratio = -configuration.axialCenter / harmonicAmplitude
            if ratio >= -1.0, ratio <= 1.0 {
                let offset = acos(ratio)
                try appendPeriodicAngle(
                    phase - offset,
                    from: lower,
                    to: upper,
                    result: &candidateAngles, capacity: &candidateAnglesCapacity
                , using: &execution)
                try appendPeriodicAngle(
                    phase + offset,
                    from: lower,
                    to: upper,
                    result: &candidateAngles, capacity: &candidateAnglesCapacity
                , using: &execution)
            }
        }
        return try CertifiedAnalyticCurveEvaluation.map(candidateAngles, using: &execution) {element, execution in configuration.radicand(at: element) }
            .min() ?? -.infinity
    }



    private static func appendPeriodicAngle(
        _ angle: Double,
        from lower: Double,
        to upper: Double,
        result: inout [Double]
    ,
        capacity: inout Int, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        let firstIndex = ceil((lower - angle) / period)
        let adjusted = angle + firstIndex * period
        if adjusted >= lower, adjusted <= upper {
            try CertifiedAnalyticCurveEvaluation.append(adjusted, to: &result, using: &execution, capacity: &capacity)
        }
    }



    private static func adjustedAngle(
        _ angle: Double,
        inside interval: ClosedRange<Double>
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        var adjusted = try normalizedAngle(angle, using: &execution)
        while adjusted < interval.lowerBound - period * 0.5 {
            try execution.consumeWork(1)
            adjusted += period
        }
        while adjusted > interval.upperBound + period * 0.5 {
            try execution.consumeWork(1)
            adjusted -= period
        }
        if adjusted < interval.lowerBound {
            adjusted += period
        }
        return adjusted
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
        case sphereSurface
        case coneSurface
        case componentKind
        case lowerAngle
        case upperAngle
        case certificationTolerance
        case maximumResidualUpperBound
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .sphereSurface,
                .coneSurface,
                .componentKind,
                .lowerAngle,
                .upperAngle,
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
            sphereSurface: container.decode(Surface3D.self, forKey: .sphereSurface),
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
            componentKind: container.decode(ComponentKind.self, forKey: .componentKind),
            lowerAngle: container.decode(Double.self, forKey: .lowerAngle),
            upperAngle: container.decode(Double.self, forKey: .upperAngle),
            tolerance: tolerance
        , using: &execution)
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumResidualUpperBound,
                in: container,
                debugDescription: "The sphere-cone residual certificate does not match the reconstructed source surfaces."
            )
        }
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        guard originalNodeTraversal == nil else {
            throw EncodingError.invalidValue(self,.init(codingPath:encoder.codingPath,debugDescription:"Generated node traversal authority cannot be discarded by the legacy curve codec."))
        }
        try validate(tolerance: certificationTolerance, using: &execution)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sphereSurface, forKey: .sphereSurface)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(componentKind, forKey: .componentKind)
        try container.encode(lowerAngle, forKey: .lowerAngle)
        try container.encode(upperAngle, forKey: .upperAngle)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
#endif
}

#if !hasFeature(Embedded)
extension CertifiedSphereConeIntersectionCurve: Codable {}
extension CertifiedSphereConeIntersectionCurve.ComponentKind: Codable {}
#endif

extension CertifiedSphereConeIntersectionCurve {
    /// Reads the same private configuration and generator coefficients as the position law.
    /// The caller owns admission and retains the immutable original component and surfaces.
    func originalApexReducedSourceSnapshot(field: OriginalPhysicalAngleScalarDomain,
        tolerance: ModelingTolerance) throws -> OriginalCertifiedSphereConeApexSnapshot {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try originalApexReducedSourceSnapshot(field: field, tolerance: tolerance, using: &execution)
    }

    func originalApexReducedSourceSnapshot(field: OriginalPhysicalAngleScalarDomain,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OriginalCertifiedSphereConeApexSnapshot {
        try execution.consumeWork(1)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Other apex intervals have no source snapshot
        // contract here. Public source preparation supports only the retained [0,binary pi]
        // branch until its full interpolation and denominator guards are certified.
        guard componentKind == .apexReducedAngularInterval,
              lowerAngle == 0, upperAngle.bitPattern == Double.pi.bitPattern else {
            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
        }
        let configuration = try Self.makeConfiguration(
            sphereSurface: sphereSurface, coneSurface: coneSurface, tolerance: tolerance, using: &execution)
        let basis = try analyticOrthonormalBasis(configuration.cone.axis, tolerance: tolerance)
        let cosine = cos(configuration.cone.halfAngle)
        let sine = sin(configuration.cone.halfAngle)
        // Preserve the authored division and scale ordering from slantDifferential.
        let slantDenominator = configuration.quadraticA * cos(configuration.cone.halfAngle)
        let inverseQuadraticCosine = 1.0 / slantDenominator
        let scale = 2.0 * inverseQuadraticCosine
        // The original affine angle is finite for every closed normalized T in [0,1].
        // This apex branch does not exclude zero slant at either closed endpoint.
        guard configuration.cone.halfAngle.isFinite,
              slantDenominator.isFinite, slantDenominator > 0,
              inverseQuadraticCosine.isFinite, inverseQuadraticCosine > 0,
              scale.isFinite, scale > 0 else {
            throw OriginalSourceIssuanceFailure.unresolvedAuthority
        }
        return OriginalCertifiedSphereConeApexSnapshot(original: self, field: field,
            apex: configuration.cone.apex, axis: configuration.cone.axis,
            basisU: basis.u, basisV: basis.v, halfAngle: configuration.cone.halfAngle,
            axialCenter: configuration.axialCenter, radialCosine: configuration.radialCosine,
            radialSine: configuration.radialSine, quadraticA: configuration.quadraticA,
            quadraticC: configuration.quadraticC, sine: sine, cosine: cosine,
            slope: configuration.slope, slantDenominator: slantDenominator,
            inverseQuadraticCosine: inverseQuadraticCosine, slantScale: scale)
    }
}
