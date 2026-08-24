import CADCore

/// A reusable certified arc-length representation for one bounded curve span.
public protocol CurveArcLengthParameterization: Sendable {
    var lengthEnclosure: CurveArcLengthEnclosure { get }

    func parameterEnclosure(
        atArcLengthFraction fraction: Double
    ) throws -> CurveArcLengthParameterEnclosure
}

public protocol CurveArcLengthResolving: Sendable {
    func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure

    func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure

    func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization
}

public extension CurveArcLengthResolving {
    func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try enclosure(
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }

    func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        try parameterEnclosure(
            atArcLengthFraction: fraction,
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }

    func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization {
        try parameterization(
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(),
            tolerance: tolerance
        )
    }
}
