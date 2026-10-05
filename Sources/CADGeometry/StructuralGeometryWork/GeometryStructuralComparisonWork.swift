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
        case let .parameterImage(curve):
            try charge(2)
            try Self.charge(gain: curve.parameterGain, using: charge)
            try Self.charge(curve: curve.source, using: charge)
        case .originalConstructionChart(let image):
            try charge(2)
            switch image.chart {
            case .traversal(let traversal):
                try Self.charge(traversal: traversal, using: charge)
            case .parameterLaw(let source):
                try charge(3)
                try Self.charge(curve: source.source, using: charge)
                for value in [source.firstFraction, source.lastFraction] {
                    try charge(1)
                    try chargeArray(value.canonicalNumeratorWords.count, using: charge)
                    try chargeArray(value.canonicalDenominatorWords.count, using: charge)
                }
            }
        case .originalPolyline(let original):
            try charge(3)
            try chargeArray(original.points.count, using: charge)
            for _ in original.points { try charge(3) }
        case .originalGuideEndpointConnector(let original):
            try charge(6)
            try Self.charge(traversal: original.source, using: charge)
            try Self.charge(traversal: original.startBoundary, using: charge)
            try Self.charge(traversal: original.endBoundary, using: charge)
        case .originalGuideTraversalChain(let original):
            try charge(4)
            for traversal in original.traversals { try Self.charge(traversal: traversal, using: charge) }
            for station in original.stations {
                try charge(1)
                try chargeArray(station.canonicalNumeratorWords.count, using: charge)
                try chargeArray(station.canonicalDenominatorWords.count, using: charge)
            }
            try chargeArray(original.sourceSegmentOrdinals.count, using: charge)
        case .originalDrafted(let original):
            try charge(11)
            try Self.charge(traversal: original.generator, using: charge)
        case .originalPlaneDerivative(let original):
            try Self.charge(traversal: original.source, using: charge)
            try Self.charge(planeConstraints: original.startConstraints, using: charge)
            try Self.charge(planeConstraints: original.endConstraints, using: charge)
        case .originalEndpointConnector(let connector):
            try charge(3)
            try Self.charge(curve: .bSpline(connector.construction), using: charge)
            try Self.charge(traversal: connector.startBoundary, using: charge)
            try Self.charge(traversal: connector.endBoundary, using: charge)
        case .originalAngularTransport(let image):
            try Self.charge(curve: image.source, using: charge)
            try Self.charge(angularTransport: image.transport, using: charge)
        case let .originalAffineWord(curve):
            try Self.charge(word: curve.operationWord, using: charge)
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
            case let .originalAngularTransport(image):
                try Self.charge(surface: image.source, using: charge)
                try Self.charge(angularTransport: image.uTransport, using: charge)
                try Self.charge(angularTransport: image.vTransport, using: charge)
            case let .originalAffineWord(image):
                try Self.charge(word: image.operationWord, using: charge)
                try Self.charge(surface: image.source, using: charge)
            case let .originalImage(image):
                try charge(16)
                try Self.charge(gain: image.uParameterGain, using: charge)
                try Self.charge(gain: image.vParameterGain, using: charge)
                try Self.charge(surface: image.source, using: charge)
            case let .originalRevolution(original):
                try charge(8)
                try Self.charge(traversal: original.generator, using: charge)
            case let .originalDrafted(original):
                try charge(1)
                try Self.charge(curve: .originalDrafted(original.start), using: charge)
            case let .originalPlaneDerivative(original):
                try Self.charge(surface: .procedural(.originalBoundaryCorrected(original.construction)), using: charge)
                try Self.charge(surface: .procedural(.originalCoons(original.boundaries)), using: charge)
                try Self.charge(planeConstraints: original.startConstraints, using: charge)
                try Self.charge(planeConstraints: original.endConstraints, using: charge)
            case let .originalBoundaryCorrected(original):
                try Self.charge(surface: original.construction, using: charge)
                try Self.charge(surface: .procedural(.originalCoons(original.boundaries)), using: charge)
            case let .originalCoons(original):
                try charge(4)
                try Self.charge(traversal: original.vMinimumBoundary, using: charge)
                try Self.charge(traversal: original.vMaximumBoundary, using: charge)
                try Self.charge(traversal: original.uMinimumBoundary, using: charge)
                try Self.charge(traversal: original.uMaximumBoundary, using: charge)
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

    private static func charge(planeConstraints: [OriginalPlaneDerivativeConstraint], using charge: Charge) throws {
        try chargeArray(planeConstraints.count, using: charge)
        for constraint in planeConstraints {
            try checkCancellation(); try charge(1)
            try Self.charge(surface: constraint.surface, using: charge)
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
        case let .originalBSplineContinuation(curve):
            try charge(4)
            try Self.charge(curve: curve.original, using: charge)
        case let .projectedAnalytic(curve):
            try charge(5)
            try Self.charge(curve: curve.curve, using: charge)
            try Self.charge(surface: curve.surface, using: charge)
        case let .originalAffineWord(curve):
            try charge(2)
            try Self.charge(curve: .surfaceLift(curve.source), using: charge)
            try Self.charge(surface: .procedural(.originalAffineWord(curve.target)), using: charge)
        case let .originalImage(curve):
            try charge(2)
            try Self.charge(curve: .surfaceLift(curve.source), using: charge)
            try Self.charge(surface: .procedural(.originalImage(curve.targetImage)), using: charge)
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

    private static func charge(word: OriginalAffineOperationWord, using charge: Charge) throws {
        try chargeArray(word.factors.count, using: charge)
        for factor in word.factors {
            try checkCancellation(); try charge(1)
            switch factor {
            case .forward, .inverse: try charge(12)
            case .rationalForward(let source), .rationalInverse(let source):
                try chargeArray(source.coefficients.count, using: charge)
                for coefficient in source.coefficients {
                    try checkCancellation(); try charge(1)
                    try chargeArray(coefficient.canonicalNumeratorWords.count, using: charge)
                    try chargeArray(coefficient.canonicalDenominatorWords.count, using: charge)
                }
            case .normalizedForward(let source), .normalizedInverse(let source):
                try charge(14)
                for coefficient in [source.lengthGain, source.linearGain] {
                    try chargeArray(coefficient.canonicalNumeratorWords.count, using: charge)
                    try chargeArray(coefficient.canonicalDenominatorWords.count, using: charge)
                }
                try chargeArray(source.adjustments.count, using: charge)
                for _ in source.adjustments { try checkCancellation(); try charge(4) }
            }
        }
    }

    package static func charge(traversal: OriginalCurveRootSpan3D, using charge: Charge) throws {
        try checkCancellation(); try charge(3)
        try Self.charge(curve: traversal.source, using: charge)
        try Self.charge(endpoint: traversal.start, using: charge)
        try Self.charge(endpoint: traversal.end, using: charge)
    }

    private static func charge(endpoint: OriginalCurveRootEndpoint, using charge: Charge) throws {
        try checkCancellation(); try charge(1)
        switch endpoint {
        case .authored: try charge(1)
        case .algebraic(let boundary):
            try charge(9)
            try Self.charge(curve: .bSpline(boundary.source), using: charge)
            for value in [boundary.isolationLower, boundary.isolationUpper] {
                try charge(1)
                try chargeArray(value.canonicalNumeratorWords.count, using: charge)
                try chargeArray(value.canonicalDenominatorWords.count, using: charge)
            }
            switch boundary.constraint {
            case .axis, .plane: try charge(6)
            case .parameterPolynomial(let polynomial):
                try chargeArray(polynomial.coefficients.count, using: charge)
                for (power, value) in polynomial.coefficients {
                    _ = power
                    try charge(2)
                    try chargeArray(value.canonicalNumeratorWords.count, using: charge)
                    try chargeArray(value.canonicalDenominatorWords.count, using: charge)
                }
            }
        }
    }

    private static func charge(gain: OriginalParameterGain, using charge: Charge) throws {
        try checkCancellation(); try charge(1)
        switch gain {
        case .binary: try charge(1)
        case .ratio: try charge(2)
        case .product(let value):
            try chargeArray(value.factors.count, using: charge)
            for factor in value.factors { try Self.charge(gain: factor, using: charge) }
        case .difference(let value):
            try charge(4)
            try Self.charge(gain: value.periodicTranslation.parameterGain, using: charge)
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
    private static func charge(angularTransport: OriginalAngularParameterTransport, using charge: Charge) throws {
        try charge(1)
        func coefficient(_ value: ExactRationalCoefficient) throws {
            try chargeArray(value.canonicalNumeratorWords.count, using: charge)
            try chargeArray(value.canonicalDenominatorWords.count, using: charge)
        }
        switch angularTransport {
        case .intrinsic: break
        case .physicalRadians(let gain, let offset): try coefficient(gain); try coefficient(offset)
        case .physicalRadianArc(let start, let end, _): try coefficient(start); try coefficient(end); try charge(1)
        }
    }

}
