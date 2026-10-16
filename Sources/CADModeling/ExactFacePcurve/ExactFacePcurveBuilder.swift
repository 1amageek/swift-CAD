import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactFacePcurveBuilder {
    package init() {}

    package func populateMissingPcurves(
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try populateMissingPcurves(in: &model, tolerance: tolerance, using: &execution)
    }

    package func surfaceParameterCurve(
        for curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try surfaceParameterCurve(for: curve, startParameter: startParameter, endParameter: endParameter, on: surface, tolerance: tolerance, using: &execution)
    }

    package func populateMissingPcurves(
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        for face in model.faces.values {
            try execution.consumeWork(1)
            guard let surface = model.geometry.surfaces[face.surfaceID] else {
                throw missingReference("Pcurve construction references a missing face surface.", tolerance)
            }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard var loop = model.loops[loopID] else {
                    throw missingReference("Pcurve construction references a missing face loop.", tolerance)
                }
                if loop.coedges.contains(where: { $0.surfaceParameterCurve == nil }) {
                    try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
                }
                for index in loop.coedges.indices where loop.coedges[index].surfaceParameterCurve == nil {
                    try execution.consumeWork(1)
                    loop.coedges[index].surfaceParameterCurve = try pcurve(
                        for: loop.coedges[index],
                        on: surface,
                        model: model,
                        tolerance: tolerance
                    , using: &execution)
                }
                model.loops[loopID] = loop
            }
        }
    }

    private func pcurve(
        for coedge: Coedge,
        on surface: Surface3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve {
        try execution.consumeWork(1)
        guard let edge = model.edges[coedge.edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let trim = edge.trim else {
            throw missingReference("Pcurve construction requires exact trimmed edge geometry.", tolerance)
        }
        let parameters: (start: Double, end: Double)
        switch coedge.orientation {
        case .forward:
            parameters = (trim.startParameter, trim.endParameter)
        case .reversed:
            parameters = (trim.endParameter, trim.startParameter)
        }
        return try surfaceParameterCurve(
            for: curve,
            startParameter: parameters.start,
            endParameter: parameters.end,
            on: surface,
            tolerance: tolerance
        , using: &execution)
    }

    package func surfaceParameterCurve(for curve: Curve3D, startParameter: Double,
        endParameter: Double, on surface: Surface3D, tolerance: ModelingTolerance,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve {
        if let maximumAlgebraicDepth {
            let maximum = try ExactScalarDepth(value: maximumAlgebraicDepth, coefficient: maximumAlgebraicDepth)
            return try execution.withProofScope(maximum: maximum) { execution in
                try surfaceParameterCurveImpl(for: curve, startParameter: startParameter,
                    endParameter: endParameter, on: surface, tolerance: tolerance, using: &execution)
            }
        }
        return try surfaceParameterCurveImpl(for: curve, startParameter: startParameter,
            endParameter: endParameter, on: surface, tolerance: tolerance, using: &execution)
    }

    private func surfaceParameterCurveImpl(
        for curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite,
              try curve.parameterDomain.containsSpan(
                  from: startParameter,
                  to: endParameter,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact pcurve construction requires a finite non-degenerate curve trim."
            )
        }
        if case let .parameterImage(image) = curve {
            let candidate = try surfaceParameterCurve(for: image.source,
                startParameter: image.sourceParameter(at: startParameter, tolerance: tolerance, using: &execution),
                endParameter: image.sourceParameter(at: endParameter, tolerance: tolerance, using: &execution),
                on: surface, tolerance: tolerance, using: &execution)
            // Endpoint arithmetic only constructs a candidate. The retained original
            // parameter image and its whole interval law authorize correspondence.
            try verify(candidate, curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, tolerance: tolerance, using: &execution)
            return candidate
        }
        if case let .originalAffineWord(curveImage) = curve,
           case let .procedural(.originalAffineWord(surfaceImage)) = surface,
           curveImage.operationWord == surfaceImage.operationWord {
            let original = try surfaceParameterCurve(for: curveImage.source,
                startParameter: startParameter, endParameter: endParameter,
                on: surfaceImage.source, tolerance: tolerance, using: &execution)
            let candidate = SurfaceParameterCurve.originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(
                source: SurfaceLiftCurve3D(surface: surfaceImage.source, parameterCurve: original),
                target: surfaceImage, tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution))
            try verify(candidate, curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, tolerance: tolerance, using: &execution)
            return candidate
        }
        if case let .affineImage(curveImage) = curve,
           case let .procedural(.originalImage(surfaceImage)) = surface,
           curveImage.transform == surfaceImage.transform {
            let original = try surfaceParameterCurve(for: curveImage.source,
                startParameter: startParameter, endParameter: endParameter,
                on: surfaceImage.source, tolerance: tolerance, using: &execution)
            let candidate = SurfaceParameterCurve.originalImage(try OriginalImageSurfaceParameterCurve(
                source: SurfaceLiftCurve3D(surface: surfaceImage.source, parameterCurve: original),
                targetImage: surfaceImage, tolerance: tolerance, using: &execution))
            try verify(candidate, curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, tolerance: tolerance, using: &execution)
            return candidate
        }
        if case let .surfaceLift(lift) = curve,
           lift.surface == surface {
            var pcurve = try lift.parameterCurve.subcurve(
                fromNormalizedFraction: min(startParameter, endParameter),
                toNormalizedFraction: max(startParameter, endParameter),
                tolerance: tolerance
            , using: &execution)
            if endParameter < startParameter {
                pcurve = try pcurve.reversed(tolerance: tolerance, using: &execution)
            }
            try verify(
                pcurve,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return pcurve
        }
        if try isPlanar(surface, using: &execution),
           let harmonic = try planarHarmonicPcurve(
               curve: curve,
               startParameter: startParameter,
               endParameter: endParameter,
               surface: surface,
               tolerance: tolerance
           , using: &execution) {
            try verify(
                harmonic,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return harmonic
        }
        if let planarSpline = try planarBSplinePcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        , using: &execution) {
            try verify(
                planarSpline,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return planarSpline
        }
        if let projectedAnalytic = try projectedAnalyticPcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        , using: &execution) {
            try verify(
                projectedAnalytic,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return projectedAnalytic
        }
        if let greatCircle = try sphericalGreatCirclePcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        , using: &execution) {
            try verify(
                greatCircle,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return greatCircle
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): general nonlinear inverse pcurves, including
        // converted rational boundaries on retained original surface images, still require
        // an original Geometry correspondence law. Bridge and sewing construction reach
        // this branch; complete native interval/D3 correspondence must exist before those
        // domains can publish successfully. Sampled projection is not that authority.
        guard try supportsExactProjection(
            curve: curve,
            surface: surface,
            tolerance: tolerance
        , using: &execution) else {
            throw unsupportedPcurveError(tolerance)
        }

        let samples = try projectedSamples(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        , using: &execution)
        try execution.retainStorage(count: samples.count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: samples.count, stride: MemoryLayout<Double>.stride)
        let threshold = max(tolerance.distance, tolerance.angle)
        let uValues = try unwrapped(samples.map { $0.u }, domain: surface.uDomain, using: &execution)
        let vValues = try unwrapped(samples.map { $0.v }, domain: surface.vDomain, using: &execution)
        let candidate: SurfaceParameterCurve
        if spread(uValues) <= threshold,
           let firstV = vValues.first,
           let lastV = vValues.last {
            candidate = .constantU(
                u: uValues.reduce(0.0, +) / Double(uValues.count),
                vStart: firstV,
                vEnd: lastV
            )
        } else if spread(vValues) <= threshold,
                  let firstU = uValues.first,
                  let lastU = uValues.last {
            candidate = .constantV(
                v: vValues.reduce(0.0, +) / Double(vValues.count),
                uStart: firstU,
                uEnd: lastU
            )
        } else if isLinear(curve), try isPlanar(surface, using: &execution),
                  let firstU = uValues.first,
                  let lastU = uValues.last,
                  let firstV = vValues.first,
                  let lastV = vValues.last {
            candidate = .polyline([
                SurfaceParameter(u: firstU, v: firstV),
                SurfaceParameter(u: lastU, v: lastV),
            ])
        } else {
            throw unsupportedPcurveError(tolerance)
        }
        do {
            try verify(
                candidate,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
            return candidate
        } catch let error as KernelError where error.code == .topologyFailure {
            throw unsupportedPcurveError(tolerance)
        }
    }

    private func planarBSplinePcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.consumeWork(1)
        guard try isPlanar(surface, using: &execution), case let .bSpline(source) = curve else {
            return nil
        }
        var trimmed = try source.trimmed(
            from: min(startParameter, endParameter),
            to: max(startParameter, endParameter),
            tolerance: tolerance
        , using: &execution)
        if endParameter < startParameter {
            trimmed = try trimmed.reversed(tolerance: tolerance, using: &execution)
        }
        try execution.retainStorage(count: trimmed.controlPoints.count, stride: MemoryLayout<Point2D>.stride)
        let controlPoints = try trimmed.controlPoints.map { point -> Point2D in
            guard let result = try surface.exactAffineParameterProjectionResult(
                of: point,
                tolerance: tolerance
            , using: &execution) else {
                throw unsupportedPcurveError(tolerance)
            }
            switch result {
            case let .projected(projection):
                return Point2D(x: projection.u, y: projection.v)
            case .outsideTolerance:
                throw unsupportedPcurveError(tolerance)
            }
        }
        let result = BSplineCurve2D(
            degree: trimmed.degree,
            knots: trimmed.knots,
            controlPoints: controlPoints,
            weights: trimmed.weights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return .bSpline(result)
    }

    private func projectedAnalyticPcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.consumeWork(1)
        guard ProjectedAnalyticSurfaceParameterCurve.supports(curve, on: surface) else { return nil }
        return .projectedAnalytic(try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter,
            endParameter: endParameter,
            tolerance: tolerance
        , using: &execution))
    }

    private func planarHarmonicPcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.consumeWork(1)
        guard let definition = try harmonicDefinition(
            for: curve,
            tolerance: tolerance
        , using: &execution) else {
            return nil
        }
        let center = try surface.parameterProjection(of: definition.center, tolerance: tolerance, using: &execution)
        let cosinePoint = try surface.parameterProjection(
            of: definition.fullCurve.point(at: 0.0, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        let sinePoint = try surface.parameterProjection(
            of: definition.fullCurve.point(at: Double.pi / 2.0, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosinePoint.u - center.u, y: cosinePoint.v - center.v),
            sine: Point2D(x: sinePoint.u - center.u, y: sinePoint.v - center.v),
            startParameter: startParameter,
            endParameter: endParameter
        )
    }

    private func sphericalGreatCirclePcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.consumeWork(1)
        guard case let .analytic(.sphere(surfaceCenter, surfaceRadius)) = surface,
              let definition = try harmonicDefinition(
                  for: curve,
                  tolerance: tolerance
              , using: &execution),
              definition.center.isApproximatelyEqual(
                  to: surfaceCenter,
                  tolerance: tolerance.distance
              ) else {
            return nil
        }
        let cosineOffset = try definition.fullCurve.point(
            at: 0.0,
            tolerance: tolerance
        , using: &execution) - surfaceCenter
        let sineOffset = try definition.fullCurve.point(
            at: Double.pi / 2.0,
            tolerance: tolerance
        , using: &execution) - surfaceCenter
        guard abs(cosineOffset.length - surfaceRadius) <= tolerance.distance,
              abs(sineOffset.length - surfaceRadius) <= tolerance.distance else {
            return nil
        }
        return .sphericalGreatCircle(
            cosine: try cosineOffset.normalized(tolerance: tolerance.distance),
            sine: try sineOffset.normalized(tolerance: tolerance.distance),
            startParameter: startParameter,
            endParameter: endParameter
        )
    }

    private func harmonicDefinition(
        for curve: Curve3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (center: Point3D, fullCurve: Curve3D)? {
        try execution.consumeWork(1)
        switch curve {
        case let .circle(circle):
            return (circle.center, curve)
        case let .analytic(.circle(center, normal, radius)):
            return (center, .analytic(.circle(center: center, normal: normal, radius: radius)))
        case let .analytic(.arc(center, normal, radius, _, _)):
            return (center, .analytic(.circle(center: center, normal: normal, radius: radius)))
        case let .analytic(.ellipse(center, normal, majorAxis, majorRadius, minorRadius)):
            return (
                center,
                .analytic(.ellipse(
                    center: center,
                    normal: normal,
                    majorAxis: majorAxis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                ))
            )
        case let .rigidImage(image):
            guard let source = try harmonicDefinition(
                for: image.source,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            return (
                image.transform.applying(to: source.center),
                try image.transform.applying(
                    to: source.fullCurve,
                    tolerance: tolerance
                )
            )
        case let .affineImage(image):
            guard let source = try harmonicDefinition(
                for: image.source,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            return (
                image.transform.applying(to: source.center),
                .affineImage(try AffineImageCurve3D(
                    source: source.fullCurve,
                    transform: image.transform,
                    tolerance: tolerance
                , using: &execution))
            )
        case let .originalAffineWord(image):
            guard let original = try harmonicDefinition(for: image.source, tolerance: tolerance, using: &execution) else { return nil }
            return (try image.preparedWord.applying(to: original.center, usage: &execution),
                .originalAffineWord(try OriginalAffineWordCurve3D(source: original.fullCurve,
                    operationWord: image.operationWord, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)))
        case .line,
             .analytic(.line),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus),
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection,
             .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted,
             .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport,
             .parameterImage:
            return nil
        }
    }

    private func projectedSamples(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [SurfaceParameterProjection] {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 9, stride: MemoryLayout<SurfaceParameterProjection>.stride)
        return try (0...8).map { index in
            try execution.consumeWork(1)
            let fraction = Double(index) / 8.0
            let parameter = startParameter + (endParameter - startParameter) * fraction
            return try surface.parameterProjection(
                of: curve.point(at: parameter, tolerance: tolerance, using: &execution),
                tolerance: tolerance
            , using: &execution)
        }
    }

    private func verify(
        _ pcurve: SurfaceParameterCurve,
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: startParameter,
            to: endParameter,
            surface: surface,
            parameterCurve: pcurve,
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 32,
                maximumCellCount: 65_536
            ),
            tolerance: tolerance, using: &execution
        )
    }

    private func unwrapped(
        _ values: [Double],
        domain: ParameterDomain
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        guard case let .periodic(period) = domain,
              let first = values.first else {
            return values
        }
        try execution.retainStorage(count: values.count, stride: MemoryLayout<Double>.stride)
        var result = [first]
        for value in values.dropFirst() {
            try execution.consumeWork(1)
            var adjusted = value
            guard let previous = result.last else { continue }
            while adjusted - previous > period * 0.5 { try execution.consumeWork(1); adjusted -= period }
            while previous - adjusted > period * 0.5 { try execution.consumeWork(1); adjusted += period }
            result.append(adjusted)
        }
        return result
    }

    private func spread(_ values: [Double]) -> Double {
        guard let minimum = values.min(), let maximum = values.max() else {
            return .infinity
        }
        return maximum - minimum
    }

    private func isPlanar(_ surface: Surface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try surface.hasExactAffineParameterization(using: &execution)
    }

    private func isCylindrical(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch try exactAnalyticReduction(of: surface, tolerance: tolerance, using: &execution) {
        case .cylinder, .analytic(.cylinder):
            return true
        case .plane, .analytic, .bSpline, .procedural:
            return false
        }
    }

    private func isConical(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case .analytic(.cone) = try exactAnalyticReduction(
            of: surface,
            tolerance: tolerance
        , using: &execution) else { return false }
        return true
    }

    private func isSpherical(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case .analytic(.sphere) = try exactAnalyticReduction(
            of: surface,
            tolerance: tolerance
        , using: &execution) else { return false }
        return true
    }

    private func isToroidal(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard case .analytic(.torus) = try exactAnalyticReduction(
            of: surface,
            tolerance: tolerance
        , using: &execution) else { return false }
        return true
    }

    private func exactAnalyticReduction(
        of surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.consumeWork(1)
        guard case let .procedural(.offset(offset)) = surface else {
            return surface
        }
        return try offset.exactChartPreservingSurface(tolerance: tolerance, using: &execution)
            ?? surface
    }

    private func isLinear(_ curve: Curve3D) -> Bool {
        curve.hasExactLinearParameterization
    }

    private func supportsExactProjection(
        curve: Curve3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        if isLinear(curve) {
            if try isPlanar(surface, using: &execution) { return true }
            if try isCylindrical(surface, tolerance: tolerance, using: &execution) { return true }
            return try isConical(surface, tolerance: tolerance, using: &execution)
        }
        let supportedSurface: Bool
        if try isCylindrical(surface, tolerance: tolerance, using: &execution) {
            supportedSurface = true
        } else if try isConical(surface, tolerance: tolerance, using: &execution) {
            supportedSurface = true
        } else if try isSpherical(surface, tolerance: tolerance, using: &execution) {
            supportedSurface = true
        } else {
            supportedSurface = try isToroidal(surface, tolerance: tolerance, using: &execution)
        }
        guard supportedSurface else {
            return false
        }
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc):
            return true
        case let .rigidImage(image):
            return try supportsExactProjection(
                curve: image.source,
                surface: image.transform.inverted().applying(
                    to: surface,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            , using: &execution)
        case .line,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection,
             .affineImage,
             .originalAffineWord,
             .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted,
             .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport,
             .parameterImage:
            return false
        }
    }

    private func missingReference(
        _ message: String,
        _ tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private func unsupportedPcurveError(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "The exact edge-on-surface relation has no supported pcurve representation."
        )
    }
}
