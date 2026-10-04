import CADCore

/// Accounts for the original stored payload that structural geometry consumers
/// must inspect before comparing or hashing it.
package struct GeometryStructuralComparisonWork {
    package typealias Charge = (Int) throws -> Void

    package static func charge(
        curve: Curve3D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(1)
        switch curve {
        case .line:
            try charge(4)
        case .circle:
            try charge(4)
        case let .analytic(curve):
            try Self.charge(analyticCurve: curve, using: charge)
        case let .bSpline(curve):
            try Self.charge(curve: curve, using: charge)
        case let .implicit(curve):
            try Self.charge(implicitCurve: curve, using: charge)
        case let .surfaceLift(curve):
            try charge(2)
            try Self.charge(surface: curve.surface, using: charge)
            try Self.charge(parameterCurve: curve.parameterCurve, using: charge)
        case let .certifiedIntersection(curve):
            try charge(1)
            switch curve {
            case .coneTorus(let curve):
                try Self.charge(surface: curve.coneSurface, using: charge)
                try Self.charge(surface: curve.torusSurface, using: charge)
                try charge(8)
                if curve.apexReduction != nil { try charge(1) }
                try curve.chargeStructuralComparisonWork(using: charge)
            case .parallelTorusTorus(let curve):
                try Self.charge(surface: curve.primarySurface, using: charge)
                try Self.charge(surface: curve.secondarySurface, using: charge)
                try charge(8)
                // The private certificate has exactly componentKind and
                // processedCellCount as equality payload.
                try charge(2)
            case let .sphereCone(curve):
                try Self.charge(curve: curve, using: charge)
            case let .coneCone(curve):
                try Self.charge(curve: curve, using: charge)
            case let .coneCylinder(curve):
                try Self.charge(curve: curve, using: charge)
            }
        case let .rigidImage(curve):
            try charge(2)
            try Self.charge(curve: curve.source, using: charge)
        case let .affineImage(curve):
            try charge(2)
            try Self.charge(curve: curve.source, using: charge)
        }
    }

    package static func charge(
        surface: Surface3D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(1)
        switch surface {
        case .plane:
            try charge(4)
        case .cylinder:
            try charge(5)
        case let .analytic(surface):
            try charge(1)
            switch surface {
            case .plane:
                try charge(6)
            case .cylinder:
                try charge(5)
            case .cone:
                try charge(3)
            case .sphere:
                try charge(2)
            case .torus:
                try charge(4)
            }
        case let .bSpline(surface):
            try Self.charge(surface: surface, using: charge)
        case let .procedural(surface):
            try charge(1)
            switch surface {
            case let .offset(surface):
                try charge(1)
                try Self.charge(surface: surface.source, using: charge)
                try charge(1)
            case let .ruled(surface):
                try charge(1)
                try Self.charge(curve: surface.startBoundary, using: charge)
                try Self.charge(curve: surface.endBoundary, using: charge)
                try charge(1)
            case let .rollingBall(surface):
                try charge(1)
                try Self.charge(curve: surface.centerSpine, using: charge)
                try Self.charge(curve: surface.firstContact, using: charge)
                try Self.charge(curve: surface.secondContact, using: charge)
                try charge(2)
            }
        }
    }

    package static func charge(
        parameterCurve: SurfaceParameterCurve,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(1)
        switch parameterCurve {
        case .affine:
            try charge(6)
        case .constantU, .constantV:
            try charge(3)
        case .harmonic:
            try charge(8)
        case .sphericalGreatCircle:
            try charge(6)
        case let .polyline(points):
            try chargeArray(points.count, using: charge)
            for _ in points {
                try checkCancellation()
                try charge(2)
            }
        case let .bSpline(curve):
            try Self.charge(curve: curve, using: charge)
        case let .certifiedImplicit(curve):
            try Self.charge(implicitCurve: curve.intersection, using: charge)
            try charge(3)
        case let .certifiedAnalyticImplicit(curve):
            try Self.charge(analyticIntersection: curve.intersection, using: charge)
            try charge(2)
        case let .certifiedAnalyticPair(curve):
            try Self.charge(analyticIntersection: curve.intersection, using: charge)
            try charge(3)
        case let .projectedAnalytic(curve):
            try charge(5)
            try Self.charge(curve: curve.curve, using: charge)
            try Self.charge(surface: curve.surface, using: charge)
        case let .rigidImage(curve):
            try charge(5)
            try Self.charge(surface: curve.source.surface, using: charge)
            try Self.charge(parameterCurve: curve.source.parameterCurve, using: charge)
            try Self.charge(surface: curve.targetSurface, using: charge)
        case let .offsetSurfaceImage(curve):
            try charge(2)
            try Self.charge(parameterCurve: curve.source, using: charge)
            try Self.charge(surface: curve.offset.source, using: charge)
            try charge(1)
        case let .periodicTranslation(base, _, _):
            try charge(2)
            try Self.charge(parameterCurve: base, using: charge)
        }
    }

    private static func charge(
        implicitCurve curve: CertifiedImplicitIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.firstSurface, using: charge)
        try Self.charge(surface: curve.secondSurface, using: charge)
        try chargeArray(curve.cells.count, using: charge)
        for cell in curve.cells {
            try checkCancellation()
            // parameterBox (four intervals), freeParameter, direction, and
            // three parameter pairs (two scalar values each).
            try charge(12)
        }
        try charge(2) // isClosed and certificationTolerance
    }

    private static func charge(
        analyticIntersection curve: CertifiedAnalyticBSplineIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(implicitCurve: curve.implicitCurve, using: charge)
        try Self.charge(surface: curve.analyticSurface, using: charge)
        try Self.charge(surface: .bSpline(curve.boundedSurface), using: charge)
        try charge(2) // analyticIsFirst and periodicSeamOffset
    }

    private static func charge(
        analyticIntersection curve: CertifiedAnalyticAnalyticIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.firstSurface, using: charge)
        try Self.charge(surface: curve.secondSurface, using: charge)
        try Self.charge(definition: curve.definition, using: charge)
    }

    private static func charge(
        definition: CertifiedAnalyticAnalyticIntersectionCurve.Definition,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(1) // the synthesized enum discriminator
        switch definition {
        case let .planeTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .coneCone(curve):
            try Self.charge(curve: curve, using: charge)
        case let .cylinderCylinder(curve):
            try Self.charge(curve: curve, using: charge)
        case let .sphereCylinder(curve):
            try Self.charge(curve: curve, using: charge)
        case let .sphereCone(curve):
            try Self.charge(curve: curve, using: charge)
        case let .coneCylinder(curve):
            try Self.charge(curve: curve, using: charge)
        case let .sphereTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .parallelTorusCylinder(curve):
            try Self.charge(curve: curve, using: charge)
        case let .generalTorusCylinder(curve):
            try Self.charge(curve: curve, using: charge)
        case let .generalConeTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .parallelTorusTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .congruentTorusTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .generalTorusTorus(curve):
            try Self.charge(curve: curve, using: charge)
        case let .boundedPlaneCone(curve):
            try Self.charge(curve: curve, using: charge)
        }
    }

    private static func charge(
        curve: CertifiedPlaneTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.planeSurface, using: charge)
        try Self.charge(surface: curve.torusSurface, using: charge)
        try charge(5) // component, two angles, tolerance, residual bound
    }

    private static func charge(
        curve: CertifiedSphereConeIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: charge)
        try Self.charge(surface: curve.coneSurface, using: charge)
        try charge(5) // component, two angles, tolerance, residual bound
    }

    private static func charge(
        curve: CertifiedConeConeIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.referenceSurface, using: charge)
        try Self.charge(surface: curve.parameterizedSurface, using: charge)
        try charge(5) // component, two angles, tolerance, residual bound
    }

    private static func charge(
        curve: CertifiedConeCylinderIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.coneSurface, using: charge)
        try Self.charge(surface: curve.cylinderSurface, using: charge)
        try charge(5) // component, two angles, tolerance, residual bound
    }

    private static func charge(
        curve: CertifiedCylinderCylinderIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.referenceSurface, using: charge)
        try Self.charge(surface: curve.parameterizedSurface, using: charge)
        try charge(5)
    }

    private static func charge(
        curve: CertifiedSphereCylinderIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: charge)
        try Self.charge(surface: curve.cylinderSurface, using: charge)
        try charge(5)
    }

    private static func charge(
        curve: CertifiedSphereTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: charge)
        try Self.charge(surface: curve.torusSurface, using: charge)
        try charge(5)
    }

    private static func charge(
        curve: CertifiedParallelTorusCylinderIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.torusSurface, using: charge)
        try Self.charge(surface: curve.cylinderSurface, using: charge)
        try charge(5)
    }

    private static func charge(
        curve: CertifiedGeneralTorusCylinderIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.torusSurface, using: charge)
        try Self.charge(surface: curve.cylinderSurface, using: charge)
        try charge(6)
        try curve.chargeStructuralComparisonWork(using: charge)
    }

    private static func charge(
        curve: CertifiedGeneralConeTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.coneSurface, using: charge)
        try Self.charge(surface: curve.torusSurface, using: charge)
        try charge(6) // branch, count, depth, cell count, tolerance, residual
        if curve.apexReduction != nil { try charge(1) }
        try curve.chargeStructuralComparisonWork(using: charge)
    }

    private static func charge(
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.primarySurface, using: charge)
        try Self.charge(surface: curve.secondarySurface, using: charge)
        try charge(8)
        try charge(2) // fixed certificate payload
    }

    private static func charge(
        curve: CertifiedCongruentTorusTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.primarySurface, using: charge)
        try Self.charge(surface: curve.secondarySurface, using: charge)
        try Self.charge(curve: curve.sectionCurve, using: charge)
        try charge(6)
    }

    private static func charge(
        curve: CertifiedGeneralTorusTorusIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.parameterizedSurface, using: charge)
        try Self.charge(surface: curve.referenceSurface, using: charge)
        try charge(7)
        try curve.chargeStructuralComparisonWork(using: charge)
    }

    private static func charge(
        curve: CertifiedBoundedPlaneConeIntersectionCurve,
        using charge: Charge
    ) throws {
        try Self.charge(surface: curve.planeSurface, using: charge)
        try Self.charge(surface: curve.coneSurface, using: charge)
        try Self.charge(analyticCurve: curve.analyticCurve, using: charge)
        try charge(5)
    }

    private static func charge(
        analyticCurve curve: AnalyticCurve3D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(1)
        switch curve {
        case .line:
            try charge(4)
        case .circle:
            try charge(4)
        case .arc:
            try charge(5)
        case .ellipse:
            try charge(5)
        case .hyperbola:
            try charge(5)
        case .parabola:
            try charge(4)
        case let .planeTorus(curve):
            try Self.charge(curve: curve, using: charge)
        }
    }

    private static func charge(
        curve: BSplineCurve3D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(6)
        try chargeArray(curve.knots.count, using: charge)
        try chargeArray(curve.controlPoints.count, using: charge)
        try chargeArray(curve.weights.count, using: charge)
        try charge(curve.knots.count)
        for _ in curve.controlPoints {
            try checkCancellation()
            try charge(3)
        }
        try charge(curve.weights.count)
        try charge(2)
    }

    private static func charge(
        curve: BSplineCurve2D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(6)
        try chargeArray(curve.knots.count, using: charge)
        try chargeArray(curve.controlPoints.count, using: charge)
        try chargeArray(curve.weights.count, using: charge)
        try charge(curve.knots.count)
        for _ in curve.controlPoints {
            try checkCancellation()
            try charge(2)
        }
        try charge(curve.weights.count)
        try charge(2)
    }

    private static func charge(
        surface: BSplineSurface3D,
        using charge: Charge
    ) throws {
        try checkCancellation()
        try charge(8)
        try chargeArray(surface.uKnots.count, using: charge)
        try chargeArray(surface.vKnots.count, using: charge)
        try chargeArray(surface.controlPoints.count, using: charge)
        try chargeArray(surface.weights.count, using: charge)
        try charge(surface.uKnots.count)
        try charge(surface.vKnots.count)
        for row in surface.controlPoints {
            try checkCancellation()
            try chargeArray(row.count, using: charge)
            for _ in row {
                try checkCancellation()
                try charge(3)
            }
        }
        for row in surface.weights {
            try checkCancellation()
            try chargeArray(row.count, using: charge)
            try charge(row.count)
        }
        try charge(4)
    }

    private static func chargeArray(_ count: Int, using charge: Charge) throws {
        guard count >= 0 else { throw GeometryError.invalidDistance(Double(count)) }
        try checkCancellation()
        try charge(count)
    }

    private static func checkCancellation() throws {
        try Task.checkCancellation()
    }
}
