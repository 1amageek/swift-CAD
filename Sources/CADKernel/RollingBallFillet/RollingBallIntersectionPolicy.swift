import CADCore
import CADGeometry

/// Selects the existing request allowance on the caller's shared execution.
enum RollingBallIntersectionPolicy {
    static let maximumDepth = 20
    static let maximumSourceDepth = 20
    static let maximumAlgebraicDepth = 32

    static func contribution(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OriginalQueryContributionHandle {
        try tolerance.validate()
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        let bytes = requirements.maximumScalarCount.multipliedReportingOverflow(by: MemoryLayout<Double>.stride)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        return try execution.makeContributionHandle(workLimit: 65_536,
            storageByteLimit: bytes.partialValue, storageByteQuantum: MemoryLayout<Double>.stride,
            executionLimits: .init(maximumValueDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumAlgebraicDepth,
                remainingSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumDepth, maximumSpans: 4096))
    }
}
