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
        remainingSourceDepth: Int = 16,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int = 32, maximumSubdivisionDepth: Int = 32) throws {
        try Task.checkCancellation()
        try consumeWork?(0)
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
                consumeWork: { try consumeWork?($0) }, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try validateOriginalImageSpan(on: curve, edgeID: edgeID, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        case let .rigidImage(image):
            try validate(
                on: image.source,
                edgeID: edgeID,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSubdivisionDepth: maximumSubdivisionDepth
            )
        case let .affineImage(image):
            try validate(
                on: image.source,
                edgeID: edgeID,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth - 1,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSubdivisionDepth: maximumSubdivisionDepth
            )
        case let .originalAffineWord(image):
            try validate(on: image.source, edgeID: edgeID, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth)
        }
    }

    private func originalParameterSpan(on curve: Curve3D, remainingSourceDepth: Int,
        usage: inout OriginalSourceProofAdmission) throws
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
            try usage.visitExactCell(depth: 0)
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
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int = 16,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int = 32) throws -> Bool {
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original trim algebra policy is outside its independent envelope.")
        }
        var usage = OriginalSourceProofAdmission(consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let span = try originalParameterSpan(on: curve, remainingSourceDepth: remainingSourceDepth, usage: &usage)
        guard case .periodic(let period) = span.source.parameterDomain else { return false }
        return try span.magnitude.subtracting(.originalDouble(period, usage: &usage), usage: &usage).isZero
    }

    private func validateOriginalImageSpan(on curve: Curve3D, edgeID: EdgeID,
        tolerance: ModelingTolerance,
        remainingSourceDepth: Int, consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws {
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original trim algebra policy is outside its independent envelope.")
        }
        var usage = OriginalSourceProofAdmission(consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let span = try originalParameterSpan(on: curve, remainingSourceDepth: remainingSourceDepth, usage: &usage)
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
        let lowerDifference = try span.magnitude.subtracting(.originalDouble(minimum, usage: &usage), usage: &usage)
        guard lowerDifference.isPositive else { throw TopologyError.invalidTrim(edgeID) }
        if let maximum {
            let upperDifference = try span.magnitude.subtracting(.originalDouble(maximum, usage: &usage), usage: &usage)
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
