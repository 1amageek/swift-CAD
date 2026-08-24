import Foundation
import CADCore

package struct ExactRectangularBSplineSurfacePatch: Sendable, Hashable {
    package struct AxisMapping: Sendable, Hashable {
        package enum Kind: Sendable, Hashable {
            case identity
            case normalized
            case rationalCircularArc(segmentCount: Int)
            case normalizedRationalCircularArc(segmentCount: Int)
            case normalizedRationalHyperbola(spanCount: Int)
        }

        package let sourceLower: Double
        package let sourceUpper: Double
        package let kind: Kind

        package var targetLower: Double {
            switch kind {
            case .identity:
                sourceLower
            case .normalized, .rationalCircularArc,
                 .normalizedRationalCircularArc,
                 .normalizedRationalHyperbola:
                0.0
            }
        }

        package var targetUpper: Double {
            switch kind {
            case .identity:
                sourceUpper
            case .normalized, .normalizedRationalCircularArc,
                 .normalizedRationalHyperbola:
                1.0
            case let .rationalCircularArc(segmentCount):
                Double(segmentCount)
            }
        }

        /// Whether the target coordinate is exactly the source coordinate
        /// throughout this mapping's complete domain.
        package var preservesSourceParameter: Bool {
            switch kind {
            case .identity:
                true
            case .normalized:
                sourceLower == 0.0 && sourceUpper == 1.0
            case .rationalCircularArc, .normalizedRationalCircularArc,
                 .normalizedRationalHyperbola:
                false
            }
        }

        package func map(
            _ sourceParameter: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            try tolerance.validate()
            guard sourceParameter.isFinite,
                  sourceParameter >= sourceLower - tolerance.angle,
                  sourceParameter <= sourceUpper + tolerance.angle else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: min(
                        abs(sourceParameter - sourceLower),
                        abs(sourceParameter - sourceUpper)
                    ),
                    tolerance: tolerance,
                    message: "A source surface parameter lies outside the exact patch mapping domain."
                )
            }
            switch kind {
            case .identity:
                return min(max(sourceParameter, sourceLower), sourceUpper)
            case .normalized:
                return (min(max(sourceParameter, sourceLower), sourceUpper) - sourceLower)
                    / (sourceUpper - sourceLower)
            case let .rationalCircularArc(segmentCount),
                 let .normalizedRationalCircularArc(segmentCount):
                if sourceParameter <= sourceLower + tolerance.angle {
                    return 0.0
                }
                if sourceParameter >= sourceUpper - tolerance.angle {
                    return kind.isNormalized ? 1.0 : Double(segmentCount)
                }
                let segmentAngle = (sourceUpper - sourceLower) / Double(segmentCount)
                let rawIndex = Int(floor((sourceParameter - sourceLower) / segmentAngle))
                let segmentIndex = min(max(rawIndex, 0), segmentCount - 1)
                let segmentStart = sourceLower + Double(segmentIndex) * segmentAngle
                let segmentMiddle = segmentStart + segmentAngle * 0.5
                let halfAngleTangent = tan(segmentAngle * 0.25)
                guard halfAngleTangent.isFinite,
                      abs(halfAngleTangent) > tolerance.relative else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "The exact circular-arc surface parameter mapping is singular."
                    )
                }
                let projectedCoordinate = tan(
                    (sourceParameter - segmentMiddle) * 0.5
                ) / halfAngleTangent
                let localParameter = (1.0 + projectedCoordinate) * 0.5
                let parameter = Double(segmentIndex) + localParameter
                return kind.isNormalized ? parameter / Double(segmentCount) : parameter
            case let .normalizedRationalHyperbola(spanCount):
                if sourceParameter <= sourceLower + tolerance.relative {
                    return 0.0
                }
                if sourceParameter >= sourceUpper - tolerance.relative {
                    return 1.0
                }
                let spanWidth = (sourceUpper - sourceLower) / Double(spanCount)
                let rawIndex = Int(floor((sourceParameter - sourceLower) / spanWidth))
                let spanIndex = min(max(rawIndex, 0), spanCount - 1)
                let spanStart = sourceLower + Double(spanIndex) * spanWidth
                let spanMiddle = spanStart + spanWidth * 0.5
                let halfSpanTangent = tanh(spanWidth * 0.25)
                guard halfSpanTangent.isFinite,
                      abs(halfSpanTangent) > tolerance.relative else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "The exact hyperbolic curve parameter mapping is singular."
                    )
                }
                let projectedCoordinate = tanh(
                    (sourceParameter - spanMiddle) * 0.5
                ) / halfSpanTangent
                let localParameter = (1.0 + projectedCoordinate) * 0.5
                return (Double(spanIndex) + localParameter) / Double(spanCount)
            }
        }
    }

    package let surface: BSplineSurface3D
    package let uMapping: AxisMapping
    package let vMapping: AxisMapping

    package func parameter(
        for sourceParameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        SurfaceParameter(
            u: try uMapping.map(sourceParameter.u, tolerance: tolerance),
            v: try vMapping.map(sourceParameter.v, tolerance: tolerance)
        )
    }
}

private extension ExactRectangularBSplineSurfacePatch.AxisMapping.Kind {
    var isNormalized: Bool {
        switch self {
        case .normalizedRationalCircularArc:
            true
        case .identity, .normalized, .rationalCircularArc,
             .normalizedRationalHyperbola:
            false
        }
    }
}
