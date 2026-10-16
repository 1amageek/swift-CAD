import CADCore

/// Accounts for the original stored payload that structural geometry consumers
/// must inspect before comparing or hashing it.
package struct GeometryStructuralComparisonWork {

    package static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: Curve3D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(1)
        switch curve {
        case .line:
            try execution.consumeWork(4)
        case .circle:
            try execution.consumeWork(4)
        case let .analytic(curve):
            try Self.charge(analyticCurve: curve, using: &execution)
        case let .bSpline(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .implicit(curve):
            try Self.charge(implicitCurve: curve, using: &execution)
        case let .surfaceLift(curve):
            try execution.consumeWork(2)
            try Self.charge(surface: curve.surface, using: &execution)
            try Self.charge(parameterCurve: curve.parameterCurve, using: &execution)
        case let .certifiedIntersection(curve):
            try execution.consumeWork(1)
            switch curve {
            case .coneTorus(let curve):
                try Self.charge(surface: curve.coneSurface, using: &execution)
                try Self.charge(surface: curve.torusSurface, using: &execution)
                try execution.consumeWork(8)
                if curve.apexReduction != nil { try execution.consumeWork(1) }
                try curve.chargeStructuralComparisonWork(using: &execution)
            case .parallelTorusTorus(let curve):
                try Self.charge(surface: curve.primarySurface, using: &execution)
                try Self.charge(surface: curve.secondarySurface, using: &execution)
                try execution.consumeWork(8)
                // The private certificate has exactly componentKind and
                // processedCellCount as equality payload.
                try execution.consumeWork(2)
            case let .sphereCone(curve):
                try Self.charge(curve: curve, using: &execution)
            case let .coneCone(curve):
                try Self.charge(curve: curve, using: &execution)
            case let .coneCylinder(curve):
                try Self.charge(curve: curve, using: &execution)
            }
        case let .rigidImage(curve):
            try execution.consumeWork(2)
            try Self.charge(curve: curve.source, using: &execution)
        case let .parameterImage(curve):
            try execution.consumeWork(2)
            try Self.charge(gain: curve.parameterGain, using: &execution)
            try Self.charge(curve: curve.source, using: &execution)
        case .originalConstructionChart(let image):
            try execution.consumeWork(2)
            switch image.chart {
            case .traversal(let traversal):
                try Self.charge(traversal: traversal, using: &execution)
            case .parameterLaw(let source):
                try execution.consumeWork(3)
                try Self.charge(curve: source.source, using: &execution)
                for value in [source.firstFraction, source.lastFraction] {
                    try execution.consumeWork(1)
                    try chargeArray(value.canonicalNumeratorWords.count, using: &execution)
                    try chargeArray(value.canonicalDenominatorWords.count, using: &execution)
                }
            }
        case .originalPolyline(let original):
            try execution.consumeWork(3)
            try chargeArray(original.points.count, using: &execution)
            for _ in original.points { try execution.consumeWork(3) }
        case .originalGuideEndpointConnector(let original):
            try execution.consumeWork(6)
            try Self.charge(traversal: original.source, using: &execution)
            try Self.charge(traversal: original.startBoundary, using: &execution)
            try Self.charge(traversal: original.endBoundary, using: &execution)
        case .originalGuideTraversalChain(let original):
            try execution.consumeWork(4)
            for traversal in original.traversals { try Self.charge(traversal: traversal, using: &execution) }
            for station in original.stations {
                try execution.consumeWork(1)
                try chargeArray(station.canonicalNumeratorWords.count, using: &execution)
                try chargeArray(station.canonicalDenominatorWords.count, using: &execution)
            }
            try chargeArray(original.sourceSegmentOrdinals.count, using: &execution)
        case .originalDrafted(let original):
            try execution.consumeWork(11)
            try Self.charge(traversal: original.generator, using: &execution)
        case .originalPlaneDerivative(let original):
            try Self.charge(traversal: original.source, using: &execution)
            try Self.charge(planeConstraints: original.startConstraints, using: &execution)
            try Self.charge(planeConstraints: original.endConstraints, using: &execution)
        case .originalEndpointConnector(let connector):
            try execution.consumeWork(3)
            try Self.charge(curve: .bSpline(connector.construction), using: &execution)
            try Self.charge(traversal: connector.startBoundary, using: &execution)
            try Self.charge(traversal: connector.endBoundary, using: &execution)
        case .originalAngularTransport(let image):
            try Self.charge(curve: image.source, using: &execution)
            try Self.charge(angularTransport: image.transport, using: &execution)
        case let .originalAffineWord(curve):
            try Self.charge(word: curve.operationWord, using: &execution)
            try Self.charge(curve: curve.source, using: &execution)
        case let .affineImage(curve):
            try execution.consumeWork(2)
            try Self.charge(curve: curve.source, using: &execution)
        }
    }

    @inline(never)
    package static func charge<A: ExactScalarAdmission & ~Copyable>(
        surface: Surface3D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(1)
        if case .bSpline(let native) = surface {
            try Self.charge(surface: native, using: &execution)
            return
        }
        try chargeNonNativeSurfacePayload(surface: surface, using: &execution)
    }

    @inline(never)
    private static func chargeNonNativeSurfacePayload<A: ExactScalarAdmission & ~Copyable>(
        surface: Surface3D,
        using execution: inout A
    ) throws {
        switch surface {
        case .plane:
            try execution.consumeWork(4)
        case .cylinder:
            try execution.consumeWork(5)
        case let .analytic(surface):
            try execution.consumeWork(1)
            switch surface {
            case .plane:
                try execution.consumeWork(6)
            case .cylinder:
                try execution.consumeWork(5)
            case .cone:
                try execution.consumeWork(3)
            case .sphere:
                try execution.consumeWork(2)
            case .torus:
                try execution.consumeWork(4)
            }
        case let .bSpline(surface):
            try Self.charge(surface: surface, using: &execution)
        case let .procedural(surface):
            try execution.consumeWork(1)
            switch surface {
            case let .originalAngularTransport(image):
                try Self.charge(surface: image.source, using: &execution)
                try Self.charge(angularTransport: image.uTransport, using: &execution)
                try Self.charge(angularTransport: image.vTransport, using: &execution)
            case let .originalAffineWord(image):
                try Self.charge(word: image.operationWord, using: &execution)
                try Self.charge(surface: image.source, using: &execution)
            case let .originalImage(image):
                try execution.consumeWork(16)
                try Self.charge(gain: image.uParameterGain, using: &execution)
                try Self.charge(gain: image.vParameterGain, using: &execution)
                try Self.charge(surface: image.source, using: &execution)
            case let .originalRevolution(original):
                try execution.consumeWork(8)
                try Self.charge(traversal: original.generator, using: &execution)
            case let .originalDrafted(original):
                try execution.consumeWork(1)
                try Self.charge(curve: .originalDrafted(original.start), using: &execution)
            case let .originalPlaneDerivative(original):
                try Self.charge(surface: .procedural(.originalBoundaryCorrected(original.construction)), using: &execution)
                try Self.charge(surface: .procedural(.originalCoons(original.boundaries)), using: &execution)
                try Self.charge(planeConstraints: original.startConstraints, using: &execution)
                try Self.charge(planeConstraints: original.endConstraints, using: &execution)
            case let .originalBoundaryCorrected(original):
                try Self.charge(surface: original.construction, using: &execution)
                try Self.charge(surface: .procedural(.originalCoons(original.boundaries)), using: &execution)
            case let .originalCoons(original):
                try execution.consumeWork(4)
                try Self.charge(traversal: original.vMinimumBoundary, using: &execution)
                try Self.charge(traversal: original.vMaximumBoundary, using: &execution)
                try Self.charge(traversal: original.uMinimumBoundary, using: &execution)
                try Self.charge(traversal: original.uMaximumBoundary, using: &execution)
            case let .offset(surface):
                try execution.consumeWork(1)
                try Self.charge(surface: surface.source, using: &execution)
                try execution.consumeWork(1)
            case let .ruled(surface):
                try execution.consumeWork(1)
                try Self.charge(curve: surface.startBoundary, using: &execution)
                try Self.charge(curve: surface.endBoundary, using: &execution)
                try execution.consumeWork(1)
            case let .rollingBall(surface):
                try execution.consumeWork(1)
                try Self.charge(curve: surface.centerSpine, using: &execution)
                try Self.charge(curve: surface.firstContact, using: &execution)
                try Self.charge(curve: surface.secondContact, using: &execution)
                try execution.consumeWork(2)
            }
        }
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(planeConstraints: [OriginalPlaneDerivativeConstraint], using execution: inout A) throws {
        try chargeArray(planeConstraints.count, using: &execution)
        for constraint in planeConstraints {
            try checkCancellation(); try execution.consumeWork(1)
            try Self.charge(surface: constraint.surface, using: &execution)
        }
    }

    package static func charge<A: ExactScalarAdmission & ~Copyable>(
        parameterCurve: SurfaceParameterCurve,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(1)
        switch parameterCurve {
        case .affine:
            try execution.consumeWork(6)
        case .constantU, .constantV:
            try execution.consumeWork(3)
        case .harmonic:
            try execution.consumeWork(8)
        case .sphericalGreatCircle:
            try execution.consumeWork(6)
        case let .polyline(points):
            try chargeArray(points.count, using: &execution)
            for _ in points {
                try checkCancellation()
                try execution.consumeWork(2)
            }
        case let .bSpline(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .certifiedImplicit(curve):
            try Self.charge(implicitCurve: curve.intersection, using: &execution)
            try execution.consumeWork(3)
        case let .certifiedAnalyticImplicit(curve):
            try Self.charge(analyticIntersection: curve.intersection, using: &execution)
            try execution.consumeWork(2)
        case let .certifiedAnalyticPair(curve):
            try Self.charge(analyticIntersection: curve.intersection, using: &execution)
            try execution.consumeWork(3)
        case let .originalBSplineContinuation(curve):
            try execution.consumeWork(4)
            try Self.charge(curve: curve.original, using: &execution)
        case let .projectedAnalytic(curve):
            try execution.consumeWork(5)
            try Self.charge(curve: curve.curve, using: &execution)
            try Self.charge(surface: curve.surface, using: &execution)
        case let .originalAffineWord(curve):
            try execution.consumeWork(2)
            try Self.charge(curve: .surfaceLift(curve.source), using: &execution)
            try Self.charge(surface: .procedural(.originalAffineWord(curve.target)), using: &execution)
        case let .originalImage(curve):
            try execution.consumeWork(2)
            try Self.charge(curve: .surfaceLift(curve.source), using: &execution)
            try Self.charge(surface: .procedural(.originalImage(curve.targetImage)), using: &execution)
        case let .rigidImage(curve):
            try execution.consumeWork(5)
            try Self.charge(surface: curve.source.surface, using: &execution)
            try Self.charge(parameterCurve: curve.source.parameterCurve, using: &execution)
            try Self.charge(surface: curve.targetSurface, using: &execution)
        case let .offsetSurfaceImage(curve):
            try execution.consumeWork(2)
            try Self.charge(parameterCurve: curve.source, using: &execution)
            try Self.charge(surface: curve.offset.source, using: &execution)
            try execution.consumeWork(1)
        case let .periodicTranslation(base, _, _):
            try execution.consumeWork(2)
            try Self.charge(parameterCurve: base, using: &execution)
        }
    }

    package static func charge<A: ExactScalarAdmission & ~Copyable>(word: OriginalAffineOperationWord, using execution: inout A) throws {
        try chargeArray(word.factors.count, using: &execution)
        for factor in word.factors {
            try checkCancellation(); try execution.consumeWork(1)
            switch factor {
            case .forward, .inverse: try execution.consumeWork(12)
            case .rationalForward(let source), .rationalInverse(let source):
                try chargeArray(source.coefficients.count, using: &execution)
                for coefficient in source.coefficients {
                    try checkCancellation(); try execution.consumeWork(1)
                    try chargeArray(coefficient.canonicalNumeratorWords.count, using: &execution)
                    try chargeArray(coefficient.canonicalDenominatorWords.count, using: &execution)
                }
            case .normalizedForward(let source), .normalizedInverse(let source):
                try execution.consumeWork(14)
                for coefficient in [source.lengthGain, source.linearGain] {
                    try chargeArray(coefficient.canonicalNumeratorWords.count, using: &execution)
                    try chargeArray(coefficient.canonicalDenominatorWords.count, using: &execution)
                }
                try chargeArray(source.adjustments.count, using: &execution)
                for _ in source.adjustments { try checkCancellation(); try execution.consumeWork(4) }
            }
        }
    }

    package static func charge<A: ExactScalarAdmission & ~Copyable>(traversal: OriginalCurveRootSpan3D, using execution: inout A) throws {
        try checkCancellation(); try execution.consumeWork(3)
        try Self.charge(curve: traversal.source, using: &execution)
        try Self.charge(endpoint: traversal.start, using: &execution)
        try Self.charge(endpoint: traversal.end, using: &execution)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(endpoint: OriginalCurveRootEndpoint, using execution: inout A) throws {
        try checkCancellation(); try execution.consumeWork(1)
        switch endpoint {
        case .authored: try execution.consumeWork(1)
        case .algebraic(let boundary):
            try execution.consumeWork(9)
            try Self.charge(curve: .bSpline(boundary.source), using: &execution)
            for value in [boundary.isolationLower, boundary.isolationUpper] {
                try execution.consumeWork(1)
                try chargeArray(value.canonicalNumeratorWords.count, using: &execution)
                try chargeArray(value.canonicalDenominatorWords.count, using: &execution)
            }
            switch boundary.constraint {
            case .axis, .plane: try execution.consumeWork(6)
            case .parameterPolynomial(let polynomial):
                try chargeArray(polynomial.coefficients.count, using: &execution)
                for (power, value) in polynomial.coefficients {
                    _ = power
                    try execution.consumeWork(2)
                    try chargeArray(value.canonicalNumeratorWords.count, using: &execution)
                    try chargeArray(value.canonicalDenominatorWords.count, using: &execution)
                }
            }
        }
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(gain: OriginalParameterGain, using execution: inout A) throws {
        try checkCancellation(); try execution.consumeWork(1)
        switch gain {
        case .binary: try execution.consumeWork(1)
        case .ratio: try execution.consumeWork(2)
        case .product(let value):
            try chargeArray(value.factors.count, using: &execution)
            for factor in value.factors { try Self.charge(gain: factor, using: &execution) }
        case .difference(let value):
            try execution.consumeWork(4)
            try Self.charge(gain: value.periodicTranslation.parameterGain, using: &execution)
        }
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        implicitCurve curve: CertifiedImplicitIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.firstSurface, using: &execution)
        try Self.charge(surface: curve.secondSurface, using: &execution)
        try chargeArray(curve.cells.count, using: &execution)
        for cell in curve.cells {
            try checkCancellation()
            // parameterBox (four intervals), freeParameter, direction, and
            // three parameter pairs (two scalar values each).
            try execution.consumeWork(12)
        }
        try execution.consumeWork(2) // isClosed and certificationTolerance
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        analyticIntersection curve: CertifiedAnalyticBSplineIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(implicitCurve: curve.implicitCurve, using: &execution)
        try Self.charge(surface: curve.analyticSurface, using: &execution)
        try Self.charge(surface: .bSpline(curve.boundedSurface), using: &execution)
        try execution.consumeWork(2) // analyticIsFirst and periodicSeamOffset
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        analyticIntersection curve: CertifiedAnalyticAnalyticIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.firstSurface, using: &execution)
        try Self.charge(surface: curve.secondSurface, using: &execution)
        try Self.charge(definition: curve.definition, using: &execution)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        definition: CertifiedAnalyticAnalyticIntersectionCurve.Definition,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(1) // the synthesized enum discriminator
        switch definition {
        case let .planeTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .coneCone(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .cylinderCylinder(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .sphereCylinder(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .sphereCone(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .coneCylinder(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .sphereTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .parallelTorusCylinder(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .generalTorusCylinder(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .generalConeTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .parallelTorusTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .congruentTorusTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .generalTorusTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        case let .boundedPlaneCone(curve):
            try Self.charge(curve: curve, using: &execution)
        }
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedPlaneTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.planeSurface, using: &execution)
        try Self.charge(surface: curve.torusSurface, using: &execution)
        try execution.consumeWork(5) // component, two angles, tolerance, residual bound
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedSphereConeIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: &execution)
        try Self.charge(surface: curve.coneSurface, using: &execution)
        try execution.consumeWork(5) // component, two angles, tolerance, residual bound
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedConeConeIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.referenceSurface, using: &execution)
        try Self.charge(surface: curve.parameterizedSurface, using: &execution)
        try execution.consumeWork(5) // component, two angles, tolerance, residual bound
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedConeCylinderIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.coneSurface, using: &execution)
        try Self.charge(surface: curve.cylinderSurface, using: &execution)
        try execution.consumeWork(5) // component, two angles, tolerance, residual bound
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedCylinderCylinderIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.referenceSurface, using: &execution)
        try Self.charge(surface: curve.parameterizedSurface, using: &execution)
        try execution.consumeWork(5)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedSphereCylinderIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: &execution)
        try Self.charge(surface: curve.cylinderSurface, using: &execution)
        try execution.consumeWork(5)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedSphereTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.sphereSurface, using: &execution)
        try Self.charge(surface: curve.torusSurface, using: &execution)
        try execution.consumeWork(5)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedParallelTorusCylinderIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.torusSurface, using: &execution)
        try Self.charge(surface: curve.cylinderSurface, using: &execution)
        try execution.consumeWork(5)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedGeneralTorusCylinderIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.torusSurface, using: &execution)
        try Self.charge(surface: curve.cylinderSurface, using: &execution)
        try execution.consumeWork(6)
        try curve.chargeStructuralComparisonWork(using: &execution)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedGeneralConeTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.coneSurface, using: &execution)
        try Self.charge(surface: curve.torusSurface, using: &execution)
        try execution.consumeWork(6) // branch, count, depth, cell count, tolerance, residual
        if curve.apexReduction != nil { try execution.consumeWork(1) }
        try curve.chargeStructuralComparisonWork(using: &execution)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.primarySurface, using: &execution)
        try Self.charge(surface: curve.secondarySurface, using: &execution)
        try execution.consumeWork(8)
        try execution.consumeWork(2) // fixed certificate payload
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedCongruentTorusTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.primarySurface, using: &execution)
        try Self.charge(surface: curve.secondarySurface, using: &execution)
        try Self.charge(curve: curve.sectionCurve, using: &execution)
        try execution.consumeWork(6)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedGeneralTorusTorusIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.parameterizedSurface, using: &execution)
        try Self.charge(surface: curve.referenceSurface, using: &execution)
        try execution.consumeWork(7)
        try curve.chargeStructuralComparisonWork(using: &execution)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: CertifiedBoundedPlaneConeIntersectionCurve,
        using execution: inout A
    ) throws {
        try Self.charge(surface: curve.planeSurface, using: &execution)
        try Self.charge(surface: curve.coneSurface, using: &execution)
        try Self.charge(analyticCurve: curve.analyticCurve, using: &execution)
        try execution.consumeWork(5)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        analyticCurve curve: AnalyticCurve3D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(1)
        switch curve {
        case .line:
            try execution.consumeWork(4)
        case .circle:
            try execution.consumeWork(4)
        case .arc:
            try execution.consumeWork(5)
        case .ellipse:
            try execution.consumeWork(5)
        case .hyperbola:
            try execution.consumeWork(5)
        case .parabola:
            try execution.consumeWork(4)
        case let .planeTorus(curve):
            try Self.charge(curve: curve, using: &execution)
        }
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(6)
        try chargeArray(curve.knots.count, using: &execution)
        try chargeArray(curve.controlPoints.count, using: &execution)
        try chargeArray(curve.weights.count, using: &execution)
        try execution.consumeWork(curve.knots.count)
        for _ in curve.controlPoints {
            try checkCancellation()
            try execution.consumeWork(3)
        }
        try execution.consumeWork(curve.weights.count)
        try execution.consumeWork(2)
    }

    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve2D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(6)
        try chargeArray(curve.knots.count, using: &execution)
        try chargeArray(curve.controlPoints.count, using: &execution)
        try chargeArray(curve.weights.count, using: &execution)
        try execution.consumeWork(curve.knots.count)
        for _ in curve.controlPoints {
            try checkCancellation()
            try execution.consumeWork(2)
        }
        try execution.consumeWork(curve.weights.count)
        try execution.consumeWork(2)
    }

    @inline(never)
    private static func charge<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        using execution: inout A
    ) throws {
        try checkCancellation()
        try execution.consumeWork(8)
        try chargeArray(surface.uKnots.count, using: &execution)
        try chargeArray(surface.vKnots.count, using: &execution)
        try chargeArray(surface.controlPoints.count, using: &execution)
        try chargeArray(surface.weights.count, using: &execution)
        try execution.consumeWork(surface.uKnots.count)
        try execution.consumeWork(surface.vKnots.count)
        for row in surface.controlPoints {
            try checkCancellation()
            try chargeArray(row.count, using: &execution)
            for _ in row {
                try checkCancellation()
                try execution.consumeWork(3)
            }
        }
        for row in surface.weights {
            try checkCancellation()
            try chargeArray(row.count, using: &execution)
            try execution.consumeWork(row.count)
        }
        try execution.consumeWork(4)
    }

    private static func chargeArray<A: ExactScalarAdmission & ~Copyable>(_ count: Int, using execution: inout A) throws {
        guard count >= 0 else { throw GeometryError.invalidDistance(Double(count)) }
        try checkCancellation()
        try execution.consumeWork(count)
    }

    private static func checkCancellation() throws {
        try CurrentTaskCancellationChecker().checkCancellation()
    }
    private static func charge<A: ExactScalarAdmission & ~Copyable>(angularTransport: OriginalAngularParameterTransport, using execution: inout A) throws {
        try execution.consumeWork(1)
        func coefficient(_ value: ExactRationalCoefficient) throws {
            try chargeArray(value.canonicalNumeratorWords.count, using: &execution)
            try chargeArray(value.canonicalDenominatorWords.count, using: &execution)
        }
        switch angularTransport {
        case .intrinsic: break
        case .physicalRadians(let gain, let offset): try coefficient(gain); try coefficient(offset)
        case .physicalRadianArc(let start, let end, _): try coefficient(start); try coefficient(end); try execution.consumeWork(1)
        }
    }

}
