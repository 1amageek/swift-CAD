import CADCore
import CADGeometry

/// Composes a selected foreign chart without replacing its shared intrinsic basis.
public enum IndependentShapeAngularCurveSelection {
    public static func physicalArc(basis: Curve3D, gain: ExactRationalCoefficient,
        first: Double, last: Double, increasing: Bool, tolerance: ModelingTolerance,
        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        let start = try gain.multiplied(by: .originalDouble(first, usage: &execution), usage: &execution)
        let end = try gain.multiplied(by: .originalDouble(last, usage: &execution), usage: &execution)
        let difference = try end.subtracting(start, usage: &execution)
        let desired = increasing ? 1 : -1
        let turns: Int
        if difference.canonicalSign == desired { turns = 0 }
        else {
            func agrees(_ count: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
                let transport = OriginalAngularParameterTransport.physicalRadianArc(start: start, end: end,
                    additionalTurns: increasing ? count : -count)
                return try transport.orientationSign(usage: &execution) == desired
            }
            var lower = 0, upper = Int.max
            guard try agrees(upper, using: &execution) else {
                throw IndependentShapeSourceError.resourceLimitExceeded("Physical-radian trim exceeds the retained integer turn domain.")
            }
            while upper - lower > 1 {
                try execution.consumeWork(1)
                let middle = lower + (upper - lower) / 2
                if try agrees(middle, using: &execution) { upper = middle } else { lower = middle }
            }
            turns = increasing ? upper : -upper
        }
        let transport = OriginalAngularParameterTransport.physicalRadianArc(start: start, end: end, additionalTurns: turns)
        return try transportedCurve(basis: basis, transport: transport, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }
    package static func physicalArcTransport(in curve: Curve3D) -> OriginalAngularParameterTransport? {
        let original: Curve3D
        if case .originalAffineWord(let image) = curve { original = image.source } else { original = curve }
        if case .originalAngularTransport(let image) = original,
           case .physicalRadianArc = image.transport { return image.transport }
        return nil
    }
    private static func transportedCurve(basis: Curve3D,
        transport: OriginalAngularParameterTransport, tolerance: ModelingTolerance, maximumSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int, using execution: inout OriginalQueryExecution) throws -> Curve3D {
        if case .originalAffineWord(let image) = basis {
            let local = try OriginalAngularTransportCurve3D(source: image.source, transport: transport,
                tolerance: tolerance, usage: &execution)
            return .originalAffineWord(try OriginalAffineWordCurve3D(source: .originalAngularTransport(local),
                operationWord: image.operationWord, tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                usage: &execution))
        }
        return .originalAngularTransport(try OriginalAngularTransportCurve3D(source: basis,
            transport: transport, tolerance: tolerance, usage: &execution))
    }
    public static func foreignCurve(basis: Curve3D,
        law: IndependentShapeAngularSource.CoordinateLaw, tolerance: ModelingTolerance,
        maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        switch law {
        case .canonicalGain(let gain):
            let selected = Curve3D.parameterImage(ParameterImageCurve3D(validatedSource: basis,
                parameterGain: gain, offset: 0))
            try selected.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: maximumSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            return selected
        case .physicalRadians(let gain):
            let transport = OriginalAngularParameterTransport.physicalRadians(gain: gain, offset: .zero)
            return try transportedCurve(basis: basis, transport: transport, tolerance: tolerance,
                maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
    }
}
