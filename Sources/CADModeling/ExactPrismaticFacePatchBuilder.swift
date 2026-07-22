import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactPrismaticFacePatchBuilder: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func request(
        boundary: [ExactPrismaticBoundarySegment],
        axis: Vector3D,
        height: Double,
        featureID: FeatureID,
        stablePrefix: String,
        bodyKind: BodyKind = .solid,
        includesCaps: Bool = true,
        sideOrientation: Orientation = .forward,
        capNormal: Vector3D? = nil
    ) throws -> BRepSewingRequest {
        try request(
            boundaries: [boundary],
            axis: axis,
            height: height,
            featureID: featureID,
            stablePrefix: stablePrefix,
            bodyKind: bodyKind,
            includesCaps: includesCaps,
            sideOrientation: sideOrientation,
            capNormal: capNormal
        )
    }

    package func request(
        boundaries: [[ExactPrismaticBoundarySegment]],
        axis: Vector3D,
        height: Double,
        featureID: FeatureID,
        stablePrefix: String,
        bodyKind: BodyKind = .solid,
        includesCaps: Bool = true,
        sideOrientation: Orientation = .forward,
        capNormal: Vector3D? = nil
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        let axis = try axis.normalized(tolerance: tolerance.distance)
        let capNormal = try (capNormal ?? axis).normalized(
            tolerance: tolerance.distance
        )
        guard height > tolerance.distance,
              boundaries.isEmpty == false,
              boundaries.allSatisfy({ $0.count >= 2 }),
              stablePrefix.isEmpty == false,
              bodyKind != .solid || includesCaps else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact prismatic sewing requires a closed boundary and positive height."
            )
        }
        for boundary in boundaries {
            try validateClosure(boundary)
        }
        let shells = try boundaries.enumerated().map { index, boundary in
            let componentPrefix = boundaries.count == 1
                ? stablePrefix
                : "\(stablePrefix):component:\(index)"
            return try shell(
                boundary: boundary,
                axis: axis,
                height: height,
                stablePrefix: componentPrefix,
                includesCaps: includesCaps,
                sideOrientation: sideOrientation,
                capNormal: capNormal
            )
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: bodyKind,
            shells: shells
        )
    }

    private func shell(
        boundary: [ExactPrismaticBoundarySegment],
        axis: Vector3D,
        height: Double,
        stablePrefix: String,
        includesCaps: Bool,
        sideOrientation: Orientation,
        capNormal: Vector3D
    ) throws -> BRepSewingShell {
        let topOffset = axis * height
        var patches: [BRepSewingFacePatch] = []
        if includesCaps {
            patches.append(try capPatch(
                boundary: boundary,
                capNormal: capNormal,
                offset: .zero,
                isTop: false,
                stableID: "\(stablePrefix):cap:lower"
            ))
            patches.append(try capPatch(
                boundary: boundary,
                capNormal: capNormal,
                offset: topOffset,
                isTop: true,
                stableID: "\(stablePrefix):cap:upper"
            ))
        }
        patches.append(contentsOf: try boundary.enumerated().map { index, segment in
            try sidePatch(
                segment: segment,
                index: index,
                axis: axis,
                height: height,
                stableID: "\(stablePrefix):side:\(index)",
                requestedOrientation: sideOrientation
            )
        })
        return BRepSewingShell(
            stableID: "\(stablePrefix):shell",
            patches: patches
        )
    }

    private func validateClosure(
        _ boundary: [ExactPrismaticBoundarySegment]
    ) throws {
        for index in boundary.indices {
            let next = boundary[(index + 1) % boundary.count]
            guard boundary[index].endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Exact prismatic boundary is not closed."
                )
            }
        }
    }

    private func capPatch(
        boundary: [ExactPrismaticBoundarySegment],
        capNormal: Vector3D,
        offset: Vector3D,
        isTop: Bool,
        stableID: String
    ) throws -> BRepSewingFacePatch {
        guard let first = boundary.first else {
            throw FeatureEvaluationError.emptyResult(
                "Exact prismatic cap has no boundary."
            )
        }
        let surface = Surface3D.plane(Plane3D(
            origin: first.startPoint + offset,
            normal: isTop ? capNormal : -capNormal
        ))
        let ordered = isTop
            ? Array(boundary.enumerated())
            : Array(boundary.enumerated().reversed())
        let edges = try ordered.map { index, segment in
            try boundaryEdge(
                segment,
                offset: offset,
                reversed: isTop == false,
                surface: surface,
                stableID: "\(stableID):edge:\(index)"
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):loop",
                role: .outer,
                edges: edges
            )]
        )
    }

    private func sidePatch(
        segment: ExactPrismaticBoundarySegment,
        index: Int,
        axis: Vector3D,
        height: Double,
        stableID: String,
        requestedOrientation: Orientation
    ) throws -> BRepSewingFacePatch {
        let topOffset = axis * height
        let surface: Surface3D
        let orientation: Orientation
        switch segment.geometry {
        case .line:
            let direction = try (segment.endPoint - segment.startPoint).normalized(
                tolerance: tolerance.distance
            )
            surface = .plane(Plane3D(
                origin: segment.startPoint,
                normal: try direction.cross(axis).normalized(
                    tolerance: tolerance.distance
                )
            ))
            orientation = .forward
        case let .circularArc(circle, startParameter, endParameter):
            surface = .cylinder(Cylinder3D(
                origin: circle.center,
                axis: axis,
                radius: circle.radius
            ))
            orientation = endParameter >= startParameter ? .forward : .reversed
        case let .bSpline(curve):
            surface = .bSpline(try ruledSurface(
                curve: curve,
                axis: axis,
                height: height
            ))
            orientation = .forward
        }

        let ruledParameters = try ruledSurfaceParameters(for: segment)
        let bottom = try boundaryEdge(
            segment,
            offset: .zero,
            reversed: false,
            surface: surface,
            ruledSurfaceV: ruledParameters == nil ? nil : 0.0,
            stableID: "\(stableID):bottom"
        )
        let end = try lineEdge(
            from: segment.endPoint,
            to: segment.endPoint + topOffset,
            surface: surface,
            surfaceParameterCurve: ruledParameters.map {
                .constantU(u: $0.upper, vStart: 0.0, vEnd: 1.0)
            },
            stableID: "\(stableID):end"
        )
        let top = try boundaryEdge(
            segment,
            offset: topOffset,
            reversed: true,
            surface: surface,
            ruledSurfaceV: ruledParameters == nil ? nil : 1.0,
            stableID: "\(stableID):top"
        )
        let start = try lineEdge(
            from: segment.startPoint + topOffset,
            to: segment.startPoint,
            surface: surface,
            surfaceParameterCurve: ruledParameters.map {
                .constantU(u: $0.lower, vStart: 1.0, vEnd: 0.0)
            },
            stableID: "\(stableID):start"
        )
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: combined(
                orientation,
                with: requestedOrientation
            ),
            loops: [BRepSewingLoop(
                stableID: "\(stableID):loop",
                role: .outer,
                edges: [bottom, end, top, start]
            )]
        )
    }

    private func boundaryEdge(
        _ segment: ExactPrismaticBoundarySegment,
        offset: Vector3D,
        reversed: Bool,
        surface: Surface3D,
        ruledSurfaceV: Double? = nil,
        stableID: String
    ) throws -> BRepSewingEdge {
        switch segment.geometry {
        case .line:
            let start = (reversed ? segment.endPoint : segment.startPoint) + offset
            let end = (reversed ? segment.startPoint : segment.endPoint) + offset
            return try lineEdge(
                from: start,
                to: end,
                surface: surface,
                stableID: stableID
            )
        case let .circularArc(circle, startParameter, endParameter):
            let shifted = Circle3D(
                center: circle.center + offset,
                normal: circle.normal,
                radius: circle.radius
            )
            let start = reversed ? endParameter : startParameter
            let end = reversed ? startParameter : endParameter
            let curve = Curve3D.circle(shifted)
            return BRepSewingEdge(
                stableID: stableID,
                curve: curve,
                startParameter: start,
                endParameter: end,
                startPoint: try curve.point(at: start, tolerance: tolerance),
                endPoint: try curve.point(at: end, tolerance: tolerance),
                surfaceParameterCurve: try circularPcurve(
                    circle: shifted,
                    startParameter: start,
                    endParameter: end,
                    surface: surface
                )
            )
        case let .bSpline(source):
            let curve = try translated(source, by: offset)
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact prismatic B-spline edge requires a bounded curve."
                )
            }
            let start = reversed ? upper : lower
            let end = reversed ? lower : upper
            let exactCurve = Curve3D.bSpline(curve)
            let pcurve: SurfaceParameterCurve
            if let ruledSurfaceV {
                pcurve = .constantV(
                    v: ruledSurfaceV,
                    uStart: start,
                    uEnd: end
                )
                try pcurve.validate(on: surface, tolerance: tolerance)
            } else {
                pcurve = try planarBSplinePcurve(
                    curve: curve,
                    reversed: reversed,
                    surface: surface
                )
            }
            return BRepSewingEdge(
                stableID: stableID,
                curve: exactCurve,
                startParameter: start,
                endParameter: end,
                startPoint: try exactCurve.point(at: start, tolerance: tolerance),
                endPoint: try exactCurve.point(at: end, tolerance: tolerance),
                surfaceParameterCurve: pcurve
            )
        }
    }

    private func lineEdge(
        from start: Point3D,
        to end: Point3D,
        surface: Surface3D,
        surfaceParameterCurve: SurfaceParameterCurve? = nil,
        stableID: String
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let length = delta.length
        let curve = Curve3D.line(Line3D(
            origin: start,
            direction: try delta.normalized(tolerance: tolerance.distance)
        ))
        let pcurve: SurfaceParameterCurve
        if let surfaceParameterCurve {
            try surfaceParameterCurve.validate(on: surface, tolerance: tolerance)
            pcurve = surfaceParameterCurve
        } else {
            let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
            let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
            if isCylindrical(surface),
               abs(startUV.u - endUV.u) <= tolerance.angle {
                pcurve = .constantU(
                    u: startUV.u,
                    vStart: startUV.v,
                    vEnd: endUV.v
                )
            } else {
                pcurve = .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            }
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: pcurve
        )
    }

    private func circularPcurve(
        circle: Circle3D,
        startParameter: Double,
        endParameter: Double,
        surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        let curve = Curve3D.circle(circle)
        if isCylindrical(surface) {
            let start = try surface.parameterProjection(
                of: curve.point(at: startParameter, tolerance: tolerance),
                tolerance: tolerance
            )
            let middle = try surface.parameterProjection(
                of: curve.point(
                    at: 0.5 * (startParameter + endParameter),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
            let end = try surface.parameterProjection(
                of: curve.point(at: endParameter, tolerance: tolerance),
                tolerance: tolerance
            )
            let unwrappedMiddle = unwrappedPeriodicParameter(
                middle.u,
                nearest: start.u
            )
            let unwrappedEnd = unwrappedPeriodicParameter(
                end.u,
                nearest: 2.0 * unwrappedMiddle - start.u
            )
            return .constantV(
                v: start.v,
                uStart: start.u,
                uEnd: unwrappedEnd
            )
        }
        let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
        let cosine = try surface.parameterProjection(
            of: curve.point(at: 0.0, tolerance: tolerance),
            tolerance: tolerance
        )
        let sine = try surface.parameterProjection(
            of: curve.point(at: Double.pi / 2.0, tolerance: tolerance),
            tolerance: tolerance
        )
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
            sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
            startParameter: startParameter,
            endParameter: endParameter
        )
    }

    private func ruledSurface(
        curve: BSplineCurve3D,
        axis: Vector3D,
        height: Double
    ) throws -> BSplineSurface3D {
        let topOffset = axis * height
        let surface = BSplineSurface3D(
            uDegree: curve.degree,
            vDegree: 1,
            uKnots: curve.knots,
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                curve.controlPoints,
                curve.controlPoints.map { $0 + topOffset },
            ],
            weights: [curve.weights, curve.weights]
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    private func translated(
        _ curve: BSplineCurve3D,
        by offset: Vector3D
    ) throws -> BSplineCurve3D {
        let translated = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map { $0 + offset },
            weights: curve.weights
        )
        try translated.validate(tolerance: tolerance)
        return translated
    }

    private func planarBSplinePcurve(
        curve: BSplineCurve3D,
        reversed: Bool,
        surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        guard isPlanar(surface) else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact prismatic B-spline edges require a planar cap or ruled B-spline side surface."
            )
        }
        var projected = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: try curve.controlPoints.map { point in
                let parameter = try surface.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
                return Point2D(x: parameter.u, y: parameter.v)
            },
            weights: curve.weights
        )
        if reversed {
            projected = try projected.reversed(tolerance: tolerance)
        }
        try projected.validate(tolerance: tolerance)
        return .bSpline(projected)
    }

    private func ruledSurfaceParameters(
        for segment: ExactPrismaticBoundarySegment
    ) throws -> (lower: Double, upper: Double)? {
        guard case let .bSpline(curve) = segment.geometry else {
            return nil
        }
        guard case let .closed(lower, upper) = curve.domain,
              upper > lower else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact prismatic ruled surface requires a bounded spline parameter domain."
            )
        }
        return (lower, upper)
    }

    private func combined(
        _ lhs: Orientation,
        with rhs: Orientation
    ) -> Orientation {
        lhs == rhs ? .forward : .reversed
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

    private func unwrappedPeriodicParameter(
        _ value: Double,
        nearest reference: Double
    ) -> Double {
        let period = 2.0 * Double.pi
        return value + ((reference - value) / period).rounded() * period
    }
}
