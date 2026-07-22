import CADCore

/// A range certificate derived from a parent full-graph Krawczyk cell. It does
/// not claim a second independent existence proof; uniqueness is inherited
/// from the parent and the restricted bounds follow from its derivative proof.
public struct CertifiedImplicitIntersectionGraphSubcell: Sendable, Hashable {
    public let parameterBox: SurfaceIntersectionParameterBox
    public let parameterDerivativeBounds: [ScalarInterval]

    init(
        parameterBox: SurfaceIntersectionParameterBox,
        parameterDerivativeBounds: [ScalarInterval]
    ) {
        self.parameterBox = parameterBox
        self.parameterDerivativeBounds = parameterDerivativeBounds
    }
}

public extension CertifiedImplicitIntersectionGraphCell {
    func restrictedBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphSubcell {
        try tolerance.validate()
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= 0.0,
              upperFraction <= 1.0,
              upperFraction - lowerFraction > tolerance.relative else {
            throw GeometryError.invalidDistance(upperFraction - lowerFraction)
        }
        let midpointFraction = lowerFraction
            + (upperFraction - lowerFraction) * 0.5
        let traversalStart = try parameterPair(
            atNormalizedFraction: lowerFraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let traversalMidpoint = try parameterPair(
            atNormalizedFraction: midpointFraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let traversalEnd = try parameterPair(
            atNormalizedFraction: upperFraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let parentDerivatives = try parameterDerivativeBounds(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let localSpan = upperFraction - lowerFraction
        let localHalfSpan = localSpan * 0.5
        var intervals: [ScalarInterval] = []
        var derivatives: [ScalarInterval] = []
        intervals.reserveCapacity(4)
        derivatives.reserveCapacity(4)
        for coordinate in SurfaceIntersectionParameterCoordinate.allCases {
            let index = coordinate.rawValue
            let source = parameterBox.interval(for: coordinate)
            if coordinate == freeParameter {
                let endpointValues = [
                    traversalStart.values[index],
                    traversalEnd.values[index],
                ]
                intervals.append(try ScalarInterval(
                    lower: endpointValues.min()!,
                    upper: endpointValues.max()!
                ))
            } else {
                let midpointValue = traversalMidpoint.values[index]
                let parentDerivative = parentDerivatives[index]
                let radius = max(
                    abs(parentDerivative.lower),
                    abs(parentDerivative.upper)
                ) * localHalfSpan
                let anchorValues = [
                    traversalStart.values[index],
                    midpointValue,
                    traversalEnd.values[index],
                ]
                var lower = min(
                    anchorValues.min()!,
                    midpointValue - radius
                ).nextDown
                var upper = max(
                    anchorValues.max()!,
                    midpointValue + radius
                ).nextUp
                lower = max(lower, source.lower)
                upper = min(upper, source.upper)
                if upper - lower <= Double.leastNonzeroMagnitude {
                    lower = midpointValue.nextDown
                    upper = midpointValue.nextUp
                }
                intervals.append(try ScalarInterval(lower: lower, upper: upper))
            }
            let derivative = parentDerivatives[index]
            let products = [
                derivative.lower * localSpan,
                derivative.upper * localSpan,
            ]
            derivatives.append(try ScalarInterval(
                lower: products.min()!.nextDown,
                upper: products.max()!.nextUp
            ))
        }
        return CertifiedImplicitIntersectionGraphSubcell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: intervals[0],
                firstV: intervals[1],
                secondU: intervals[2],
                secondV: intervals[3]
            ),
            parameterDerivativeBounds: derivatives
        )
    }
}
