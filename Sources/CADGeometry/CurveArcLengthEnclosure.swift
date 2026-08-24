import CADCore

/// A certified enclosure of a curve's arc length over a bounded parameter interval.
public struct CurveArcLengthEnclosure: Codable, Hashable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double

    public init(
        lowerBound: Double,
        upperBound: Double
    ) throws {
        guard lowerBound.isFinite,
              upperBound.isFinite,
              lowerBound >= 0.0,
              upperBound >= lowerBound else {
            throw GeometryError.invalidDistance(upperBound)
        }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var width: Double {
        upperBound - lowerBound
    }

    public var midpoint: Double {
        lowerBound + width * 0.5
    }
}

/// A certified parameter interval containing the requested arc-length fraction.
public struct CurveArcLengthParameterEnclosure: Codable, Hashable, Sendable {
    public let parameterRange: ScalarInterval
    public let spatialErrorUpperBound: Double

    public init(
        parameterRange: ScalarInterval,
        spatialErrorUpperBound: Double
    ) throws {
        guard spatialErrorUpperBound.isFinite,
              spatialErrorUpperBound >= 0.0 else {
            throw GeometryError.invalidDistance(spatialErrorUpperBound)
        }
        self.parameterRange = parameterRange
        self.spatialErrorUpperBound = spatialErrorUpperBound
    }

    public var parameter: Double {
        parameterRange.midpoint
    }
}

public struct CurveArcLengthOptions: Codable, Hashable, Sendable {
    public var absoluteAccuracy: Double?
    public var relativeAccuracy: Double
    public var maximumSubdivisionDepth: Int
    public var maximumIntervalCount: Int

    public init(
        absoluteAccuracy: Double? = nil,
        relativeAccuracy: Double = 1.0e-10,
        maximumSubdivisionDepth: Int = 48,
        maximumIntervalCount: Int = 131_072
    ) {
        self.absoluteAccuracy = absoluteAccuracy
        self.relativeAccuracy = relativeAccuracy
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumIntervalCount = maximumIntervalCount
    }

    func validatedAbsoluteAccuracy(
        tolerance: ModelingTolerance
    ) throws -> Double {
        try tolerance.validate()
        let accuracy = absoluteAccuracy ?? tolerance.distance
        guard accuracy.isFinite,
              accuracy > 0.0,
              relativeAccuracy.isFinite,
              relativeAccuracy >= 0.0,
              maximumSubdivisionDepth > 0,
              maximumIntervalCount >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve arc-length options require positive finite accuracy and resource limits."
            )
        }
        return accuracy
    }
}
