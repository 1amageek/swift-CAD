import CADCore
import CADGeometry
import Foundation

/// Certifies divergence-theorem volume for trimmed B-spline faces.
///
/// Polynomial Bezier spans use exact Bernstein coefficient integration,
/// axis-aligned planar straight-edge faces use an outward-rounded boundary
/// Green integral, arbitrary polynomial Bezier loops use an exact Bernstein
/// flux primitive, and remaining rational rectangles use certified adaptive
/// quadrature. Unsupported trims never enter an approximate success path.
struct TrimmedParametricSurfaceVolumeEvaluator {
    struct VolumeBounds: Sendable, Hashable {
        let lower: Double
        let upper: Double

        var midpoint: Double {
            lower + (upper - lower) * 0.5
        }

        var errorRadius: Double {
            (upper - lower) * 0.5
        }
    }

    private let maximumCoefficientOperations: Int
    private let maximumRationalSubdivisionDepth: Int
    private let maximumRationalCellCount: Int

    init(
        maximumCoefficientOperations: Int = 2_000_000,
        maximumRationalSubdivisionDepth: Int = 10,
        maximumRationalCellCount: Int = 1_000_000
    ) {
        self.maximumCoefficientOperations = maximumCoefficientOperations
        self.maximumRationalSubdivisionDepth = maximumRationalSubdivisionDepth
        self.maximumRationalCellCount = maximumRationalCellCount
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let bounds = try volumeBounds(
            of: shell,
            in: model,
            tolerance: tolerance
        ) else {
            return nil
        }
        let reference = try referencePoint(for: shell, in: model)
        let characteristicLength = try characteristicLength(
            of: shell,
            in: model,
            reference: reference,
            tolerance: tolerance
        )
        let requestedError = volumeTolerance(
            characteristicLength: characteristicLength,
            tolerance: tolerance
        )
        guard bounds.errorRadius <= requestedError else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: bounds.errorRadius,
                tolerance: tolerance,
                message: "Certified B-spline surface-flux volume exceeded the requested enclosure width."
            )
        }
        return bounds.midpoint
    }

    func volumeBounds(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        let reference = try referencePoint(for: shell, in: model)
        let characteristicLength = try characteristicLength(
            of: shell,
            in: model,
            reference: reference,
            tolerance: tolerance
        )
        let requestedError = volumeTolerance(
            characteristicLength: characteristicLength,
            tolerance: tolerance
        )
        let faceCount = shell.faceIDs.count
        guard faceCount > 0 else {
            return nil
        }
        let totalCoedgeCount = try coedgeCount(of: shell, in: model)
        guard totalCoedgeCount > 0 else {
            return nil
        }
        var budget = CoefficientBudget(limit: maximumCoefficientOperations)
        var total = OutwardInterval.exact(0.0)

        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Parametric volume references missing face geometry."
                )
            }
            guard case let .bSpline(spline) = surface else {
                return nil
            }
            try spline.validate(tolerance: tolerance)
            let trim = try ExactRectangularPcurveDomainResolver().resolve(
                face: face,
                model: model,
                tolerance: tolerance
            )
            var contribution: OutwardInterval
            if let trim {
                if var patch = try PolynomialBezierPatch(
                    surface: spline,
                    tolerance: tolerance
                ) {
                    patch = try patch.trimmed(
                        uLower: trim.uLower,
                        uUpper: trim.uUpper,
                        vLower: trim.vLower,
                        vUpper: trim.vUpper,
                        sourceUDomain: spline.uDomain,
                        sourceVDomain: spline.vDomain,
                        tolerance: tolerance
                    )
                    contribution = try patch.fluxIntegral(
                        reference: reference,
                        budget: &budget,
                        tolerance: tolerance
                    )
                } else if let planarContribution = try axisAlignedPlanarContribution(
                    face: face,
                    surface: spline,
                    model: model,
                    reference: reference,
                    tolerance: tolerance
                ) {
                    contribution = planarContribution
                } else {
                    let rationalBounds = try CertifiedRationalBezierSurfaceFluxIntegrator(
                        maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
                        maximumCellCount: maximumRationalCellCount
                    ).integrate(
                        surface: spline,
                        uLower: trim.uLower,
                        uUpper: trim.uUpper,
                        vLower: trim.vLower,
                        vUpper: trim.vUpper,
                        reference: reference,
                        requestedError: requestedError * 0.99 / Double(faceCount),
                        tolerance: tolerance
                    )
                    guard let rationalBounds else {
                        return nil
                    }
                    contribution = OutwardInterval(
                        lower: rationalBounds.lower,
                        upper: rationalBounds.upper
                    )
                }
            } else if let patch = try PolynomialBezierPatch(
                surface: spline,
                tolerance: tolerance
            ), let polynomialContribution = try arbitraryPolynomialContribution(
                face: face,
                model: model,
                primitive: try patch.fluxPrimitive(
                    reference: reference,
                    uDomain: spline.uDomain,
                    vDomain: spline.vDomain,
                    budget: &budget,
                    tolerance: tolerance
                ),
                requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
                tolerance: tolerance
            ) {
                contribution = polynomialContribution
            } else if let planarContribution = try axisAlignedPlanarContribution(
                face: face,
                surface: spline,
                model: model,
                reference: reference,
                tolerance: tolerance
            ) {
                contribution = planarContribution
            } else if let field = try CertifiedRationalBezierSurfaceFluxIntegrator(
                maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
                maximumCellCount: maximumRationalCellCount
            ).preparedField(
                surface: spline,
                reference: reference,
                tolerance: tolerance
            ), let rationalContribution = try arbitraryRationalContribution(
                face: face,
                surface: spline,
                model: model,
                field: field,
                requestedCurveWidth: requestedError * 1.98 / Double(totalCoedgeCount),
                tolerance: tolerance
            ) {
                contribution = rationalContribution
            } else {
                return nil
            }
            if face.orientation == .reversed {
                contribution = -contribution
            }
            total = total + contribution
        }

        guard total.lower.isFinite, total.upper.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Certified B-spline surface-flux volume exceeded finite arithmetic."
            )
        }
        return VolumeBounds(lower: total.lower, upper: total.upper)
    }

    func rationalLoopVolumeBounds(
        surface: BSplineSurface3D,
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        reference: Point3D,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard !parameterCurves.isEmpty,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Rational B-spline loop volume requires pcurves and a positive enclosure width."
            )
        }
        let integrator = CertifiedRationalBezierSurfaceFluxIntegrator(
            maximumSubdivisionDepth: maximumRationalSubdivisionDepth,
            maximumCellCount: maximumRationalCellCount
        )
        if let plane = try AxisAlignedPlane(
            surface: surface,
            tolerance: tolerance
        ) {
            if plane.coordinate == plane.coordinate(of: reference) {
                return VolumeBounds(lower: 0.0, upper: 0.0)
            }
            guard let planarField = try integrator.preparedField(
                surface: surface,
                reference: reference,
                includeFluxNumerator: false,
                tolerance: tolerance
            ) else {
                return nil
            }
            if let planarContribution = try rationalPlanarLoopContribution(
                parameterCurves: parameterCurves,
                role: role,
                plane: plane,
                field: planarField,
                reference: reference,
                requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
                tolerance: tolerance
            ) {
                return VolumeBounds(
                    lower: planarContribution.lower,
                    upper: planarContribution.upper
                )
            }
        }
        guard let field = try integrator.preparedField(
            surface: surface,
            reference: reference,
            tolerance: tolerance
        ) else {
            return nil
        }
        guard let contribution = try rationalLoopContribution(
            parameterCurves: parameterCurves,
            role: role,
            surface: surface,
            field: field,
            requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
            tolerance: tolerance
        ) else {
            return nil
        }
        return VolumeBounds(lower: contribution.lower, upper: contribution.upper)
    }

    private func rationalPlanarLoopContribution(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        plane: AxisAlignedPlane,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        reference: Point3D,
        requestedCurveWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        var projectedArea = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
        var parameterArea = SurfaceParameterAreaBounds.zero
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        for curve in parameterCurves {
            guard let curveArea = try integrator.rationalPlanarAreaBounds(
                for: curve,
                field: field,
                projection: plane.projection,
                requestedWidth: requestedCurveWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            projectedArea = projectedArea + curveArea
            parameterArea = parameterArea.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: max(
                        tolerance.relative,
                        Double.ulpOfOne * 256.0
                    ),
                    tolerance: tolerance
                )
            )
        }
        let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        if parameterArea.lower > 0.0 {
            traversalNormalized = projectedArea
        } else if parameterArea.upper < 0.0 {
            traversalNormalized = -projectedArea
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: parameterArea.minimumAbsoluteValue,
                tolerance: tolerance,
                message: "Certified rational planar area could not prove loop orientation."
            )
        }
        let roleNormalized = role == .outer
            ? traversalNormalized
            : -traversalNormalized
        let offset = OutwardInterval.exact(plane.coordinate)
            - OutwardInterval.exact(plane.coordinate(of: reference))
        return offset * OutwardInterval(
            lower: roleNormalized.lower,
            upper: roleNormalized.upper
        ) / OutwardInterval.exact(3.0)
    }

    func polynomialLoopVolumeBounds(
        surface: BSplineSurface3D,
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        reference: Point3D,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> VolumeBounds? {
        try tolerance.validate()
        guard !parameterCurves.isEmpty,
              requestedWidth.isFinite,
              requestedWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedWidth,
                tolerance: tolerance,
                message: "Polynomial B-spline loop volume requires pcurves and a positive enclosure width."
            )
        }
        guard let patch = try PolynomialBezierPatch(
            surface: surface,
            tolerance: tolerance
        ) else {
            return nil
        }
        var budget = CoefficientBudget(limit: maximumCoefficientOperations)
        let primitive = try patch.fluxPrimitive(
            reference: reference,
            uDomain: surface.uDomain,
            vDomain: surface.vDomain,
            budget: &budget,
            tolerance: tolerance
        )
        guard let contribution = try polynomialLoopContribution(
            parameterCurves: parameterCurves,
            role: role,
            primitive: primitive,
            requestedCurveWidth: requestedWidth / Double(parameterCurves.count),
            tolerance: tolerance
        ) else {
            return nil
        }
        return VolumeBounds(lower: contribution.lower, upper: contribution.upper)
    }

    private func arbitraryPolynomialContribution(
        face: Face,
        model: BRepModel,
        primitive: CertifiedPolynomialSurfaceFluxPrimitive,
        requestedCurveWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        var total = OutwardInterval.exact(0.0)
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Polynomial B-spline volume references a missing or empty loop."
                )
            }
            var curves: [SurfaceParameterCurve] = []
            curves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                curves.append(curve)
            }
            guard let contribution = try polynomialLoopContribution(
                parameterCurves: curves,
                role: loop.role,
                primitive: primitive,
                requestedCurveWidth: requestedCurveWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            total = total + contribution
        }
        return total
    }

    private func arbitraryRationalContribution(
        face: Face,
        surface: BSplineSurface3D,
        model: BRepModel,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        requestedCurveWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        var total = OutwardInterval.exact(0.0)
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Rational B-spline volume references a missing or empty loop."
                )
            }
            var curves: [SurfaceParameterCurve] = []
            curves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                curves.append(curve)
            }
            guard let contribution = try rationalLoopContribution(
                parameterCurves: curves,
                role: loop.role,
                surface: surface,
                field: field,
                requestedCurveWidth: requestedCurveWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            total = total + contribution
        }
        return total
    }

    private func rationalLoopContribution(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        surface: BSplineSurface3D,
        field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
        requestedCurveWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        guard case let .closed(uBase, _) = surface.uDomain,
              !parameterCurves.isEmpty,
              requestedCurveWidth.isFinite,
              requestedCurveWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedCurveWidth,
                tolerance: tolerance,
                message: "Rational B-spline volume requires a bounded surface and positive curve enclosure."
            )
        }
        let curveIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
        var rawFlux = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
        var areaBounds = SurfaceParameterAreaBounds.zero
        for curve in parameterCurves {
            guard let contribution = try curveIntegrator.rationalSurfaceBounds(
                for: curve,
                field: field,
                uBase: uBase,
                requestedWidth: requestedCurveWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            rawFlux = rawFlux + contribution
            areaBounds = areaBounds.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
                    tolerance: tolerance
                )
            )
        }
        let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        if areaBounds.lower > 0.0 {
            traversalNormalized = rawFlux
        } else if areaBounds.upper < 0.0 {
            traversalNormalized = -rawFlux
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: areaBounds.minimumAbsoluteValue,
                tolerance: tolerance,
                message: "Rational B-spline volume could not certify loop orientation."
            )
        }
        let roleNormalized = role == .outer
            ? traversalNormalized
            : -traversalNormalized
        return OutwardInterval(
            lower: roleNormalized.lower,
            upper: roleNormalized.upper
        )
    }

    private func polynomialLoopContribution(
        parameterCurves: [SurfaceParameterCurve],
        role: LoopRole,
        primitive: CertifiedPolynomialSurfaceFluxPrimitive,
        requestedCurveWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        guard !parameterCurves.isEmpty,
              requestedCurveWidth.isFinite,
              requestedCurveWidth > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                residual: requestedCurveWidth,
                tolerance: tolerance,
                message: "Polynomial B-spline volume requires a finite positive per-curve enclosure."
            )
        }
        let integrator = CertifiedAnalyticPcurveFluxIntegrator()
        var rawFlux = TrimmedAnalyticSurfaceVolumeEvaluator.Interval.exact(0.0)
        var areaBounds = SurfaceParameterAreaBounds.zero
        for curve in parameterCurves {
            guard let contribution = try integrator.polynomialBounds(
                for: curve,
                primitive: primitive,
                requestedWidth: requestedCurveWidth,
                tolerance: tolerance
            ) else {
                return nil
            }
            rawFlux = rawFlux + contribution
            areaBounds = areaBounds.adding(
                try SurfaceParameterCurveAreaIntegrator().bounds(
                    for: curve,
                    uShift: 0.0,
                    requestedWidth: max(tolerance.relative, Double.ulpOfOne * 256.0),
                    tolerance: tolerance
                )
            )
        }
        let traversalNormalized: TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        if areaBounds.lower > 0.0 {
            traversalNormalized = rawFlux
        } else if areaBounds.upper < 0.0 {
            traversalNormalized = -rawFlux
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: areaBounds.minimumAbsoluteValue,
                tolerance: tolerance,
                message: "Polynomial B-spline volume could not certify loop orientation."
            )
        }
        let roleNormalized = role == .outer
            ? traversalNormalized
            : -traversalNormalized
        return OutwardInterval(
            lower: roleNormalized.lower,
            upper: roleNormalized.upper
        )
    }

    private func axisAlignedPlanarContribution(
        face: Face,
        surface: BSplineSurface3D,
        model: BRepModel,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> OutwardInterval? {
        guard let plane = try AxisAlignedPlane(
            surface: surface,
            tolerance: tolerance
        ) else {
            return nil
        }
        if plane.coordinate == plane.coordinate(of: reference) {
            return .exact(0.0)
        }
        var orientedArea = OutwardInterval.exact(0.0)
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  !loop.coedges.isEmpty else {
                throw TopologyError.missingReference(
                    "Axis-aligned planar volume references a missing or empty loop."
                )
            }
            var points: [Point3D] = []
            points.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      let start = model.vertices[
                          coedge.orientation == .forward
                              ? edge.startVertexID
                              : edge.endVertexID
                      ]?.point,
                      let end = model.vertices[
                          coedge.orientation == .forward
                              ? edge.endVertexID
                              : edge.startVertexID
                      ]?.point else {
                    throw TopologyError.missingReference(
                        "Axis-aligned planar volume references missing edge geometry."
                    )
                }
                guard curveIsCertifiedStraight(
                    curve,
                    start: start,
                    end: end
                ), plane.coordinate(of: start) == plane.coordinate,
                   plane.coordinate(of: end) == plane.coordinate else {
                    return nil
                }
                points.append(start)
            }
            var twiceArea = OutwardInterval.exact(0.0)
            for index in points.indices {
                let current = plane.projected(points[index])
                let next = plane.projected(points[(index + 1) % points.count])
                twiceArea = twiceArea
                    + OutwardInterval.exact(current.first)
                        * OutwardInterval.exact(next.second)
                    - OutwardInterval.exact(next.first)
                        * OutwardInterval.exact(current.second)
            }
            let signedArea = twiceArea / OutwardInterval.exact(2.0)
            let absoluteArea: OutwardInterval
            if signedArea.lower > 0.0 {
                absoluteArea = signedArea
            } else if signedArea.upper < 0.0 {
                absoluteArea = -signedArea
            } else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: min(abs(signedArea.lower), abs(signedArea.upper)),
                    tolerance: tolerance,
                    message: "Axis-aligned planar volume could not certify loop orientation."
                )
            }
            orientedArea = orientedArea
                + (loop.role == .outer ? absoluteArea : -absoluteArea)
        }
        let offset = OutwardInterval.exact(plane.coordinate)
            - OutwardInterval.exact(plane.coordinate(of: reference))
        let orientation = OutwardInterval.exact(plane.normalSign)
        return offset * orientation * orientedArea / OutwardInterval.exact(3.0)
    }

    private func curveIsCertifiedStraight(
        _ curve: Curve3D,
        start: Point3D,
        end: Point3D
    ) -> Bool {
        switch curve {
        case .line, .analytic(.line):
            return true
        case let .bSpline(spline):
            let changingAxes = CoordinateAxis.allCases.filter {
                $0.coordinate(of: start) != $0.coordinate(of: end)
            }
            guard changingAxes.count == 1 else {
                return false
            }
            let fixedAxes = CoordinateAxis.allCases.filter {
                $0 != changingAxes[0]
            }
            return fixedAxes.allSatisfy { axis in
                let coordinate = axis.coordinate(of: start)
                return axis.coordinate(of: end) == coordinate
                    && spline.controlPoints.allSatisfy {
                        axis.coordinate(of: $0) == coordinate
                    }
            }
        case .circle, .analytic, .implicit, .surfaceLift,
             .certifiedIntersection:
            return false
        }
    }

    private enum CoordinateAxis: CaseIterable {
        case x
        case y
        case z

        func coordinate(of point: Point3D) -> Double {
            switch self {
            case .x: point.x
            case .y: point.y
            case .z: point.z
            }
        }
    }

    private struct AxisAlignedPlane {
        let axis: CoordinateAxis
        let coordinate: Double
        let normalSign: Double

        init?(
            surface: BSplineSurface3D,
            tolerance: ModelingTolerance
        ) throws {
            guard let bottomLeft = surface.controlPoints.first?.first,
                  let bottomRight = surface.controlPoints.first?.last,
                  let topLeft = surface.controlPoints.last?.first else {
                return nil
            }
            for candidate in CoordinateAxis.allCases {
                let value = candidate.coordinate(of: bottomLeft)
                guard surface.controlPoints.allSatisfy({ row in
                    row.allSatisfy { candidate.coordinate(of: $0) == value }
                }) else {
                    continue
                }
                let minimumArea = tolerance.distance * tolerance.distance
                let sign = try RobustPredicates.orientation2D(
                    Self.projected(bottomRight, axis: candidate),
                    Self.projected(topLeft, axis: candidate),
                    relativeTo: Self.projected(bottomLeft, axis: candidate),
                    determinantTolerance: minimumArea
                )
                guard sign == .positive || sign == .negative else {
                    continue
                }
                axis = candidate
                coordinate = value
                normalSign = sign == .positive ? 1.0 : -1.0
                return
            }
            return nil
        }

        func projected(_ point: Point3D) -> (first: Double, second: Double) {
            switch axis {
            case .x: (point.y, point.z)
            case .y: (point.z, point.x)
            case .z: (point.x, point.y)
            }
        }

        func coordinate(of point: Point3D) -> Double {
            axis.coordinate(of: point)
        }

        var projection: CertifiedRationalBezierSurfaceFluxIntegrator.AxisAlignedProjection {
            switch axis {
            case .x: .normalX
            case .y: .normalY
            case .z: .normalZ
            }
        }

        private static func projected(
            _ point: Point3D,
            axis: CoordinateAxis
        ) -> Point2D {
            switch axis {
            case .x: Point2D(x: point.y, y: point.z)
            case .y: Point2D(x: point.z, y: point.x)
            case .z: Point2D(x: point.x, y: point.y)
            }
        }
    }

    private func referencePoint(
        for shell: Shell,
        in model: BRepModel
    ) throws -> Point3D {
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Parametric volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Parametric volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let point = model.vertices[edge.startVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "Parametric volume references a missing boundary vertex."
                        )
                    }
                    return point
                }
            }
        }
        throw TopologyError.openShell(shell.id)
    }

    private func coedgeCount(
        of shell: Shell,
        in model: BRepModel
    ) throws -> Int {
        var count = 0
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Parametric volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Parametric volume references a missing loop."
                    )
                }
                count += loop.coedges.count
            }
        }
        return count
    }

    private func characteristicLength(
        of shell: Shell,
        in model: BRepModel,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximumLength = tolerance.distance
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Parametric volume references missing face geometry."
                )
            }
            if case let .bSpline(spline) = surface {
                for point in spline.controlPoints.flatMap({ $0 }) {
                    maximumLength = max(maximumLength, (point - reference).length)
                }
            }
        }
        return max(maximumLength, 1.0)
    }

    private func volumeTolerance(
        characteristicLength: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            tolerance.distance * characteristicLength * characteristicLength * 0.0625,
            characteristicLength * characteristicLength * characteristicLength * 1.0e-13
        )
    }

    private struct PolynomialBezierPatch {
        var x: BernsteinPolynomial2D
        var y: BernsteinPolynomial2D
        var z: BernsteinPolynomial2D

        init?(
            surface: BSplineSurface3D,
            tolerance: ModelingTolerance
        ) throws {
            guard surface.uDegree >= 1,
                  surface.vDegree >= 1,
                  surface.uControlPointCount == surface.uDegree + 1,
                  surface.vControlPointCount == surface.vDegree + 1,
                  Self.isSingleBezierKnotVector(
                      surface.uKnots,
                      degree: surface.uDegree
                  ),
                  Self.isSingleBezierKnotVector(
                      surface.vKnots,
                      degree: surface.vDegree
                  ),
                  let firstWeight = surface.weights.first?.first,
                  surface.weights.flatMap({ $0 }).allSatisfy({ $0 == firstWeight }) else {
                return nil
            }
            guard firstWeight.isFinite, firstWeight > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(firstWeight)
            }
            x = BernsteinPolynomial2D(surface.controlPoints.map { row in
                row.map { OutwardInterval.exact($0.x) }
            })
            y = BernsteinPolynomial2D(surface.controlPoints.map { row in
                row.map { OutwardInterval.exact($0.y) }
            })
            z = BernsteinPolynomial2D(surface.controlPoints.map { row in
                row.map { OutwardInterval.exact($0.z) }
            })
        }

        func trimmed(
            uLower: Double,
            uUpper: Double,
            vLower: Double,
            vUpper: Double,
            sourceUDomain: ParameterDomain,
            sourceVDomain: ParameterDomain,
            tolerance: ModelingTolerance
        ) throws -> PolynomialBezierPatch {
            guard case let .closed(sourceULower, sourceUUpper) = sourceUDomain,
                  case let .closed(sourceVLower, sourceVUpper) = sourceVDomain else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Polynomial B-spline volume requires closed parameter domains."
                )
            }
            let parameterScale = max(
                1.0,
                abs(sourceULower),
                abs(sourceUUpper),
                abs(sourceVLower),
                abs(sourceVUpper)
            )
            let parameterTolerance = max(
                tolerance.relative * parameterScale,
                Double.ulpOfOne * parameterScale * 256.0
            )
            guard uLower >= sourceULower - parameterTolerance,
                  uUpper <= sourceUUpper + parameterTolerance,
                  vLower >= sourceVLower - parameterTolerance,
                  vUpper <= sourceVUpper + parameterTolerance,
                  uUpper - uLower > parameterTolerance,
                  vUpper - vLower > parameterTolerance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rectangular pcurve trim lies outside its polynomial B-spline domain."
                )
            }
            let normalizedU = try Self.normalizedBounds(
                lower: uLower,
                upper: uUpper,
                domainLower: sourceULower,
                domainUpper: sourceUUpper,
                tolerance: tolerance
            )
            let normalizedV = try Self.normalizedBounds(
                lower: vLower,
                upper: vUpper,
                domainLower: sourceVLower,
                domainUpper: sourceVUpper,
                tolerance: tolerance
            )
            return PolynomialBezierPatch(
                x: x.trimmed(u: normalizedU, v: normalizedV),
                y: y.trimmed(u: normalizedU, v: normalizedV),
                z: z.trimmed(u: normalizedU, v: normalizedV)
            )
        }

        func fluxIntegral(
            reference: Point3D,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> OutwardInterval {
            try fluxPolynomial(
                reference: reference,
                budget: &budget,
                tolerance: tolerance
            ).integral()
        }

        func fluxPrimitive(
            reference: Point3D,
            uDomain: ParameterDomain,
            vDomain: ParameterDomain,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> CertifiedPolynomialSurfaceFluxPrimitive {
            let flux = try fluxPolynomial(
                reference: reference,
                budget: &budget,
                tolerance: tolerance
            )
            let denominator = OutwardInterval.exact(Double(flux.uDegree + 1))
            let primitive = flux.coefficients.map { row in
                var result = [OutwardInterval.exact(0.0)]
                result.reserveCapacity(row.count + 1)
                for coefficient in row {
                    result.append(result[result.count - 1] + coefficient / denominator)
                }
                return result.map {
                    TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
                        lower: $0.lower,
                        upper: $0.upper
                    )
                }
            }
            return CertifiedPolynomialSurfaceFluxPrimitive(
                coefficients: primitive,
                uDomain: uDomain,
                vDomain: vDomain
            )
        }

        private func fluxPolynomial(
            reference: Point3D,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> BernsteinPolynomial2D {
            let tangentU = PolynomialVector3(
                x: x.derivativeU(),
                y: y.derivativeU(),
                z: z.derivativeU()
            )
            let tangentV = PolynomialVector3(
                x: x.derivativeV(),
                y: y.derivativeV(),
                z: z.derivativeV()
            )
            let areaVector = try tangentU.cross(
                tangentV,
                budget: &budget,
                tolerance: tolerance
            )
            let relativePosition = PolynomialVector3(
                x: x.subtracting(constant: reference.x),
                y: y.subtracting(constant: reference.y),
                z: z.subtracting(constant: reference.z)
            )
            let flux = try relativePosition.dot(
                areaVector,
                budget: &budget,
                tolerance: tolerance
            ).scaled(by: OutwardInterval.exact(1.0) / OutwardInterval.exact(3.0))
            return flux
        }

        private init(
            x: BernsteinPolynomial2D,
            y: BernsteinPolynomial2D,
            z: BernsteinPolynomial2D
        ) {
            self.x = x
            self.y = y
            self.z = z
        }

        private static func isSingleBezierKnotVector(
            _ knots: [Double],
            degree: Int
        ) -> Bool {
            guard knots.count == 2 * (degree + 1),
                  let lower = knots.first,
                  let upper = knots.last,
                  upper > lower else {
                return false
            }
            return knots.prefix(degree + 1).allSatisfy { $0 == lower }
                && knots.suffix(degree + 1).allSatisfy { $0 == upper }
        }

        private static func normalizedBounds(
            lower: Double,
            upper: Double,
            domainLower: Double,
            domainUpper: Double,
            tolerance: ModelingTolerance
        ) throws -> ClosedIntervalPair {
            let domainSpan = OutwardInterval.exact(domainUpper)
                - OutwardInterval.exact(domainLower)
            guard domainSpan.lower > 0.0 else {
                throw GeometryError.invalidDistance(domainUpper - domainLower)
            }
            let normalizedLower = lower == domainLower
                ? OutwardInterval.exact(0.0)
                : (OutwardInterval.exact(lower) - OutwardInterval.exact(domainLower))
                    / domainSpan
            let normalizedUpper = upper == domainUpper
                ? OutwardInterval.exact(1.0)
                : (OutwardInterval.exact(upper) - OutwardInterval.exact(domainLower))
                    / domainSpan
            let clampedLower = normalizedLower.intersection(
                OutwardInterval(lower: 0.0, upper: 1.0)
            )
            let clampedUpper = normalizedUpper.intersection(
                OutwardInterval(lower: 0.0, upper: 1.0)
            )
            guard let clampedLower,
                  let clampedUpper,
                  clampedUpper.upper > clampedLower.lower else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Polynomial B-spline trim normalization produced an empty interval."
                )
            }
            return ClosedIntervalPair(lower: clampedLower, upper: clampedUpper)
        }
    }

    private struct ClosedIntervalPair {
        let lower: OutwardInterval
        let upper: OutwardInterval
    }

    private struct PolynomialVector3 {
        let x: BernsteinPolynomial2D
        let y: BernsteinPolynomial2D
        let z: BernsteinPolynomial2D

        func cross(
            _ other: PolynomialVector3,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> PolynomialVector3 {
            PolynomialVector3(
                x: try y.multiplied(
                    by: other.z,
                    budget: &budget,
                    tolerance: tolerance
                ).subtracting(
                    z.multiplied(
                        by: other.y,
                        budget: &budget,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                y: try z.multiplied(
                    by: other.x,
                    budget: &budget,
                    tolerance: tolerance
                ).subtracting(
                    x.multiplied(
                        by: other.z,
                        budget: &budget,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                ),
                z: try x.multiplied(
                    by: other.y,
                    budget: &budget,
                    tolerance: tolerance
                ).subtracting(
                    y.multiplied(
                        by: other.x,
                        budget: &budget,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                )
            )
        }

        func dot(
            _ other: PolynomialVector3,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> BernsteinPolynomial2D {
            let first = try x.multiplied(
                by: other.x,
                budget: &budget,
                tolerance: tolerance
            )
            let second = try y.multiplied(
                by: other.y,
                budget: &budget,
                tolerance: tolerance
            )
            let third = try z.multiplied(
                by: other.z,
                budget: &budget,
                tolerance: tolerance
            )
            return try first.adding(
                second,
                tolerance: tolerance
            ).adding(
                third,
                tolerance: tolerance
            )
        }
    }

    private struct BernsteinPolynomial2D {
        let coefficients: [[OutwardInterval]]

        var uDegree: Int {
            (coefficients.first?.count ?? 1) - 1
        }

        var vDegree: Int {
            coefficients.count - 1
        }

        init(_ coefficients: [[OutwardInterval]]) {
            self.coefficients = coefficients
        }

        func derivativeU() -> BernsteinPolynomial2D {
            BernsteinPolynomial2D(coefficients.map { row in
                (0..<uDegree).map { index in
                    (row[index + 1] - row[index]) * OutwardInterval.exact(Double(uDegree))
                }
            })
        }

        func derivativeV() -> BernsteinPolynomial2D {
            BernsteinPolynomial2D((0..<vDegree).map { rowIndex in
                coefficients[rowIndex].indices.map { columnIndex in
                    (coefficients[rowIndex + 1][columnIndex]
                        - coefficients[rowIndex][columnIndex])
                        * OutwardInterval.exact(Double(vDegree))
                }
            })
        }

        func subtracting(constant: Double) -> BernsteinPolynomial2D {
            let interval = OutwardInterval.exact(constant)
            return BernsteinPolynomial2D(coefficients.map { row in
                row.map { $0 - interval }
            })
        }

        func scaled(by scale: OutwardInterval) -> BernsteinPolynomial2D {
            BernsteinPolynomial2D(coefficients.map { row in
                row.map { $0 * scale }
            })
        }

        func multiplied(
            by other: BernsteinPolynomial2D,
            budget: inout CoefficientBudget,
            tolerance: ModelingTolerance
        ) throws -> BernsteinPolynomial2D {
            let outputUDegree = uDegree + other.uDegree
            let outputVDegree = vDegree + other.vDegree
            try budget.consume(
                (outputUDegree + 1) * (outputVDegree + 1),
                tolerance: tolerance
            )
            var output = Array(
                repeating: Array(
                    repeating: OutwardInterval.exact(0.0),
                    count: outputUDegree + 1
                ),
                count: outputVDegree + 1
            )
            for outputV in 0...outputVDegree {
                let firstVLower = max(0, outputV - other.vDegree)
                let firstVUpper = min(vDegree, outputV)
                for outputU in 0...outputUDegree {
                    let firstULower = max(0, outputU - other.uDegree)
                    let firstUUpper = min(uDegree, outputU)
                    var coefficient = OutwardInterval.exact(0.0)
                    for firstV in firstVLower...firstVUpper {
                        let secondV = outputV - firstV
                        let vWeight = Self.productWeight(
                            firstDegree: vDegree,
                            firstIndex: firstV,
                            secondDegree: other.vDegree,
                            secondIndex: secondV
                        )
                        for firstU in firstULower...firstUUpper {
                            let secondU = outputU - firstU
                            let uWeight = Self.productWeight(
                                firstDegree: uDegree,
                                firstIndex: firstU,
                                secondDegree: other.uDegree,
                                secondIndex: secondU
                            )
                            coefficient = coefficient
                                + coefficients[firstV][firstU]
                                * other.coefficients[secondV][secondU]
                                * uWeight * vWeight
                        }
                    }
                    output[outputV][outputU] = coefficient
                }
            }
            return BernsteinPolynomial2D(output)
        }

        func integral() -> OutwardInterval {
            var total = OutwardInterval.exact(0.0)
            for coefficient in coefficients.flatMap({ $0 }) {
                total = total + coefficient
            }
            let denominator = OutwardInterval.exact(
                Double((uDegree + 1) * (vDegree + 1))
            )
            return total / denominator
        }

        func trimmed(
            u: ClosedIntervalPair,
            v: ClosedIntervalPair
        ) -> BernsteinPolynomial2D {
            let uTrimmed = Self.trimLines(
                coefficients,
                lower: u.lower,
                upper: u.upper
            )
            let transposed = Self.transpose(uTrimmed)
            let vTrimmed = Self.trimLines(
                transposed,
                lower: v.lower,
                upper: v.upper
            )
            return BernsteinPolynomial2D(Self.transpose(vTrimmed))
        }

        func adding(
            _ other: BernsteinPolynomial2D,
            tolerance: ModelingTolerance
        ) throws -> BernsteinPolynomial2D {
            try validateMatchingDegree(other, tolerance: tolerance)
            return BernsteinPolynomial2D(coefficients.indices.map { row in
                coefficients[row].indices.map { column in
                    coefficients[row][column] + other.coefficients[row][column]
                }
            })
        }

        func subtracting(
            _ other: BernsteinPolynomial2D,
            tolerance: ModelingTolerance
        ) throws -> BernsteinPolynomial2D {
            try validateMatchingDegree(other, tolerance: tolerance)
            return BernsteinPolynomial2D(coefficients.indices.map { row in
                coefficients[row].indices.map { column in
                    coefficients[row][column] - other.coefficients[row][column]
                }
            })
        }

        private func validateMatchingDegree(
            _ other: BernsteinPolynomial2D,
            tolerance: ModelingTolerance
        ) throws {
            guard uDegree == other.uDegree,
                  vDegree == other.vDegree else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Certified volume polynomial addition requires matching bidegrees."
                )
            }
        }

        private static func trimLines(
            _ lines: [[OutwardInterval]],
            lower: OutwardInterval,
            upper: OutwardInterval
        ) -> [[OutwardInterval]] {
            lines.map { line in
                var current = line
                if lower.upper > 0.0 {
                    current = split(current, parameter: lower).upper
                }
                if upper.lower < 1.0 {
                    let denominator = OutwardInterval.exact(1.0) - lower
                    let localUpper = (upper - lower) / denominator
                    current = split(current, parameter: localUpper).lower
                }
                return current
            }
        }

        private static func split(
            _ values: [OutwardInterval],
            parameter: OutwardInterval
        ) -> (lower: [OutwardInterval], upper: [OutwardInterval]) {
            let complement = OutwardInterval.exact(1.0) - parameter
            var levels = [values]
            while let previous = levels.last, previous.count > 1 {
                levels.append((0..<(previous.count - 1)).map { index in
                    previous[index] * complement + previous[index + 1] * parameter
                })
            }
            return (
                levels.map { $0[0] },
                levels.reversed().map { $0[$0.count - 1] }
            )
        }

        private static func transpose(
            _ values: [[OutwardInterval]]
        ) -> [[OutwardInterval]] {
            guard let first = values.first else { return [] }
            return first.indices.map { column in
                values.indices.map { row in values[row][column] }
            }
        }

        private static func productWeight(
            firstDegree: Int,
            firstIndex: Int,
            secondDegree: Int,
            secondIndex: Int
        ) -> OutwardInterval {
            binomial(firstDegree, firstIndex)
                * binomial(secondDegree, secondIndex)
                / binomial(firstDegree + secondDegree, firstIndex + secondIndex)
        }

        private static func binomial(_ n: Int, _ k: Int) -> OutwardInterval {
            let reducedK = min(k, n - k)
            guard reducedK > 0 else { return .exact(1.0) }
            var value = OutwardInterval.exact(1.0)
            for index in 1...reducedK {
                value = value * OutwardInterval.exact(Double(n - reducedK + index))
                    / OutwardInterval.exact(Double(index))
            }
            return value
        }
    }

    private struct CoefficientBudget {
        let limit: Int
        var consumed = 0

        mutating func consume(
            _ count: Int,
            tolerance: ModelingTolerance
        ) throws {
            guard count >= 0,
                  consumed <= limit - count else {
                throw KernelError(
                    phase: .topology,
                    code: .resourceLimitExceeded,
                    residual: Double(consumed + max(count, 0)),
                    tolerance: tolerance,
                    message: "Certified polynomial B-spline volume exhausted its coefficient-operation budget."
                )
            }
            consumed += count
        }
    }

    private struct OutwardInterval: Sendable, Hashable {
        let lower: Double
        let upper: Double

        init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func exact(_ value: Double) -> OutwardInterval {
            OutwardInterval(lower: value, upper: value)
        }

        func intersection(_ other: OutwardInterval) -> OutwardInterval? {
            let lower = max(lower, other.lower)
            let upper = min(upper, other.upper)
            guard lower <= upper else { return nil }
            return OutwardInterval(lower: lower, upper: upper)
        }

        static prefix func - (value: OutwardInterval) -> OutwardInterval {
            OutwardInterval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
        }

        static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            lhs + (-rhs)
        }

        static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return OutwardInterval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
                // A zero-containing divisor produces an unbounded enclosure;
                // final volume validation reports it as a typed failure.
                return OutwardInterval(lower: -.infinity, upper: .infinity)
            }
            return lhs * OutwardInterval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
        }
    }
}
