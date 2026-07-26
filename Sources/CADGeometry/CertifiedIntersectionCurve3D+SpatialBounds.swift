import CADCore

extension CertifiedIntersectionCurve3D {
    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        switch self {
        case let .sphereCone(curve):
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                return try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            case .boundedAngularInterval:
                return try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
            case .apexReducedAngularInterval:
                return try curve
                    .apexReducedBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .negativeOpenAngularInterval,
                 .positiveOpenAngularInterval:
                return try curve
                    .openBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
            }
        case let .coneCone(curve):
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                return try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            case .boundedAngularInterval:
                return try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
            case .apexReducedAngularInterval:
                return try curve
                    .apexReducedBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            }
        case let .coneCylinder(curve):
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                return try curve
                    .fullBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .rulingParallelLinear:
                return try curve
                    .rulingParallelSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .boundedAngularInterval:
                return try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
            case .apexLowerNodeInterval, .apexUpperNodeInterval:
                return try curve
                    .apexNodeSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
            }
        case let .coneTorus(curve):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
        }
    }

    func structuralBreakParameters(
        within range: ScalarInterval
    ) -> [Double] {
        switch self {
        case let .coneTorus(curve):
            guard curve.apexReduction?.componentKind
                    == .generatorTangencyInterval,
                  range.lower < 0.5,
                  range.upper > 0.5 else {
                return []
            }
            return [0.5]
        case let .parallelTorusTorus(curve):
            guard curve.componentKind == .nearNodalClosedLoop,
                  range.lower < 0.5,
                  range.upper > 0.5 else {
                return []
            }
            return [0.5]
        case .sphereCone, .coneCone, .coneCylinder:
            return []
        }
    }
}
