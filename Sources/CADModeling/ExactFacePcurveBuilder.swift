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
        try tolerance.validate()
        for face in model.faces.values {
            guard let surface = model.geometry.surfaces[face.surfaceID] else {
                throw missingReference("Pcurve construction references a missing face surface.", tolerance)
            }
            for loopID in face.loops {
                guard var loop = model.loops[loopID] else {
                    throw missingReference("Pcurve construction references a missing face loop.", tolerance)
                }
                for index in loop.coedges.indices where loop.coedges[index].surfaceParameterCurve == nil {
                    loop.coedges[index].surfaceParameterCurve = try pcurve(
                        for: loop.coedges[index],
                        on: surface,
                        model: model,
                        tolerance: tolerance
                    )
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
    ) throws -> SurfaceParameterCurve {
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
        )
    }

    package func surfaceParameterCurve(
        for curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
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
        if case let .surfaceLift(lift) = curve,
           lift.surface == surface {
            var pcurve = try lift.parameterCurve.subcurve(
                fromNormalizedFraction: min(startParameter, endParameter),
                toNormalizedFraction: max(startParameter, endParameter),
                tolerance: tolerance
            )
            if endParameter < startParameter {
                pcurve = try pcurve.reversed(tolerance: tolerance)
            }
            try verify(
                pcurve,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            )
            return pcurve
        }
        if isPlanar(surface),
           let harmonic = try planarHarmonicPcurve(
               curve: curve,
               startParameter: startParameter,
               endParameter: endParameter,
               surface: surface,
               tolerance: tolerance
           ) {
            try verify(
                harmonic,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            )
            return harmonic
        }
        if let planarSpline = try planarBSplinePcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        ) {
            try verify(
                planarSpline,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            )
            return planarSpline
        }
        if let projectedAnalytic = try projectedAnalyticPcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        ) {
            try verify(
                projectedAnalytic,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            )
            return projectedAnalytic
        }
        if let greatCircle = try sphericalGreatCirclePcurve(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        ) {
            try verify(
                greatCircle,
                curve: curve,
                startParameter: startParameter,
                endParameter: endParameter,
                surface: surface,
                tolerance: tolerance
            )
            return greatCircle
        }
        guard supportsExactProjection(curve: curve, surface: surface) else {
            throw unsupportedPcurveError(tolerance)
        }

        let samples = try projectedSamples(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            surface: surface,
            tolerance: tolerance
        )
        let threshold = max(tolerance.distance, tolerance.angle)
        let uValues = unwrapped(samples.map(\.u), domain: surface.uDomain)
        let vValues = unwrapped(samples.map(\.v), domain: surface.vDomain)
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
        } else if isLinear(curve), isPlanar(surface),
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
            )
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
    ) throws -> SurfaceParameterCurve? {
        guard isPlanar(surface), case let .bSpline(source) = curve else {
            return nil
        }
        var trimmed = try source.trimmed(
            from: min(startParameter, endParameter),
            to: max(startParameter, endParameter),
            tolerance: tolerance
        )
        if endParameter < startParameter {
            trimmed = try trimmed.reversed(tolerance: tolerance)
        }
        let controlPoints = try trimmed.controlPoints.map { point -> Point2D in
            let projection = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return Point2D(x: projection.u, y: projection.v)
        }
        let result = BSplineCurve2D(
            degree: trimmed.degree,
            knots: trimmed.knots,
            controlPoints: controlPoints,
            weights: trimmed.weights
        )
        try result.validate(tolerance: tolerance)
        return .bSpline(result)
    }

    private func projectedAnalyticPcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve? {
        let isOpenConic: Bool
        switch curve {
        case .analytic(.hyperbola), .analytic(.parabola):
            isOpenConic = true
        case .line, .circle, .analytic, .bSpline, .implicit, .surfaceLift:
            isOpenConic = false
        }
        guard isOpenConic else { return nil }
        let isSupportedSurface: Bool
        switch surface {
        case .plane, .analytic(.plane), .analytic(.cone):
            isSupportedSurface = true
        case .cylinder, .analytic, .bSpline:
            isSupportedSurface = false
        }
        guard isSupportedSurface else { return nil }
        return .projectedAnalytic(try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter,
            endParameter: endParameter,
            tolerance: tolerance
        ))
    }

    private func planarHarmonicPcurve(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve? {
        guard let definition = harmonicDefinition(for: curve) else {
            return nil
        }
        let center = try surface.parameterProjection(of: definition.center, tolerance: tolerance)
        let cosinePoint = try surface.parameterProjection(
            of: definition.fullCurve.point(at: 0.0, tolerance: tolerance),
            tolerance: tolerance
        )
        let sinePoint = try surface.parameterProjection(
            of: definition.fullCurve.point(at: Double.pi / 2.0, tolerance: tolerance),
            tolerance: tolerance
        )
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
    ) throws -> SurfaceParameterCurve? {
        guard case let .analytic(.sphere(surfaceCenter, surfaceRadius)) = surface,
              let definition = harmonicDefinition(for: curve),
              definition.center.isApproximatelyEqual(
                  to: surfaceCenter,
                  tolerance: tolerance.distance
              ) else {
            return nil
        }
        let cosineOffset = try definition.fullCurve.point(
            at: 0.0,
            tolerance: tolerance
        ) - surfaceCenter
        let sineOffset = try definition.fullCurve.point(
            at: Double.pi / 2.0,
            tolerance: tolerance
        ) - surfaceCenter
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
        for curve: Curve3D
    ) -> (center: Point3D, fullCurve: Curve3D)? {
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
        case .line,
             .analytic(.line),
             .analytic(.hyperbola),
             .analytic(.parabola),
             .analytic(.planeTorus),
             .bSpline,
             .implicit,
             .surfaceLift:
            return nil
        }
    }

    private func projectedSamples(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterProjection] {
        try (0...8).map { index in
            let fraction = Double(index) / 8.0
            let parameter = startParameter + (endParameter - startParameter) * fraction
            return try surface.parameterProjection(
                of: curve.point(at: parameter, tolerance: tolerance),
                tolerance: tolerance
            )
        }
    }

    private func verify(
        _ pcurve: SurfaceParameterCurve,
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
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
            tolerance: tolerance
        )
    }

    private func unwrapped(
        _ values: [Double],
        domain: ParameterDomain
    ) -> [Double] {
        guard case let .periodic(period) = domain,
              let first = values.first else {
            return values
        }
        var result = [first]
        for value in values.dropFirst() {
            var adjusted = value
            guard let previous = result.last else { continue }
            while adjusted - previous > period * 0.5 { adjusted -= period }
            while previous - adjusted > period * 0.5 { adjusted += period }
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

    private func isPlanar(_ surface: Surface3D) -> Bool {
        switch surface {
        case .plane, .analytic(.plane):
            return true
        case .cylinder, .analytic, .bSpline:
            return false
        }
    }

    private func isCylindrical(_ surface: Surface3D) -> Bool {
        switch surface {
        case .cylinder, .analytic(.cylinder):
            return true
        case .plane, .analytic, .bSpline:
            return false
        }
    }

    private func isConical(_ surface: Surface3D) -> Bool {
        guard case .analytic(.cone) = surface else { return false }
        return true
    }

    private func isSpherical(_ surface: Surface3D) -> Bool {
        guard case .analytic(.sphere) = surface else { return false }
        return true
    }

    private func isToroidal(_ surface: Surface3D) -> Bool {
        guard case .analytic(.torus) = surface else { return false }
        return true
    }

    private func isLinear(_ curve: Curve3D) -> Bool {
        switch curve {
        case .line, .analytic(.line):
            return true
        case .circle, .analytic, .bSpline, .implicit, .surfaceLift:
            return false
        }
    }

    private func supportsExactProjection(
        curve: Curve3D,
        surface: Surface3D
    ) -> Bool {
        if isLinear(curve) {
            return isPlanar(surface) || isCylindrical(surface) || isConical(surface)
        }
        guard isCylindrical(surface)
                || isConical(surface)
                || isSpherical(surface)
                || isToroidal(surface) else {
            return false
        }
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc):
            return true
        case .line, .analytic, .bSpline, .implicit, .surfaceLift:
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
