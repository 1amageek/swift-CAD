import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct BRepFaceBoundingBoxBuilder: FaceSpatialBoundsResolving, Sendable {
    private let parameterBoundsResolver: any FaceParameterBoundsResolving
    private let surfaceDifferentialEncloser: any SurfaceDifferentialEnclosing

    private struct ProceduralBoundsCell: Sendable {
        let parameters: SurfaceParameterBox
        let depth: Int
    }

    init(
        parameterBoundsResolver: any FaceParameterBoundsResolving =
            DefaultFaceParameterBoundsResolver(),
        surfaceDifferentialEncloser: any SurfaceDifferentialEnclosing =
            DefaultSurfaceDifferentialEncloser()
    ) {
        self.parameterBoundsResolver = parameterBoundsResolver
        self.surfaceDifferentialEncloser = surfaceDifferentialEncloser
    }

    func bounds(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        try tolerance.validate()
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Face bounds reference a missing face or support surface."
            )
        }
        let boundaryPoints = try supportPoints(
            for: face,
            in: model,
            tolerance: tolerance
        )
        guard boundaryPoints.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A bounded face requires at least one certified boundary point."
            )
        }
        switch surface {
        case .plane, .analytic(.plane):
            return try BoundingBox3D(points: boundaryPoints)
        case let .cylinder(cylinder):
            return try cylinderBounds(
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: cylinder.radius,
                boundaryPoints: boundaryPoints,
                tolerance: tolerance
            )
        case let .analytic(.cylinder(origin, axis, radius)):
            return try cylinderBounds(
                origin: origin,
                axis: axis,
                radius: radius,
                boundaryPoints: boundaryPoints,
                tolerance: tolerance
            )
        case let .analytic(.cone(apex, axis, halfAngle)):
            return try coneBounds(
                apex: apex,
                axis: axis,
                halfAngle: halfAngle,
                boundaryPoints: boundaryPoints,
                tolerance: tolerance
            )
        case let .analytic(.sphere(center, radius)):
            return try radialBounds(center: center, radius: radius)
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            if let parameterBounds = try rectangularTorusParameterBounds(
                for: face,
                in: model,
                tolerance: tolerance
            ) {
                return try torusBounds(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    uBounds: parameterBounds.u,
                    vBounds: parameterBounds.v,
                    tolerance: tolerance
                )
            }
            return try radialBounds(center: center, radius: majorRadius + minorRadius)
        case let .bSpline(surface):
            return try BoundingBox3D(points: surface.controlPoints.flatMap { $0 })
        case .procedural:
            let parameters = try parameterBoundsResolver.bounds(
                for: faceID,
                in: model,
                tolerance: tolerance
            )
            return try proceduralBounds(
                surface: surface,
                parameters: parameters,
                tolerance: tolerance
            )
        }
    }

    private func proceduralBounds(
        surface: Surface3D,
        parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        var minimum = Point3D(
            x: .infinity,
            y: .infinity,
            z: .infinity
        )
        var maximum = Point3D(
            x: -.infinity,
            y: -.infinity,
            z: -.infinity
        )
        var remainingCells = 1_048_576
        var stack = [ProceduralBoundsCell(parameters: parameters, depth: 0)]
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Procedural face bounds exhausted the certified cell budget."
                )
            }
            remainingCells -= 1
            do {
                let enclosure = try surfaceDifferentialEncloser.enclosure(
                    of: surface,
                    over: cell.parameters,
                    tolerance: tolerance
                ).position
                minimum = Point3D(
                    x: min(minimum.x, enclosure.x.lower),
                    y: min(minimum.y, enclosure.y.lower),
                    z: min(minimum.z, enclosure.z.lower)
                )
                maximum = Point3D(
                    x: max(maximum.x, enclosure.x.upper),
                    y: max(maximum.y, enclosure.y.upper),
                    z: max(maximum.z, enclosure.z.upper)
                )
            } catch let error as KernelError where error.code == .singularSystem {
                guard cell.depth < 32 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Procedural face bounds could not certify a regular parameter cell."
                    )
                }
                stack.append(contentsOf: try subdivided(
                    cell.parameters,
                    depth: cell.depth + 1
                ).reversed())
            }
        }
        guard minimum.x.isFinite,
              minimum.y.isFinite,
              minimum.z.isFinite,
              maximum.x.isFinite,
              maximum.y.isFinite,
              maximum.z.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Procedural face bounds did not produce a finite enclosure."
            )
        }
        return try BoundingBox3D(minimum: minimum, maximum: maximum)
    }

    private func subdivided(
        _ parameters: SurfaceParameterBox,
        depth: Int
    ) throws -> [ProceduralBoundsCell] {
        let middleU = parameters.u.midpoint
        let middleV = parameters.v.midpoint
        guard middleU > parameters.u.lower,
              middleU < parameters.u.upper,
              middleV > parameters.v.lower,
              middleV < parameters.v.upper else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Procedural face bounds reached the representable parameter resolution."
            )
        }
        let lowerU = try ScalarInterval(
            lower: parameters.u.lower,
            upper: middleU
        )
        let upperU = try ScalarInterval(
            lower: middleU,
            upper: parameters.u.upper
        )
        let lowerV = try ScalarInterval(
            lower: parameters.v.lower,
            upper: middleV
        )
        let upperV = try ScalarInterval(
            lower: middleV,
            upper: parameters.v.upper
        )
        return [
            ProceduralBoundsCell(
                parameters: SurfaceParameterBox(u: lowerU, v: lowerV),
                depth: depth
            ),
            ProceduralBoundsCell(
                parameters: SurfaceParameterBox(u: upperU, v: lowerV),
                depth: depth
            ),
            ProceduralBoundsCell(
                parameters: SurfaceParameterBox(u: lowerU, v: upperV),
                depth: depth
            ),
            ProceduralBoundsCell(
                parameters: SurfaceParameterBox(u: upperU, v: upperV),
                depth: depth
            ),
        ]
    }

    private func supportPoints(
        for face: Face,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        var points: [Point3D] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face bounds reference a missing loop."
                )
            }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID],
                      let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point,
                      let curve = model.geometry.curves[edge.curveID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Face bounds reference missing edge geometry."
                    )
                }
                points.append(contentsOf: [start, end])
                points.append(contentsOf: try curveSupportPoints(
                    curve,
                    trim: edge.trim,
                    tolerance: tolerance
                ))
            }
        }
        return points
    }

    private func curveSupportPoints(
        _ curve: Curve3D,
        trim: CurveTrim?,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        switch curve {
        case .line, .analytic(.line):
            return []
        case let .circle(circle):
            return try circularSupportPoints(
                center: circle.center,
                normal: circle.normal,
                radius: circle.radius,
                tolerance: tolerance
            )
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return try circularSupportPoints(
                center: center,
                normal: normal,
                radius: radius,
                tolerance: tolerance
            )
        case let .analytic(.ellipse(center, normal, majorAxis, majorRadius, minorRadius)):
            let unitNormal = try normal.normalized(tolerance: tolerance.distance)
            let unitMajor = try majorAxis.normalized(tolerance: tolerance.distance)
            let unitMinor = unitNormal.cross(unitMajor)
            let extent = Vector3D(
                x: hypot(unitMajor.x * majorRadius, unitMinor.x * minorRadius),
                y: hypot(unitMajor.y * majorRadius, unitMinor.y * minorRadius),
                z: hypot(unitMajor.z * majorRadius, unitMinor.z * minorRadius)
            )
            return [center + extent, center + (-extent)]
        case let .analytic(.hyperbola(curve)):
            guard let trim else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A bounded face edge on a hyperbola requires a finite trim."
                )
            }
            return try hyperbolaSupportPoints(
                curve,
                trim: trim,
                tolerance: tolerance
            )
        case let .analytic(.parabola(curve)):
            guard let trim else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A bounded face edge on a parabola requires a finite trim."
                )
            }
            return try parabolaSupportPoints(
                curve,
                trim: trim,
                tolerance: tolerance
            )
        case let .analytic(.planeTorus(curve)):
            let bounds = try curve.boundingBox(tolerance: tolerance)
            return [bounds.minimum, bounds.maximum]
        case let .bSpline(curve):
            return curve.controlPoints
        case let .implicit(curve):
            return curve.firstSurface.controlPoints.flatMap { $0 }
        case let .surfaceLift(curve):
            let interval: ScalarInterval
            if let trim {
                interval = try ScalarInterval(
                    lower: min(trim.startParameter, trim.endParameter),
                    upper: max(trim.startParameter, trim.endParameter)
                )
            } else {
                interval = try ScalarInterval(lower: 0.0, upper: 1.0)
            }
            let bounds = try curve.boundingBox(
                over: interval,
                tolerance: tolerance
            )
            return [bounds.minimum, bounds.maximum]
        case let .certifiedIntersection(curve):
            let bounds = try curve.boundingBox(tolerance: tolerance)
            return [bounds.minimum, bounds.maximum]
        case let .rigidImage(image):
            return try curveSupportPoints(
                image.source,
                trim: trim,
                tolerance: tolerance
            ).map(image.transform.applying(to:))
        case .affineImage:
            let interval: ScalarInterval
            if let trim {
                interval = try ScalarInterval(
                    lower: min(trim.startParameter, trim.endParameter),
                    upper: max(trim.startParameter, trim.endParameter)
                )
            } else {
                switch curve.parameterDomain {
                case let .closed(lower, upper):
                    interval = try ScalarInterval(lower: lower, upper: upper)
                case let .periodic(period):
                    interval = try ScalarInterval(lower: 0.0, upper: period)
                case .unbounded:
                    throw KernelError(
                        phase: .topology,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "A bounded face edge on an unbounded affine-image curve requires a finite trim."
                    )
                }
            }
            let enclosure = try DefaultCurvePositionEncloser().enclosure(
                of: curve,
                over: interval,
                tolerance: tolerance
            )
            return [
                Point3D(
                    x: enclosure.x.lower,
                    y: enclosure.y.lower,
                    z: enclosure.z.lower
                ),
                Point3D(
                    x: enclosure.x.upper,
                    y: enclosure.y.upper,
                    z: enclosure.z.upper
                ),
            ]
        }
    }

    private func hyperbolaSupportPoints(
        _ curve: Hyperbola3D,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let exactCurve = Curve3D.analytic(.hyperbola(curve))
        let lower = min(trim.startParameter, trim.endParameter)
        let upper = max(trim.startParameter, trim.endParameter)
        let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let first = curve.transverseAxis * curve.transverseRadius
        let second = conjugateAxis * curve.conjugateRadius
        var parameters = [lower, upper]
        for components in [
            (first.x, second.x),
            (first.y, second.y),
            (first.z, second.z),
        ] {
            guard abs(components.0) > Double.leastNonzeroMagnitude else {
                continue
            }
            let ratio = -components.1 / components.0
            guard ratio.isFinite, abs(ratio) < 1.0 else { continue }
            let parameter = atanh(ratio)
            if parameter > lower, parameter < upper {
                parameters.append(parameter)
            }
        }
        return try parameters.map {
            try exactCurve.point(at: $0, tolerance: tolerance)
        }
    }

    private func parabolaSupportPoints(
        _ curve: Parabola3D,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let exactCurve = Curve3D.analytic(.parabola(curve))
        let lower = min(trim.startParameter, trim.endParameter)
        let upper = max(trim.startParameter, trim.endParameter)
        let transverseAxis = try curve.normal.cross(curve.axis).normalized(
            tolerance: tolerance.distance
        )
        var parameters = [lower, upper]
        for components in [
            (transverseAxis.x, curve.axis.x),
            (transverseAxis.y, curve.axis.y),
            (transverseAxis.z, curve.axis.z),
        ] {
            guard abs(components.1) > Double.leastNonzeroMagnitude else {
                continue
            }
            let parameter = -2.0 * curve.focalLength * components.0 / components.1
            if parameter.isFinite, parameter > lower, parameter < upper {
                parameters.append(parameter)
            }
        }
        return try parameters.map {
            try exactCurve.point(at: $0, tolerance: tolerance)
        }
    }

    private func circularSupportPoints(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let unitNormal = try normal.normalized(tolerance: tolerance.distance)
        let extent = Vector3D(
            x: radius * sqrt(max(0.0, 1.0 - unitNormal.x * unitNormal.x)),
            y: radius * sqrt(max(0.0, 1.0 - unitNormal.y * unitNormal.y)),
            z: radius * sqrt(max(0.0, 1.0 - unitNormal.z * unitNormal.z))
        )
        return [center + extent, center + (-extent)]
    }

    private func rectangularTorusParameterBounds(
        for face: Face,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (u: ScalarInterval, v: ScalarInterval)? {
        var uValues: [Double] = []
        var vValues: [Double] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Torus face bounds reference a missing loop."
                )
            }
            for coedge in loop.coedges {
                guard let parameterCurve = coedge.surfaceParameterCurve else {
                    return nil
                }
                guard let values = rectangularBoundaryValues(parameterCurve) else {
                    return nil
                }
                uValues.append(contentsOf: values.u)
                vValues.append(contentsOf: values.v)
            }
        }
        guard let uLower = uValues.min(),
              let uUpper = uValues.max(),
              let vLower = vValues.min(),
              let vUpper = vValues.max(),
              uUpper - uLower > tolerance.angle,
              vUpper - vLower > tolerance.angle,
              uUpper - uLower <= 2.0 * Double.pi + tolerance.angle,
              vUpper - vLower <= 2.0 * Double.pi + tolerance.angle else {
            return nil
        }
        return (
            u: try ScalarInterval(lower: uLower, upper: uUpper),
            v: try ScalarInterval(lower: vLower, upper: vUpper)
        )
    }

    private func rectangularBoundaryValues(
        _ curve: SurfaceParameterCurve
    ) -> (u: [Double], v: [Double])? {
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return ([u], [vStart, vEnd])
        case let .constantV(v, uStart, uEnd):
            return ([uStart, uEnd], [v])
        case let .periodicTranslation(base, uShift, vShift):
            guard let values = rectangularBoundaryValues(base) else { return nil }
            return (
                values.u.map { $0 + uShift },
                values.v.map { $0 + vShift }
            )
        case let .sameParameterImage(image):
            return rectangularBoundaryValues(image.source)
        case .affine, .harmonic, .sphericalGreatCircle, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage:
            return nil
        }
    }

    private func torusBounds(
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        uBounds: ScalarInterval,
        vBounds: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let surface = AnalyticSurface3D.torus(
            center: center,
            axis: axis,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        )
        let outerRadius = majorRadius + minorRadius
        let radialU = try (
            surface.point(u: 0.0, v: 0.0, tolerance: tolerance) - center
        ).normalized(tolerance: tolerance.distance)
        let radialV = try (
            surface.point(u: Double.pi * 0.5, v: 0.0, tolerance: tolerance) - center
        ).normalized(tolerance: tolerance.distance)
        guard outerRadius > tolerance.distance else {
            throw GeometryError.invalidDistance(outerRadius)
        }
        let cosineV = harmonicBounds(
            cosine: 1.0,
            sine: 0.0,
            interval: vBounds
        )
        let sineV = harmonicBounds(
            cosine: 0.0,
            sine: 1.0,
            interval: vBounds
        )
        let radialScale = (
            lower: majorRadius + minorRadius * cosineV.lower,
            upper: majorRadius + minorRadius * cosineV.upper
        )

        let x = torusCoordinateBounds(
            center: center.x,
            radialU: radialU.x,
            radialV: radialV.x,
            axis: axis.x,
            minorRadius: minorRadius,
            uBounds: uBounds,
            radialScale: radialScale,
            sineV: sineV
        )
        let y = torusCoordinateBounds(
            center: center.y,
            radialU: radialU.y,
            radialV: radialV.y,
            axis: axis.y,
            minorRadius: minorRadius,
            uBounds: uBounds,
            radialScale: radialScale,
            sineV: sineV
        )
        let z = torusCoordinateBounds(
            center: center.z,
            radialU: radialU.z,
            radialV: radialV.z,
            axis: axis.z,
            minorRadius: minorRadius,
            uBounds: uBounds,
            radialScale: radialScale,
            sineV: sineV
        )
        return try BoundingBox3D(
            minimum: Point3D(x: x.lower, y: y.lower, z: z.lower),
            maximum: Point3D(x: x.upper, y: y.upper, z: z.upper)
        )
    }

    private func torusCoordinateBounds(
        center: Double,
        radialU: Double,
        radialV: Double,
        axis: Double,
        minorRadius: Double,
        uBounds: ScalarInterval,
        radialScale: (lower: Double, upper: Double),
        sineV: (lower: Double, upper: Double)
    ) -> (lower: Double, upper: Double) {
        let radial = harmonicBounds(
            cosine: radialU,
            sine: radialV,
            interval: uBounds
        )
        let radialProduct = productBounds(radial, radialScale)
        let axial = productBounds(
            (lower: axis * minorRadius, upper: axis * minorRadius),
            sineV
        )
        return (
            lower: center + radialProduct.lower + axial.lower,
            upper: center + radialProduct.upper + axial.upper
        )
    }

    private func harmonicBounds(
        cosine: Double,
        sine: Double,
        interval: ScalarInterval
    ) -> (lower: Double, upper: Double) {
        let amplitude = hypot(cosine, sine)
        guard amplitude > Double.ulpOfOne else {
            return (0.0, 0.0)
        }
        let period = 2.0 * Double.pi
        if interval.width >= period {
            return (-amplitude, amplitude)
        }
        let lowerValue = cosine * cos(interval.lower) + sine * sin(interval.lower)
        let upperValue = cosine * cos(interval.upper) + sine * sin(interval.upper)
        var minimum = min(lowerValue, upperValue)
        var maximum = max(lowerValue, upperValue)
        let maximumPhase = atan2(sine, cosine)
        if containsPeriodic(
            maximumPhase,
            interval: interval,
            period: period
        ) {
            maximum = amplitude
        }
        if containsPeriodic(
            maximumPhase + Double.pi,
            interval: interval,
            period: period
        ) {
            minimum = -amplitude
        }
        return (minimum, maximum)
    }

    private func containsPeriodic(
        _ value: Double,
        interval: ScalarInterval,
        period: Double
    ) -> Bool {
        let firstIndex = ceil((interval.lower - value) / period)
        let lastIndex = floor((interval.upper - value) / period)
        return firstIndex <= lastIndex
    }

    private func productBounds(
        _ first: (lower: Double, upper: Double),
        _ second: (lower: Double, upper: Double)
    ) -> (lower: Double, upper: Double) {
        let values = [
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ]
        return (values.min() ?? 0.0, values.max() ?? 0.0)
    }

    private func cylinderBounds(
        origin: Point3D,
        axis: Vector3D,
        radius: Double,
        boundaryPoints: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let unitAxis = try axis.normalized(tolerance: tolerance.distance)
        let parameters = boundaryPoints.map { ($0 - origin).dot(unitAxis) }
        guard let lower = parameters.min(), let upper = parameters.max() else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded cylinder face requires boundary points."
            )
        }
        let lowerCenter = origin + unitAxis * lower
        let upperCenter = origin + unitAxis * upper
        let radialExtent = Vector3D(
            x: radius * sqrt(max(0.0, 1.0 - unitAxis.x * unitAxis.x)),
            y: radius * sqrt(max(0.0, 1.0 - unitAxis.y * unitAxis.y)),
            z: radius * sqrt(max(0.0, 1.0 - unitAxis.z * unitAxis.z))
        )
        return try axialBounds(
            lowerCenter: lowerCenter,
            upperCenter: upperCenter,
            radialExtent: radialExtent
        )
    }

    private func coneBounds(
        apex: Point3D,
        axis: Vector3D,
        halfAngle: Double,
        boundaryPoints: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let unitAxis = try axis.normalized(tolerance: tolerance.distance)
        let parameters = boundaryPoints.map { ($0 - apex).dot(unitAxis) }
        guard let lower = parameters.min(), let upper = parameters.max() else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded cone face requires boundary points."
            )
        }
        let maximumRadius = max(abs(lower), abs(upper)) * abs(tan(halfAngle))
        let radialExtent = Vector3D(
            x: maximumRadius * sqrt(max(0.0, 1.0 - unitAxis.x * unitAxis.x)),
            y: maximumRadius * sqrt(max(0.0, 1.0 - unitAxis.y * unitAxis.y)),
            z: maximumRadius * sqrt(max(0.0, 1.0 - unitAxis.z * unitAxis.z))
        )
        return try axialBounds(
            lowerCenter: apex + unitAxis * lower,
            upperCenter: apex + unitAxis * upper,
            radialExtent: radialExtent
        )
    }

    private func axialBounds(
        lowerCenter: Point3D,
        upperCenter: Point3D,
        radialExtent: Vector3D
    ) throws -> BoundingBox3D {
        try BoundingBox3D(
            minimum: Point3D(
                x: min(lowerCenter.x, upperCenter.x) - radialExtent.x,
                y: min(lowerCenter.y, upperCenter.y) - radialExtent.y,
                z: min(lowerCenter.z, upperCenter.z) - radialExtent.z
            ),
            maximum: Point3D(
                x: max(lowerCenter.x, upperCenter.x) + radialExtent.x,
                y: max(lowerCenter.y, upperCenter.y) + radialExtent.y,
                z: max(lowerCenter.z, upperCenter.z) + radialExtent.z
            )
        )
    }

    private func radialBounds(
        center: Point3D,
        radius: Double
    ) throws -> BoundingBox3D {
        try BoundingBox3D(
            minimum: Point3D(
                x: center.x - radius,
                y: center.y - radius,
                z: center.z - radius
            ),
            maximum: Point3D(
                x: center.x + radius,
                y: center.y + radius,
                z: center.z + radius
            )
        )
    }
}
