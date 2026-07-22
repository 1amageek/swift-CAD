import Foundation
import CADCore

package struct ExactRectangularBSplineSurfacePatch: Sendable, Hashable {
    package struct AxisMapping: Sendable, Hashable {
        package enum Kind: Sendable, Hashable {
            case identity
            case rationalCircularArc(segmentCount: Int)
        }

        package let sourceLower: Double
        package let sourceUpper: Double
        package let kind: Kind

        package var targetLower: Double {
            switch kind {
            case .identity:
                sourceLower
            case .rationalCircularArc:
                0.0
            }
        }

        package var targetUpper: Double {
            switch kind {
            case .identity:
                sourceUpper
            case let .rationalCircularArc(segmentCount):
                Double(segmentCount)
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
            case let .rationalCircularArc(segmentCount):
                if sourceParameter <= sourceLower + tolerance.angle {
                    return 0.0
                }
                if sourceParameter >= sourceUpper - tolerance.angle {
                    return Double(segmentCount)
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
                return Double(segmentIndex) + localParameter
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
