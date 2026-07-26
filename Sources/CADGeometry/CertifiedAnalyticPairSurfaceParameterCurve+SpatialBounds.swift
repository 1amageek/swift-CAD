import CADCore

extension CertifiedAnalyticPairSurfaceParameterCurve {
    var hasSpatialDifferentialMagnitudeBounds: Bool {
        switch intersection.definition {
        case .cylinderCylinder, .boundedPlaneCone:
            return true
        case let .sphereCylinder(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .sphereCone(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .coneCylinder(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .coneCone(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .planeTorus(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .congruentTorusTorus(curve):
            return curve.sectionCurve.componentKind == .negativeFullBranch
                || curve.sectionCurve.componentKind == .positiveFullBranch
        case let .parallelTorusCylinder(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case .generalTorusCylinder:
            return true
        case let .generalConeTorus(curve):
            return curve.apexReduction == nil
        case let .sphereTorus(curve):
            return curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .parallelTorusTorus(curve):
            return curve.componentKind == .regularClosed
        case .generalTorusTorus:
            return true
        }
    }

    func fullBranchCylinderSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        guard case let .cylinderCylinder(curve) = intersection.definition,
              curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair spatial bounds require a certified full-branch cylinder-cylinder component."
            )
        }
        let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
            tolerance: tolerance
        )
        let scale = abs(endFraction - startFraction).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (source.first * scale).nextUp,
            second: ((source.second * scale).nextUp * scale).nextUp
        )
    }

    func cylinderSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        guard case let .cylinderCylinder(curve) = intersection.definition else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair spatial bounds require a certified cylinder-cylinder component."
            )
        }
        let lowerFraction = min(startFraction, endFraction)
        let upperFraction = max(startFraction, endFraction)
        let source = try curve.spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            tolerance: tolerance
        )
        let scale = abs(endFraction - startFraction).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (source.first * scale).nextUp,
            second: ((source.second * scale).nextUp * scale).nextUp
        )
    }

    func spatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        switch intersection.definition {
        case .cylinderCylinder:
            return try cylinderSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        case let .boundedPlaneCone(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .sphereCylinder(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .sphereCone(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .coneCylinder(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .coneCone(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .planeTorus(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let period = (2.0 * Double.pi).nextUp
            let scale = (
                abs(endFraction - startFraction).nextUp * period
            ).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .congruentTorusTorus(curve)
            where curve.sectionCurve.componentKind == .negativeFullBranch
                || curve.sectionCurve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .parallelTorusCylinder(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .generalTorusCylinder(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .generalConeTorus(curve)
            where curve.apexReduction == nil:
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .sphereTorus(curve)
            where curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch:
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .parallelTorusTorus(curve)
            where curve.componentKind == .regularClosed:
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        case let .generalTorusTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            let scale = abs(endFraction - startFraction).nextUp
            return SpatialDifferentialMagnitudeBounds(
                first: (source.first * scale).nextUp,
                second: ((source.second * scale).nextUp * scale).nextUp
            )
        // FIXME(INCOMPLETE_IMPLEMENTATION): The remaining certified analytic-pair
        // definitions do not yet expose interval-local spatial first- and
        // second-derivative magnitude bounds. Production surface-lift curve
        // intersection reaches this branch through the certificate owner, and it
        // must not report success until each definition proves trim- and
        // seam-aware bounds for transverse and tangent root isolation.
        case .planeTorus, .coneCone, .sphereCylinder, .sphereCone,
             .coneCylinder, .sphereTorus, .parallelTorusCylinder,
             .generalConeTorus, .parallelTorusTorus,
             .congruentTorusTorus:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "This analytic-pair definition lacks certified spatial differential bounds."
            )
        }
    }
}
