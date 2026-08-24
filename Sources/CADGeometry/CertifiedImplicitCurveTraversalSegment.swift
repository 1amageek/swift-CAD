import CADCore
import Foundation

/// A monotone canonical graph interval covered by one local span of a
/// certified implicit pcurve. Closed curves may require two segments when an
/// unwrapped traversal crosses the canonical `0...1` seam.
package struct CertifiedImplicitCurveTraversalSegment: Sendable, Hashable {
    package let curveLowerFraction: Double
    package let curveUpperFraction: Double
    package let canonicalLowerFraction: Double
    package let canonicalUpperFraction: Double
    package let direction: SurfaceParameterCurveDirection

    package init(
        curveLowerFraction: Double,
        curveUpperFraction: Double,
        canonicalLowerFraction: Double,
        canonicalUpperFraction: Double,
        direction: SurfaceParameterCurveDirection
    ) {
        self.curveLowerFraction = curveLowerFraction
        self.curveUpperFraction = curveUpperFraction
        self.canonicalLowerFraction = canonicalLowerFraction
        self.canonicalUpperFraction = canonicalUpperFraction
        self.direction = direction
    }

    package var orientationMultiplier: Double {
        direction == .forward ? 1.0 : -1.0
    }

    package func curveFractionRange(
        forCanonicalLower lower: Double,
        upper: Double
    ) -> (lower: Double, upper: Double) {
        let canonicalSpan = canonicalUpperFraction - canonicalLowerFraction
        let curveSpan = curveUpperFraction - curveLowerFraction
        switch direction {
        case .forward:
            return (
                curveLowerFraction
                    + (lower - canonicalLowerFraction) / canonicalSpan * curveSpan,
                curveLowerFraction
                    + (upper - canonicalLowerFraction) / canonicalSpan * curveSpan
            )
        case .reversed:
            return (
                curveLowerFraction
                    + (canonicalUpperFraction - upper) / canonicalSpan * curveSpan,
                curveLowerFraction
                    + (canonicalUpperFraction - lower) / canonicalSpan * curveSpan
            )
        }
    }
}

package extension CertifiedImplicitSurfaceParameterCurve {
    func canonicalTraversalSegments(
        tolerance: ModelingTolerance
    ) throws -> [CertifiedImplicitCurveTraversalSegment] {
        try tolerance.validate()
        try intersection.validate(tolerance: tolerance)
        let displacement = endFraction - startFraction
        guard displacement.isFinite,
              abs(displacement) > tolerance.relative else {
            throw GeometryError.invalidDistance(displacement)
        }

        var globalBreaks = [startFraction]
        if min(startFraction, endFraction) < 1.0,
           max(startFraction, endFraction) > 1.0 {
            globalBreaks.append(1.0)
        }
        globalBreaks.append(endFraction)

        var result: [CertifiedImplicitCurveTraversalSegment] = []
        result.reserveCapacity(globalBreaks.count - 1)
        for index in 1..<globalBreaks.count {
            let globalStart = globalBreaks[index - 1]
            let globalEnd = globalBreaks[index]
            let midpoint = globalStart + (globalEnd - globalStart) * 0.5
            let periodOffset = midpoint >= 1.0 ? 1.0 : 0.0
            let canonicalStart = min(max(globalStart - periodOffset, 0.0), 1.0)
            let canonicalEnd = min(max(globalEnd - periodOffset, 0.0), 1.0)
            let canonicalSpan = abs(canonicalEnd - canonicalStart)
            guard canonicalSpan > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A certified implicit pcurve produced an empty canonical traversal segment."
                )
            }
            let firstCurveFraction = (globalStart - startFraction) / displacement
            let secondCurveFraction = (globalEnd - startFraction) / displacement
            result.append(CertifiedImplicitCurveTraversalSegment(
                curveLowerFraction: min(firstCurveFraction, secondCurveFraction),
                curveUpperFraction: max(firstCurveFraction, secondCurveFraction),
                canonicalLowerFraction: min(canonicalStart, canonicalEnd),
                canonicalUpperFraction: max(canonicalStart, canonicalEnd),
                direction: canonicalStart < canonicalEnd ? .forward : .reversed
            ))
        }

        guard result.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified implicit pcurve produced no canonical traversal segments."
            )
        }
        return result
    }
}
