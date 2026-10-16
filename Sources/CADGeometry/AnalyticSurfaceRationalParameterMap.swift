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

/// The exact chart map from the rational analytic surface used by the
/// intersection solver to the parameter chart owned by the public surface.
package struct AnalyticSurfaceRationalParameterMap: Sendable {
    package struct Enclosure: Sendable, Hashable {
        package let u: ScalarInterval
        package let v: ScalarInterval
        package let uDerivative: ScalarInterval
        package let vDerivative: ScalarInterval
    }

    private enum Mapping: Sendable {
        case plane(
            uFromU: Double,
            uFromV: Double,
            vFromU: Double,
            vFromV: Double
        )
        case cylinder(uOffset: Double)
        case cone(uOffset: Double)
        case sphere(uOffset: Double)
        case torus(uOffset: Double, vOffset: Double)
    }

    private let mapping: Mapping

    package init(
        surface: Surface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(surface: surface, periodicSeamOffset: periodicSeamOffset, tolerance: tolerance, using: &execution)
    }

    package init(
        surface: Surface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard periodicSeamOffset.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic rational parameter map requires a finite seam offset."
            )
        }
        self.mapping = try Self.mapping(
            for: surface,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        , using: &execution)
    }

    package func parameter(
        fromRational parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try self.parameter(fromRational: parameter, tolerance: tolerance, using: &execution)
    }

    package func parameter(
        fromRational parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        try tolerance.validate()
        switch mapping {
        case let .plane(uFromU, uFromV, vFromU, vFromV):
            return SurfaceParameter(
                u: parameter.u * uFromU + parameter.v * uFromV,
                v: parameter.u * vFromU + parameter.v * vFromV
            )
        case let .cylinder(uOffset), let .cone(uOffset):
            return SurfaceParameter(
                u: try rationalCircleAngle(
                    at: parameter.u,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution) + uOffset,
                v: parameter.v
            )
        case let .sphere(uOffset):
            return SurfaceParameter(
                u: try rationalCircleAngle(
                    at: parameter.u,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution) + uOffset,
                v: try rationalCircleAngle(
                    at: parameter.v,
                    upperBound: 2.0,
                    tolerance: tolerance
                , using: &execution) - Double.pi * 0.5
            )
        case let .torus(uOffset, vOffset):
            return SurfaceParameter(
                u: try rationalCircleAngle(
                    at: parameter.u,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution) + uOffset,
                v: try rationalCircleAngle(
                    at: parameter.v,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution) + vOffset
            )
        }
    }

    package func enclosure(
        rationalU: ScalarInterval,
        rationalV: ScalarInterval,
        rationalUDerivative: ScalarInterval,
        rationalVDerivative: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Enclosure {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try enclosure(rationalU: rationalU, rationalV: rationalV, rationalUDerivative: rationalUDerivative, rationalVDerivative: rationalVDerivative, tolerance: tolerance, using: &execution)
    }

    package func enclosure(
        rationalU: ScalarInterval,
        rationalV: ScalarInterval,
        rationalUDerivative: ScalarInterval,
        rationalVDerivative: ScalarInterval,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Enclosure {
        try execution.consumeWork(1)
        try tolerance.validate()
        switch mapping {
        case let .plane(uFromU, uFromV, vFromU, vFromV):
            return Enclosure(
                u: try linearCombination(
                    rationalU,
                    multipliedBy: uFromU,
                    plus: rationalV,
                    multipliedBy: uFromV
                , using: &execution),
                v: try linearCombination(
                    rationalU,
                    multipliedBy: vFromU,
                    plus: rationalV,
                    multipliedBy: vFromV
                , using: &execution),
                uDerivative: try linearCombination(
                    rationalUDerivative,
                    multipliedBy: uFromU,
                    plus: rationalVDerivative,
                    multipliedBy: uFromV
                , using: &execution),
                vDerivative: try linearCombination(
                    rationalUDerivative,
                    multipliedBy: vFromU,
                    plus: rationalVDerivative,
                    multipliedBy: vFromV
                , using: &execution)
            )
        case let .cylinder(uOffset), let .cone(uOffset):
            return Enclosure(
                u: try rationalCircleAngleBounds(
                    rationalU,
                    offset: uOffset,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution),
                v: rationalV,
                uDerivative: try rationalCircleAngleDerivativeBounds(
                    rationalUDerivative
                , using: &execution),
                vDerivative: rationalVDerivative
            )
        case let .sphere(uOffset):
            return Enclosure(
                u: try rationalCircleAngleBounds(
                    rationalU,
                    offset: uOffset,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution),
                v: try rationalCircleAngleBounds(
                    rationalV,
                    offset: -Double.pi * 0.5,
                    upperBound: 2.0,
                    tolerance: tolerance
                , using: &execution),
                uDerivative: try rationalCircleAngleDerivativeBounds(
                    rationalUDerivative
                , using: &execution),
                vDerivative: try rationalCircleAngleDerivativeBounds(
                    rationalVDerivative
                , using: &execution)
            )
        case let .torus(uOffset, vOffset):
            return Enclosure(
                u: try rationalCircleAngleBounds(
                    rationalU,
                    offset: uOffset,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution),
                v: try rationalCircleAngleBounds(
                    rationalV,
                    offset: vOffset,
                    upperBound: 4.0,
                    tolerance: tolerance
                , using: &execution),
                uDerivative: try rationalCircleAngleDerivativeBounds(
                    rationalUDerivative
                , using: &execution),
                vDerivative: try rationalCircleAngleDerivativeBounds(
                    rationalVDerivative
                , using: &execution)
            )
        }
    }

    package func rationalSearchRanges(
        surfaceU: ScalarInterval?,
        surfaceV: ScalarInterval?
    ) throws -> (u: ScalarInterval?, v: ScalarInterval?)? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try rationalSearchRanges(surfaceU: surfaceU, surfaceV: surfaceV, using: &execution)
    }

    package func rationalSearchRanges(
        surfaceU: ScalarInterval?,
        surfaceV: ScalarInterval?
    ,
        using execution: inout OriginalQueryExecution) throws -> (u: ScalarInterval?, v: ScalarInterval?)? {
        try execution.consumeWork(1)
        switch mapping {
        case let .plane(uFromU, uFromV, vFromU, vFromV):
            guard let surfaceU, let surfaceV else {
                return (u: nil, v: nil)
            }
            return (
                u: try linearCombination(
                    surfaceU,
                    multipliedBy: uFromU,
                    plus: surfaceV,
                    multipliedBy: vFromU
                , using: &execution),
                v: try linearCombination(
                    surfaceU,
                    multipliedBy: uFromV,
                    plus: surfaceV,
                    multipliedBy: vFromV
                , using: &execution)
            )
        case let .cylinder(uOffset), let .cone(uOffset):
            guard let u = try periodicRationalRange(
                requested: surfaceU,
                surfaceOffset: uOffset
            , using: &execution) else { return nil }
            return (u: u, v: surfaceV)
        case let .sphere(uOffset):
            guard let u = try periodicRationalRange(
                requested: surfaceU,
                surfaceOffset: uOffset
            , using: &execution) else { return nil }
            return (
                u: u,
                v: try sphericalMeridianRationalRange(requested: surfaceV, using: &execution)
            )
        case let .torus(uOffset, vOffset):
            guard let u = try periodicRationalRange(
                requested: surfaceU,
                surfaceOffset: uOffset
            , using: &execution), let v = try periodicRationalRange(
                requested: surfaceV,
                surfaceOffset: vOffset
            , using: &execution) else { return nil }
            return (u: u, v: v)
        }
    }



    private static func mapping(
        for surface: Surface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ,
        sourceDepth: Int = 0, using execution: inout OriginalQueryExecution) throws -> Mapping {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(sourceDepth)
        switch surface {
        case let .plane(plane):
            let target = try plane.parameterBasis(tolerance: tolerance)
            let rational = try OriginalStoredPlaneBasis.basis(
                plane.normal,
                tolerance: tolerance
            )
            return try planeMapping(rational: rational, target: target, using: &execution)
        case let .cylinder(cylinder):
            let target = try circleOrthonormalBasis(
                cylinder.axis,
                tolerance: tolerance
            )
            let rational = try analyticOrthonormalBasis(
                cylinder.axis,
                tolerance: tolerance
            )
            let chartOffset = atan2(
                rational.u.dot(target.v),
                rational.u.dot(target.u)
            )
            return .cylinder(uOffset: periodicSeamOffset + chartOffset)
        case let .analytic(analytic):
            switch analytic {
            case let .plane(_, normal):
                let basis = try OriginalStoredPlaneBasis.basis(
                    normal,
                    tolerance: tolerance
                )
                return try planeMapping(rational: basis, target: basis, using: &execution)
            case .cylinder:
                return .cylinder(uOffset: periodicSeamOffset)
            case .cone:
                return .cone(uOffset: periodicSeamOffset)
            case .sphere:
                return .sphere(uOffset: periodicSeamOffset)
            case .torus:
                return .torus(
                    uOffset: periodicSeamOffset,
                    vOffset: periodicSeamOffset
                )
            }
        case let .procedural(.offset(offset)):
            let nextDepth = try exactScalarCount(sourceDepth, 1)
            return try mapping(
                for: offset.source,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance, sourceDepth: nextDepth, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original procedural sources have no
        // certified analytic-chart reduction in this rational-map entry point.
        // They must fail until source-preserving chart equivalence is proved.
        case .bSpline, .procedural:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic rational parameter map requires an exact analytic surface chart."
            )
        }
    }



    private static func planeMapping(
        rational: (u: Vector3D, v: Vector3D),
        target: (u: Vector3D, v: Vector3D)
    ,
        using execution: inout OriginalQueryExecution) throws -> Mapping {
        try execution.consumeWork(1)
        return .plane(
            uFromU: rational.u.dot(target.u),
            uFromV: rational.v.dot(target.u),
            vFromU: rational.u.dot(target.v),
            vFromV: rational.v.dot(target.v)
        )
    }



    private func rationalCircleAngleBounds(
        _ parameter: ScalarInterval,
        offset: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        let lower = try rationalCircleAngle(
            at: parameter.lower,
            upperBound: upperBound,
            tolerance: tolerance
        , using: &execution) + offset
        let upper = try rationalCircleAngle(
            at: parameter.upper,
            upperBound: upperBound,
            tolerance: tolerance
        , using: &execution) + offset
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "An analytic rational circle parameter lost monotone angle order."
            )
        }
        return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
    }



    private func rationalCircleAngle(
        at parameter: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard parameter.isFinite,
              parameter >= -tolerance.relative,
              parameter <= upperBound + tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic rational circle parameter left its certified conversion domain."
            )
        }
        let clamped = min(max(parameter, 0.0), upperBound)
        if clamped >= 4.0 { return 2.0 * Double.pi }
        let segment = min(max(Int(floor(clamped)), 0), 3)
        let local = clamped - Double(segment)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement + local * local
        return Double(segment) * Double.pi * 0.5 + atan2(y, x)
    }



    private func rationalCircleAngleDerivativeBounds(
        _ derivative: ScalarInterval
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        // Every rational quadratic quarter-circle span has a positive angle
        // derivative within this outward-conservative scale enclosure.
        let lowerScale = 1.0.nextDown
        let upperScale = 2.0.nextUp
        let first = derivative.lower * lowerScale
        let second = derivative.lower * upperScale
        let third = derivative.upper * lowerScale
        let fourth = derivative.upper * upperScale
        return try ScalarInterval(
            lower: min(first, second, third, fourth).nextDown,
            upper: max(first, second, third, fourth).nextUp
        )
    }



    private func periodicRationalRange(
        requested: ScalarInterval?,
        surfaceOffset: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval? {
        try execution.consumeWork(1)
        guard let requested else {
            return try ScalarInterval(lower: 0.0, upper: 4.0)
        }
        let period = 2.0 * Double.pi
        guard requested.width < period else {
            return try ScalarInterval(lower: 0.0, upper: 4.0)
        }
        let cycle = floor((requested.lower - surfaceOffset) / period)
        let lower = requested.lower - surfaceOffset - cycle * period
        let upper = requested.upper - surfaceOffset - cycle * period
        let boundaryEnvelope = Double.ulpOfOne * 4_096.0
        guard lower >= -boundaryEnvelope,
              upper <= period + boundaryEnvelope else {
            return nil
        }
        let internalLower = try rationalCircleParameter(
            angle: max(lower, 0.0)
        , using: &execution).nextDown
        let internalUpper = try rationalCircleParameter(
            angle: min(upper, period)
        , using: &execution).nextUp
        guard internalLower < internalUpper else { return nil }
        return try ScalarInterval(
            lower: max(0.0, internalLower),
            upper: min(4.0, internalUpper)
        )
    }



    private func sphericalMeridianRationalRange(
        requested: ScalarInterval?
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval? {
        try execution.consumeWork(1)
        guard let requested else {
            return try ScalarInterval(lower: 0.0, upper: 2.0)
        }
        let lowerLatitude = -Double.pi * 0.5
        let upperLatitude = Double.pi * 0.5
        let lower = max(requested.lower, lowerLatitude)
        let upper = min(requested.upper, upperLatitude)
        guard lower <= upper else {
            return try ScalarInterval(lower: 0.0, upper: 0.0)
        }
        return try ScalarInterval(
            lower: try rationalCircleParameter(angle: lower - lowerLatitude, using: &execution).nextDown,
            upper: try rationalCircleParameter(angle: upper - lowerLatitude, using: &execution).nextUp
        )
    }



    private func rationalCircleParameter(angle: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let period = 2.0 * Double.pi
        if angle <= 0.0 { return 0.0 }
        if angle >= period { return 4.0 }
        let quarterAngle = Double.pi * 0.5
        let quarter = min(Int(floor(angle / quarterAngle)), 3)
        let localAngle = angle - Double(quarter) * quarterAngle
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<64 {
            try execution.consumeWork(1)
            let parameter = (lower + upper) * 0.5
            if try rationalQuarterCircleAngle(parameter: parameter, using: &execution) < localAngle {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return Double(quarter) + (lower + upper) * 0.5
    }



    private func rationalQuarterCircleAngle(parameter: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let oneMinusParameter = 1.0 - parameter
        let weightedProduct =
            2.0 * sqrt(0.5) * oneMinusParameter * parameter
        let x = oneMinusParameter * oneMinusParameter + weightedProduct
        let y = weightedProduct + parameter * parameter
        return atan2(y, x)
    }



    private func linearCombination(
        _ first: ScalarInterval,
        multipliedBy firstScale: Double,
        plus second: ScalarInterval,
        multipliedBy secondScale: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        let firstLower = first.lower * firstScale
        let firstUpper = first.upper * firstScale
        let secondLower = second.lower * secondScale
        let secondUpper = second.upper * secondScale
        return try ScalarInterval(
            lower: (min(firstLower, firstUpper)
                + min(secondLower, secondUpper)).nextDown,
            upper: (max(firstLower, firstUpper)
                + max(secondLower, secondUpper)).nextUp
        )
    }
}
