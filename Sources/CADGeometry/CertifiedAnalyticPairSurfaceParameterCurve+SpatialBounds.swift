import CADCore

extension CertifiedAnalyticPairSurfaceParameterCurve {
    /// Whether trimming only rescales one source-wide spatial derivative
    /// certificate. After the lift bounder converts the trimmed derivative
    /// back to the original curve parameter, every subinterval has the same
    /// bound and recomputing the source certificate cannot tighten it.
    var hasIntervalInvariantSpatialDifferentialMagnitudeBounds: Bool {
        switch intersection.definition {
        case let .cylinderCylinder(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .sphereCylinder(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case let .sphereCone(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
                || curve.componentKind == .apexReducedAngularInterval
        case let .coneCylinder(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
                || curve.componentKind == .rulingParallelLinear
        case let .coneCone(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
                || curve.componentKind == .apexReducedAngularInterval
        case let .parallelTorusCylinder(curve):
            curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch
        case .generalTorusCylinder:
            true
        case .boundedPlaneCone,
             .planeTorus,
             .congruentTorusTorus,
             .generalConeTorus,
             .sphereTorus,
             .parallelTorusTorus,
             .generalTorusTorus:
            false
        }
    }

    var hasSpatialDifferentialMagnitudeBounds: Bool {
        switch intersection.definition {
        case .cylinderCylinder, .boundedPlaneCone:
            return true
        case .sphereCylinder:
            return true
        case .sphereCone:
            return true
        case .coneCylinder:
            return true
        case .coneCone:
            return true
        case .planeTorus:
            return true
        case .congruentTorusTorus:
            return true
        case .parallelTorusCylinder:
            return true
        case .generalTorusCylinder:
            return true
        case .generalConeTorus:
            return true
        case .sphereTorus:
            return true
        case .parallelTorusTorus:
            return true
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
        return source.scaled(by: endFraction - startFraction)
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
        return source.scaled(by: endFraction - startFraction)
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
            return source.scaled(by: endFraction - startFraction)
        case let .sphereCylinder(curve):
            let source: SpatialDifferentialMagnitudeBounds
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                source = try curve
                    .fullBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .boundedAngularInterval:
                source = try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            case .negativeOpenAngularInterval,
                 .positiveOpenAngularInterval:
                source = try curve
                    .openBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(startFraction, endFraction),
                        toNormalizedFraction: max(startFraction, endFraction),
                        tolerance: tolerance
                    )
            }
            return source.scaled(by: endFraction - startFraction)
        case let .sphereCone(curve):
            let source: SpatialDifferentialMagnitudeBounds
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            case .boundedAngularInterval:
                source = try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            case .apexReducedAngularInterval:
                source = try curve
                    .apexReducedBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .negativeOpenAngularInterval,
                 .positiveOpenAngularInterval:
                source = try curve
                    .openBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            }
            return source.scaled(by: endFraction - startFraction)
        case let .coneCylinder(curve):
            let source: SpatialDifferentialMagnitudeBounds
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                source = try curve
                    .fullBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .rulingParallelLinear:
                source = try curve
                    .rulingParallelSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .boundedAngularInterval:
                source = try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            case .apexLowerNodeInterval, .apexUpperNodeInterval:
                source = try curve
                    .apexNodeSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            }
            return source.scaled(by: endFraction - startFraction)
        case let .coneCone(curve):
            let source: SpatialDifferentialMagnitudeBounds
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                source = try curve.fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            case .boundedAngularInterval:
                source = try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            case .apexReducedAngularInterval:
                source = try curve
                    .apexReducedBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            }
            return source.scaled(by: endFraction - startFraction)
        case let .planeTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(
                by: (endFraction - startFraction) * 2.0 * Double.pi
            )
        case let .congruentTorusTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        case let .parallelTorusCylinder(curve):
            let source: SpatialDifferentialMagnitudeBounds
            switch curve.componentKind {
            case .negativeFullBranch, .positiveFullBranch:
                source = try curve
                    .fullBranchSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
            case .boundedAngularInterval:
                source = try curve
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            case .negativeInternalTangencyInterval,
                 .positiveInternalTangencyInterval:
                source = try curve
                    .internalTangencySpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            startFraction,
                            endFraction
                        ),
                        toNormalizedFraction: max(
                            startFraction,
                            endFraction
                        ),
                        tolerance: tolerance
                    )
            }
            return source.scaled(by: endFraction - startFraction)
        case let .generalTorusCylinder(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        case let .generalConeTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        case let .sphereTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        case let .parallelTorusTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        case let .generalTorusTorus(curve):
            let source = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: min(startFraction, endFraction),
                toNormalizedFraction: max(startFraction, endFraction),
                tolerance: tolerance
            )
            return source.scaled(by: endFraction - startFraction)
        }
    }
}
