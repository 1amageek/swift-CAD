import CADCore
import CADGeometry

/// The ordered parameter interval used by an edge on its canonical 3D curve.
public struct CurveTrim: Hashable, Sendable {
    public var startParameter: Double
    public var endParameter: Double

    public init(startParameter: Double, endParameter: Double) {
        self.startParameter = startParameter
        self.endParameter = endParameter
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case startParameter
        case endParameter
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startParameter, .endParameter],
            in: decoder
        )
        startParameter = try container.decode(Double.self, forKey: .startParameter)
        endParameter = try container.decode(Double.self, forKey: .endParameter)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startParameter, forKey: .startParameter)
        try container.encode(endParameter, forKey: .endParameter)
    }
    #endif

    public func validate(on curve: Curve3D, edgeID: EdgeID, tolerance: ModelingTolerance,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32,
        maximumSubdivisionDepth: Int = 32) throws {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumAlgebraicDepth, maximumCoefficientDepth: maximumAlgebraicDepth,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
        try validate(on: curve, edgeID: edgeID, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
    }

    public func validate(on curve: Curve3D, edgeID: EdgeID, tolerance: ModelingTolerance,
        remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32, maximumSubdivisionDepth: Int = 32,
        using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
        guard remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
            (0...32).contains(maximumSubdivisionDepth) else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original trim validation exhausted source depth.")
        }
        try validateFiniteParameters(edgeID: edgeID, tolerance: tolerance)
        // Original parameter images validate their native bounds and exact span
        // below; a rounded inverse foreign period is not source-domain authority.
        if case .parameterImage = curve {} else {
            guard try curve.parameterDomain.containsSpan(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance
            ) else {
                throw TopologyError.invalidTrim(edgeID)
            }
        }
        let span = abs(endParameter - startParameter)
        switch curve {
        case .line:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case .circle:
            guard span > tolerance.angle,
                  span <= Double.pi * 2.0 else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case let .analytic(curve):
            switch curve {
            case .line:
                guard span > tolerance.distance else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .circle, .ellipse, .planeTorus:
                guard span > tolerance.angle,
                      span <= Double.pi * 2.0 else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .arc:
                guard span > tolerance.angle else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .hyperbola:
                guard span > tolerance.relative else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .parabola:
                guard span > tolerance.distance else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            }
        case .bSpline:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            guard span > tolerance.relative else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case let .parameterImage(image):
            _ = try image.sourceParameterBounds(over: ScalarInterval(lower: min(startParameter,endParameter),
                upper: max(startParameter,endParameter)), tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            try validateOriginalImageSpan(on: curve, edgeID: edgeID, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                using: &execution)
        case let .rigidImage(image):
            try validate(
                on: image.source,
                edgeID: edgeID,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                using: &execution
            )
        case let .affineImage(image):
            try validate(
                on: image.source,
                edgeID: edgeID,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                using: &execution
            )
        case let .originalAffineWord(image):
            try validate(on: image.source, edgeID: edgeID, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1, maximumAlgebraicDepth: maximumAlgebraicDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
        }
    }

    private func originalParameterSpan(on curve: Curve3D, remainingSourceDepth: Int,
        usage: inout OriginalQueryExecution) throws
        -> (source: Curve3D, magnitude: ExactRationalCoefficient) {
        var source = curve
        var span = try ExactRationalCoefficient.originalDouble(endParameter, usage: &usage)
            .subtracting(.originalDouble(startParameter, usage: &usage), usage: &usage)
        var depth = 0
        while true {
            guard remainingSourceDepth >= 0, depth < 16, depth <= remainingSourceDepth else {
                throw GeometryError.invalidDistance(abs(endParameter-startParameter))
            }
            depth += 1
            try usage.consumeWork(1)
            switch source {
            case .parameterImage(let image):
                span = try span.multiplied(by: image.parameterGain.exactCoefficient(usage: &usage), usage: &usage)
                source = image.source
            case .rigidImage(let image): source = image.source
            case .affineImage(let image): source = image.source
            case .originalAffineWord(let image): source = image.source
            default: return (source, span.isNegative ? span.negated : span)
            }
        }
    }

    package func coversOriginalCurvePeriod(on curve: Curve3D,
        remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original trim algebra policy is outside its independent envelope.")
        }
        let span = try originalParameterSpan(on: curve, remainingSourceDepth: remainingSourceDepth, usage: &execution)
        guard case .periodic(let period) = span.source.parameterDomain else { return false }
        return try span.magnitude.subtracting(.originalDouble(period, usage: &execution), usage: &execution).isZero
    }

    private func validateOriginalImageSpan(on curve: Curve3D, edgeID: EdgeID,
        tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws {
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original trim algebra policy is outside its independent envelope.")
        }
        let span = try originalParameterSpan(on: curve, remainingSourceDepth: remainingSourceDepth, usage: &execution)
        let minimum: Double, maximum: Double?
        switch span.source {
        case .line, .bSpline: minimum = tolerance.distance; maximum = nil
        case .circle: minimum = tolerance.angle; maximum = 2*Double.pi
        case .analytic(let analytic):
            switch analytic {
            case .line, .parabola: minimum = tolerance.distance; maximum = nil
            case .circle, .ellipse, .planeTorus: minimum = tolerance.angle; maximum = 2*Double.pi
            case .arc: minimum = tolerance.angle; maximum = nil
            case .hyperbola: minimum = tolerance.relative; maximum = nil
            }
        case .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            minimum = tolerance.relative; maximum = nil
        case .rigidImage, .affineImage, .parameterImage, .originalAffineWord:
            throw TopologyError.invalidTrim(edgeID)
        }
        let lowerDifference = try span.magnitude.subtracting(.originalDouble(minimum, usage: &execution), usage: &execution)
        guard lowerDifference.isPositive else { throw TopologyError.invalidTrim(edgeID) }
        if let maximum {
            let upperDifference = try span.magnitude.subtracting(.originalDouble(maximum, usage: &execution), usage: &execution)
            guard !upperDifference.isPositive else { throw TopologyError.invalidTrim(edgeID) }
        }
    }

    public func validateFiniteParameters(edgeID: EdgeID, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite else {
            throw TopologyError.invalidTrim(edgeID)
        }
    }
}

#if !hasFeature(Embedded)
extension CurveTrim: Codable {}
#endif
