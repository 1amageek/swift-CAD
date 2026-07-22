import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel

enum ExactExchangeAdvancedAnalyticFixture {
    static func tiltedCylindricalSheet() throws -> BRepModel {
        let axis = try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        let radius = 0.020
        let height = 0.010
        let uLower = 0.0
        let uUpper = Double.pi * 0.5
        let surface = Surface3D.cylinder(Cylinder3D(origin: .origin, axis: axis, radius: radius))
        let p00 = try surface.point(u: uLower, v: 0.0, tolerance: .standard)
        let p10 = try surface.point(u: uUpper, v: 0.0, tolerance: .standard)
        let p11 = try surface.point(u: uUpper, v: height, tolerance: .standard)
        let p01 = try surface.point(u: uLower, v: height, tolerance: .standard)
        let upperCenter = Point3D.origin + axis * height
        let edges = [
            BRepSewingEdge(
                stableID: "exact:tilted-cylinder:lower",
                curve: .circle(Circle3D(center: .origin, normal: axis, radius: radius)),
                startParameter: uLower,
                endParameter: uUpper,
                startPoint: p00,
                endPoint: p10,
                surfaceParameterCurve: .constantV(v: 0.0, uStart: uLower, uEnd: uUpper)
            ),
            BRepSewingEdge(
                stableID: "exact:tilted-cylinder:right",
                curve: .line(Line3D(origin: p10, direction: axis)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: p10,
                endPoint: p11,
                surfaceParameterCurve: .constantU(u: uUpper, vStart: 0.0, vEnd: height)
            ),
            BRepSewingEdge(
                stableID: "exact:tilted-cylinder:upper",
                curve: .circle(Circle3D(center: upperCenter, normal: axis, radius: radius)),
                startParameter: uUpper,
                endParameter: uLower,
                startPoint: p11,
                endPoint: p01,
                surfaceParameterCurve: .constantV(v: height, uStart: uUpper, uEnd: uLower)
            ),
            BRepSewingEdge(
                stableID: "exact:tilted-cylinder:left",
                curve: .line(Line3D(origin: p01, direction: -axis)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: p01,
                endPoint: p00,
                surfaceParameterCurve: .constantU(u: uLower, vStart: height, vEnd: 0.0)
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:tilted-cylinder", edges: edges)
    }

    static func ellipticalSheet() throws -> BRepModel {
        let majorRadius = 0.040
        let minorRadius = 0.020
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let start = Point3D(x: majorRadius, y: 0.0, z: 0.0)
        let end = Point3D(x: -majorRadius, y: 0.0, z: 0.0)
        let ellipse = AnalyticCurve3D.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        )
        let edges = [
            BRepSewingEdge(
                stableID: "exact:ellipse:arc",
                curve: .analytic(ellipse),
                startParameter: 0.0,
                endParameter: Double.pi,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .harmonic(
                    center: Point2D(x: 0.0, y: 0.0),
                    cosine: Point2D(x: majorRadius, y: 0.0),
                    sine: Point2D(x: 0.0, y: minorRadius),
                    startParameter: 0.0,
                    endParameter: Double.pi
                )
            ),
            BRepSewingEdge(
                stableID: "exact:ellipse:chord",
                curve: .analytic(.line(origin: end, direction: .unitX)),
                startParameter: 0.0,
                endParameter: majorRadius * 2.0,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .constantV(
                    v: 0.0,
                    uStart: -majorRadius,
                    uEnd: majorRadius
                )
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:ellipse", edges: edges)
    }

    static func hyperbolicSheet(reversed: Bool) throws -> BRepModel {
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: .origin,
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: 0.030,
            conjugateRadius: 0.015
        )))
        return try openConicSheet(
            curve: curve,
            lowerParameter: -0.8,
            upperParameter: 0.65,
            reversed: reversed,
            stableID: "exact:hyperbola:\(reversed)"
        )
    }

    static func parabolicSheet(reversed: Bool) throws -> BRepModel {
        let curve = Curve3D.analytic(.parabola(Parabola3D(
            vertex: .origin,
            normal: .unitZ,
            axis: .unitX,
            focalLength: 0.020
        )))
        return try openConicSheet(
            curve: curve,
            lowerParameter: -0.025,
            upperParameter: 0.035,
            reversed: reversed,
            stableID: "exact:parabola:\(reversed)"
        )
    }

    static func clockwiseEllipticalSheet() throws -> BRepModel {
        let majorRadius = 0.040
        let minorRadius = 0.020
        let startParameter = 0.0
        let endParameter = Double.pi
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let ellipse = AnalyticCurve3D.ellipse(
            center: .origin,
            normal: -.unitZ,
            majorAxis: .unitX,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        )
        let exactEllipse = Curve3D.analytic(ellipse)
        let start = try exactEllipse.point(at: startParameter, tolerance: .standard)
        let end = try exactEllipse.point(at: endParameter, tolerance: .standard)
        let chord = start - end
        let edges = [
            BRepSewingEdge(
                stableID: "exact:clockwise-ellipse:arc",
                curve: exactEllipse,
                startParameter: startParameter,
                endParameter: endParameter,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .harmonic(
                    center: Point2D(x: 0.0, y: 0.0),
                    cosine: Point2D(x: majorRadius, y: 0.0),
                    sine: Point2D(x: 0.0, y: -minorRadius),
                    startParameter: startParameter,
                    endParameter: endParameter
                )
            ),
            BRepSewingEdge(
                stableID: "exact:clockwise-ellipse:chord",
                curve: .analytic(.line(
                    origin: end,
                    direction: try chord.normalized(tolerance: ModelingTolerance.standard.distance)
                )),
                startParameter: 0.0,
                endParameter: chord.length,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .constantV(
                    v: 0.0,
                    uStart: -majorRadius,
                    uEnd: majorRadius
                )
            ),
        ]
        return try sheet(
            surface: surface,
            stableID: "exact:clockwise-ellipse",
            edges: edges
        )
    }

    static func analyticArcSheet(reversed: Bool) throws -> BRepModel {
        let normal = try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        let radius = 0.030
        let arcStart = 0.25
        let arcEnd = 2.60
        let lowerTrim = 0.45
        let upperTrim = 2.20
        let startParameter = reversed ? upperTrim : lowerTrim
        let endParameter = reversed ? lowerTrim : upperTrim
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: normal))
        let arc = AnalyticCurve3D.arc(
            center: .origin,
            normal: normal,
            radius: radius,
            startAngle: arcStart,
            endAngle: arcEnd
        )
        let exactArc = Curve3D.analytic(arc)
        let basisCircle = Curve3D.analytic(.circle(
            center: .origin,
            normal: normal,
            radius: radius
        ))
        let centerUV = try surface.parameterProjection(of: .origin, tolerance: .standard)
        let cosineUV = try surface.parameterProjection(
            of: basisCircle.point(at: 0.0, tolerance: .standard),
            tolerance: .standard
        )
        let sineUV = try surface.parameterProjection(
            of: basisCircle.point(at: 0.5 * Double.pi, tolerance: .standard),
            tolerance: .standard
        )
        let start = try exactArc.point(at: startParameter, tolerance: .standard)
        let end = try exactArc.point(at: endParameter, tolerance: .standard)
        let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
        let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
        let chord = start - end
        let edges = [
            BRepSewingEdge(
                stableID: "exact:analytic-arc:\(reversed):arc",
                curve: exactArc,
                startParameter: startParameter,
                endParameter: endParameter,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .harmonic(
                    center: Point2D(x: centerUV.u, y: centerUV.v),
                    cosine: Point2D(
                        x: cosineUV.u - centerUV.u,
                        y: cosineUV.v - centerUV.v
                    ),
                    sine: Point2D(
                        x: sineUV.u - centerUV.u,
                        y: sineUV.v - centerUV.v
                    ),
                    startParameter: startParameter,
                    endParameter: endParameter
                )
            ),
            BRepSewingEdge(
                stableID: "exact:analytic-arc:\(reversed):chord",
                curve: .analytic(.line(
                    origin: end,
                    direction: try chord.normalized(tolerance: ModelingTolerance.standard.distance)
                )),
                startParameter: 0.0,
                endParameter: chord.length,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .affine(
                    origin: Point2D(x: endUV.u, y: endUV.v),
                    direction: Point2D(
                        x: startUV.u - endUV.u,
                        y: startUV.v - endUV.v
                    ),
                    startParameter: 0.0,
                    endParameter: 1.0
                )
            ),
        ]
        return try sheet(
            surface: surface,
            stableID: "exact:analytic-arc:\(reversed)",
            edges: edges
        )
    }

    static func seamCrossingEllipticalSheet() throws -> BRepModel {
        let majorRadius = 0.040
        let minorRadius = 0.020
        let startParameter = 2.0 * Double.pi - 0.7
        let endParameter = 2.0 * Double.pi + 0.6
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let ellipse = AnalyticCurve3D.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        )
        let exactEllipse = Curve3D.analytic(ellipse)
        let start = try exactEllipse.point(at: startParameter, tolerance: .standard)
        let end = try exactEllipse.point(at: endParameter, tolerance: .standard)
        let chord = start - end
        let edges = [
            BRepSewingEdge(
                stableID: "exact:seam-ellipse:arc",
                curve: exactEllipse,
                startParameter: startParameter,
                endParameter: endParameter,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .harmonic(
                    center: Point2D(x: 0.0, y: 0.0),
                    cosine: Point2D(x: majorRadius, y: 0.0),
                    sine: Point2D(x: 0.0, y: minorRadius),
                    startParameter: startParameter,
                    endParameter: endParameter
                )
            ),
            BRepSewingEdge(
                stableID: "exact:seam-ellipse:chord",
                curve: .analytic(.line(
                    origin: end,
                    direction: try chord.normalized(tolerance: ModelingTolerance.standard.distance)
                )),
                startParameter: 0.0,
                endParameter: chord.length,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: end.x, v: end.y),
                    SurfaceParameter(u: start.x, v: start.y),
                ])
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:seam-ellipse", edges: edges)
    }

    static func conicalSheet() throws -> BRepModel {
        let halfAngle = Double.pi / 6.0
        let uLower = 0.0
        let uUpper = Double.pi * 0.5
        let vLower = 0.020
        let vUpper = 0.040
        let analytic = AnalyticSurface3D.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        )
        let surface = Surface3D.analytic(analytic)
        let lowerCenter = Point3D(x: 0.0, y: 0.0, z: vLower * cos(halfAngle))
        let upperCenter = Point3D(x: 0.0, y: 0.0, z: vUpper * cos(halfAngle))
        let p00 = try surface.point(u: uLower, v: vLower, tolerance: .standard)
        let p10 = try surface.point(u: uUpper, v: vLower, tolerance: .standard)
        let p11 = try surface.point(u: uUpper, v: vUpper, tolerance: .standard)
        let p01 = try surface.point(u: uLower, v: vUpper, tolerance: .standard)
        let lowerCircle = AnalyticCurve3D.circle(
            center: lowerCenter,
            normal: .unitZ,
            radius: vLower * sin(halfAngle)
        )
        let upperCircle = AnalyticCurve3D.circle(
            center: upperCenter,
            normal: .unitZ,
            radius: vUpper * sin(halfAngle)
        )
        let rightDirection = try (p11 - p10).normalized(tolerance: ModelingTolerance.standard.distance)
        let leftDirection = try (p00 - p01).normalized(tolerance: ModelingTolerance.standard.distance)
        let edges = [
            try circleEdge(
                stableID: "exact:cone:lower",
                curve: lowerCircle,
                startPoint: p00,
                endPoint: p10,
                pcurve: .constantV(v: vLower, uStart: uLower, uEnd: uUpper)
            ),
            BRepSewingEdge(
                stableID: "exact:cone:right",
                curve: .analytic(.line(origin: p10, direction: rightDirection)),
                startParameter: 0.0,
                endParameter: (p11 - p10).length,
                startPoint: p10,
                endPoint: p11,
                surfaceParameterCurve: .constantU(u: uUpper, vStart: vLower, vEnd: vUpper)
            ),
            try circleEdge(
                stableID: "exact:cone:upper",
                curve: upperCircle,
                startPoint: p11,
                endPoint: p01,
                pcurve: .constantV(v: vUpper, uStart: uUpper, uEnd: uLower)
            ),
            BRepSewingEdge(
                stableID: "exact:cone:left",
                curve: .analytic(.line(origin: p01, direction: leftDirection)),
                startParameter: 0.0,
                endParameter: (p00 - p01).length,
                startPoint: p01,
                endPoint: p00,
                surfaceParameterCurve: .constantU(u: uLower, vStart: vUpper, vEnd: vLower)
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:cone", edges: edges)
    }

    static func coneHyperbolicSheet(reversed: Bool) throws -> BRepModel {
        let halfAngle = Double.pi * 0.25
        let offset = 0.020
        let lowerParameter = -0.5
        let upperParameter = 0.5
        let startParameter = reversed ? upperParameter : lowerParameter
        let endParameter = reversed ? lowerParameter : upperParameter
        let surface = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: Point3D(x: offset, y: 0.0, z: 0.0),
            normal: .unitX,
            transverseAxis: .unitZ,
            transverseRadius: offset,
            conjugateRadius: offset
        )))
        let projected = try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: startParameter,
            endParameter: endParameter,
            tolerance: .standard
        )
        let start = try curve.point(at: startParameter, tolerance: .standard)
        let end = try curve.point(at: endParameter, tolerance: .standard)
        let startUV = try projected.parameter(
            atNormalizedFraction: 0.0,
            tolerance: .standard
        )
        let endUV = try projected.parameter(
            atNormalizedFraction: 1.0,
            tolerance: .standard
        )
        guard abs(startUV.v - endUV.v) <= ModelingTolerance.standard.distance else {
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                residual: abs(startUV.v - endUV.v),
                tolerance: .standard,
                message: "The cone hyperbola fixture endpoints must share one exact cone latitude."
            )
        }
        let latitude = 0.5 * (startUV.v + endUV.v)
        let closingCurve = Curve3D.analytic(.circle(
            center: Point3D(
                x: 0.0,
                y: 0.0,
                z: latitude * cos(halfAngle)
            ),
            normal: .unitZ,
            radius: latitude * sin(halfAngle)
        ))
        return try sheet(
            surface: surface,
            stableID: "exact:cone-hyperbola:\(reversed)",
            edges: [
                BRepSewingEdge(
                    stableID: "exact:cone-hyperbola:\(reversed):conic",
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: .projectedAnalytic(projected)
                ),
                BRepSewingEdge(
                    stableID: "exact:cone-hyperbola:\(reversed):latitude",
                    curve: closingCurve,
                    startParameter: endUV.u,
                    endParameter: startUV.u,
                    startPoint: end,
                    endPoint: start,
                    surfaceParameterCurve: .constantV(
                        v: latitude,
                        uStart: endUV.u,
                        uEnd: startUV.u
                    )
                ),
            ]
        )
    }

    static func sphericalSheet() throws -> BRepModel {
        let radius = 0.030
        let uLower = 0.0
        let uUpper = Double.pi * 0.5
        let vLower = -Double.pi / 6.0
        let vUpper = Double.pi / 6.0
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: radius))
        let p00 = try surface.point(u: uLower, v: vLower, tolerance: .standard)
        let p10 = try surface.point(u: uUpper, v: vLower, tolerance: .standard)
        let p11 = try surface.point(u: uUpper, v: vUpper, tolerance: .standard)
        let p01 = try surface.point(u: uLower, v: vUpper, tolerance: .standard)
        let lowerCircle = AnalyticCurve3D.circle(
            center: Point3D(x: 0.0, y: 0.0, z: radius * sin(vLower)),
            normal: .unitZ,
            radius: radius * cos(vLower)
        )
        let upperCircle = AnalyticCurve3D.circle(
            center: Point3D(x: 0.0, y: 0.0, z: radius * sin(vUpper)),
            normal: .unitZ,
            radius: radius * cos(vUpper)
        )
        let rightCircle = AnalyticCurve3D.circle(center: .origin, normal: -.unitY, radius: radius)
        let leftCircle = AnalyticCurve3D.circle(center: .origin, normal: -.unitX, radius: radius)
        let edges = [
            try circleEdge(
                stableID: "exact:sphere:lower",
                curve: lowerCircle,
                startPoint: p00,
                endPoint: p10,
                pcurve: .constantV(v: vLower, uStart: uLower, uEnd: uUpper)
            ),
            try circleEdge(
                stableID: "exact:sphere:right",
                curve: rightCircle,
                startPoint: p10,
                endPoint: p11,
                pcurve: .constantU(u: uUpper, vStart: vLower, vEnd: vUpper)
            ),
            try circleEdge(
                stableID: "exact:sphere:upper",
                curve: upperCircle,
                startPoint: p11,
                endPoint: p01,
                pcurve: .constantV(v: vUpper, uStart: uUpper, uEnd: uLower)
            ),
            try circleEdge(
                stableID: "exact:sphere:left",
                curve: leftCircle,
                startPoint: p01,
                endPoint: p00,
                pcurve: .constantU(u: uLower, vStart: vUpper, vEnd: vLower)
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:sphere", edges: edges)
    }

    static func greatCircleHemisphere(reversed: Bool) throws -> BRepModel {
        let radius = 0.030
        let normal = try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: radius))
        let curve = Curve3D.analytic(.circle(
            center: .origin,
            normal: normal,
            radius: radius
        ))
        let cosine = try (curve.point(at: 0.0, tolerance: .standard) - Point3D.origin)
            .normalized(tolerance: ModelingTolerance.standard.distance)
        let sine = try (curve.point(at: 0.5 * Double.pi, tolerance: .standard) - Point3D.origin)
            .normalized(tolerance: ModelingTolerance.standard.distance)
        let direction = reversed ? -1.0 : 1.0
        let parameters = [
            (0.0, direction * Double.pi),
            (direction * Double.pi, direction * 2.0 * Double.pi),
        ]
        let edges = try parameters.enumerated().map { index, interval in
            BRepSewingEdge(
                stableID: "exact:great-circle:\(reversed):\(index)",
                curve: curve,
                startParameter: interval.0,
                endParameter: interval.1,
                startPoint: try curve.point(at: interval.0, tolerance: .standard),
                endPoint: try curve.point(at: interval.1, tolerance: .standard),
                surfaceParameterCurve: .sphericalGreatCircle(
                    cosine: cosine,
                    sine: sine,
                    startParameter: interval.0,
                    endParameter: interval.1
                )
            )
        }
        return try sheet(
            surface: surface,
            stableID: "exact:great-circle:\(reversed)",
            edges: edges
        )
    }

    static func toroidalSheet() throws -> BRepModel {
        let majorRadius = 0.040
        let minorRadius = 0.010
        let uLower = 0.0
        let uUpper = Double.pi * 0.5
        let vLower = -Double.pi / 4.0
        let vUpper = Double.pi / 4.0
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        ))
        let p00 = try surface.point(u: uLower, v: vLower, tolerance: .standard)
        let p10 = try surface.point(u: uUpper, v: vLower, tolerance: .standard)
        let p11 = try surface.point(u: uUpper, v: vUpper, tolerance: .standard)
        let p01 = try surface.point(u: uLower, v: vUpper, tolerance: .standard)
        let lowerCircle = AnalyticCurve3D.circle(
            center: Point3D(x: 0.0, y: 0.0, z: minorRadius * sin(vLower)),
            normal: .unitZ,
            radius: majorRadius + minorRadius * cos(vLower)
        )
        let upperCircle = AnalyticCurve3D.circle(
            center: Point3D(x: 0.0, y: 0.0, z: minorRadius * sin(vUpper)),
            normal: .unitZ,
            radius: majorRadius + minorRadius * cos(vUpper)
        )
        let rightCircle = AnalyticCurve3D.circle(
            center: Point3D(x: -majorRadius, y: 0.0, z: 0.0),
            normal: -.unitY,
            radius: minorRadius
        )
        let leftCircle = AnalyticCurve3D.circle(
            center: Point3D(x: 0.0, y: majorRadius, z: 0.0),
            normal: -.unitX,
            radius: minorRadius
        )
        let edges = [
            try circleEdge(
                stableID: "exact:torus:lower",
                curve: lowerCircle,
                startPoint: p00,
                endPoint: p10,
                pcurve: .constantV(v: vLower, uStart: uLower, uEnd: uUpper)
            ),
            try circleEdge(
                stableID: "exact:torus:right",
                curve: rightCircle,
                startPoint: p10,
                endPoint: p11,
                pcurve: .constantU(u: uUpper, vStart: vLower, vEnd: vUpper)
            ),
            try circleEdge(
                stableID: "exact:torus:upper",
                curve: upperCircle,
                startPoint: p11,
                endPoint: p01,
                pcurve: .constantV(v: vUpper, uStart: uUpper, uEnd: uLower)
            ),
            try circleEdge(
                stableID: "exact:torus:left",
                curve: leftCircle,
                startPoint: p01,
                endPoint: p00,
                pcurve: .constantU(u: uLower, vStart: vUpper, vEnd: vLower)
            ),
        ]
        return try sheet(surface: surface, stableID: "exact:torus", edges: edges)
    }

    static func planeTorusIntersectionSheet(reversed: Bool) throws -> BRepModel {
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        let plane = Surface3D.analytic(.plane(origin: .origin, normal: normal))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 0.030,
            minorRadius: 0.010
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: plane,
            second: torus,
            tolerance: .standard
        )
        let exactIntersections: [CertifiedAnalyticAnalyticIntersectionCurve] = intersections.compactMap {
            intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(curve) = intersection,
                  case let .analyticAnalytic(exact) = curve.truth else {
                return nil
            }
            return exact
        }
        guard let exactIntersection = exactIntersections.first else {
            throw KernelError(
                phase: .exchange,
                code: .intersectionFailure,
                tolerance: .standard,
                message: "The plane-torus exchange fixture produced no certified intersection component."
            )
        }
        let curve = exactIntersection.curve
        let direction = reversed ? -1.0 : 1.0
        let intervals = [
            (0.0, direction * Double.pi),
            (direction * Double.pi, direction * 2.0 * Double.pi),
        ]
        let edges = try intervals.enumerated().map { index, interval in
            BRepSewingEdge(
                stableID: "exact:plane-torus:\(reversed):\(index)",
                curve: curve,
                startParameter: interval.0,
                endParameter: interval.1,
                startPoint: try curve.point(at: interval.0, tolerance: .standard),
                endPoint: try curve.point(at: interval.1, tolerance: .standard),
                surfaceParameterCurve: .certifiedAnalyticPair(
                    try CertifiedAnalyticPairSurfaceParameterCurve(
                        intersection: exactIntersection,
                        role: .first,
                        startFraction: interval.0 / (2.0 * Double.pi),
                        endFraction: interval.1 / (2.0 * Double.pi),
                        tolerance: .standard
                    )
                )
            )
        }
        return try sheet(
            surface: plane,
            stableID: "exact:plane-torus:\(reversed)",
            edges: edges
        )
    }

    static func implicitBSplineIntersectionSheet(reversed: Bool) throws -> BRepModel {
        let horizontal = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.040, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.040, z: 0.0),
                    Point3D(x: 0.040, y: 0.040, z: 0.0),
                ],
            ]
        )
        let vertical = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.020, z: -0.020),
                    Point3D(x: 0.040, y: 0.020, z: -0.020),
                ],
                [
                    Point3D(x: 0.0, y: 0.020, z: 0.020),
                    Point3D(x: 0.040, y: 0.020, z: 0.020),
                ],
            ],
            weights: [
                [1.0, 1.25],
                [0.75, 1.0],
            ]
        )
        let surface = Surface3D.bSpline(horizontal)
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: surface,
            second: .bSpline(vertical),
            tolerance: .standard
        )
        let exactIntersections = intersections.compactMap { intersection -> SurfaceSurfaceIntersectionCurve? in
            guard case let .curve(curve) = intersection,
                  case .implicit = curve.truth else {
                return nil
            }
            return curve
        }
        guard let exactIntersection = exactIntersections.first else {
            throw KernelError(
                phase: .exchange,
                code: .intersectionFailure,
                tolerance: .standard,
                message: "The implicit exchange fixture produced no certified intersection component."
            )
        }
        let curve = exactIntersection.curve
        let startParameter = reversed ? 1.0 : 0.0
        let endParameter = reversed ? 0.0 : 1.0
        let parameterCurve = reversed
            ? try exactIntersection.firstSurfaceParameterCurve.reversed(tolerance: .standard)
            : exactIntersection.firstSurfaceParameterCurve
        let start = try curve.point(at: startParameter, tolerance: .standard)
        let end = try curve.point(at: endParameter, tolerance: .standard)
        let startUV = try parameterCurve.startParameter(tolerance: .standard)
        let endUV = try parameterCurve.endParameter(tolerance: .standard)
        let deltaU = endUV.u - startUV.u
        let deltaV = endUV.v - startUV.v
        let parameterLength = hypot(deltaU, deltaV)
        guard parameterLength > ModelingTolerance.standard.relative else {
            throw KernelError(
                phase: .exchange,
                code: .singularGeometry,
                tolerance: .standard,
                message: "The implicit exchange fixture produced a degenerate parameter-space edge."
            )
        }
        let candidateOffsets = [
            Point2D(x: -deltaV / parameterLength * 0.20, y: deltaU / parameterLength * 0.20),
            Point2D(x: deltaV / parameterLength * 0.20, y: -deltaU / parameterLength * 0.20),
        ]
        guard let offset = candidateOffsets.first(where: { offset in
            let values = [
                startUV.u + offset.x,
                startUV.v + offset.y,
                endUV.u + offset.x,
                endUV.v + offset.y,
            ]
            return values.allSatisfy { $0 >= 0.0 && $0 <= 1.0 }
        }) else {
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                tolerance: .standard,
                message: "The implicit exchange fixture could not form an interior offset loop."
            )
        }
        let offsetEndUV = SurfaceParameter(u: endUV.u + offset.x, v: endUV.v + offset.y)
        let offsetStartUV = SurfaceParameter(u: startUV.u + offset.x, v: startUV.v + offset.y)
        let offsetEnd = try surface.point(
            u: offsetEndUV.u,
            v: offsetEndUV.v,
            tolerance: .standard
        )
        let offsetStart = try surface.point(
            u: offsetStartUV.u,
            v: offsetStartUV.v,
            tolerance: .standard
        )
        return try sheet(
            surface: surface,
            stableID: "exact:implicit:\(reversed)",
            edges: [
                BRepSewingEdge(
                    stableID: "exact:implicit:\(reversed):intersection",
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: parameterCurve
                ),
                try lineEdge(
                    stableID: "exact:implicit:\(reversed):end",
                    start: end,
                    end: offsetEnd,
                    startUV: endUV,
                    endUV: offsetEndUV
                ),
                try lineEdge(
                    stableID: "exact:implicit:\(reversed):offset",
                    start: offsetEnd,
                    end: offsetStart,
                    startUV: offsetEndUV,
                    endUV: offsetStartUV
                ),
                try lineEdge(
                    stableID: "exact:implicit:\(reversed):start",
                    start: offsetStart,
                    end: start,
                    startUV: offsetStartUV,
                    endUV: startUV
                ),
            ]
        )
    }

    static func analyticBSplineIntersectionSheet(reversed: Bool) throws -> BRepModel {
        let radius = 0.030
        let analyticSurface = Surface3D.analytic(.sphere(
            center: .origin,
            radius: radius
        ))
        let boundedSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -0.045, y: -0.045, z: 0.0),
                    Point3D(x: 0.045, y: -0.045, z: 0.0),
                ],
                [
                    Point3D(x: -0.045, y: 0.045, z: 0.0),
                    Point3D(x: 0.045, y: 0.045, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 1.25],
                [0.8, 1.0],
            ]
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: analyticSurface,
            second: boundedSurface,
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 4,
                maximumIterations: 48,
                maximumSeedCount: 1_024
            ),
            tolerance: .standard
        )
        let exactIntersections = intersections.compactMap { intersection -> SurfaceSurfaceIntersectionCurve? in
            guard case let .curve(curve) = intersection,
                  case .analyticBSpline = curve.truth else {
                return nil
            }
            return curve
        }
        guard exactIntersections.count == 1,
              let exactIntersection = exactIntersections.first else {
            throw KernelError(
                phase: .exchange,
                code: .intersectionFailure,
                residual: Double(exactIntersections.count),
                tolerance: .standard,
                message: "The analytic B-spline exchange fixture requires one certified component."
            )
        }
        let curve = exactIntersection.curve
        let sourcePcurve = exactIntersection.firstSurfaceParameterCurve
        let intervals = reversed
            ? [(1.0, 0.5), (0.5, 0.0)]
            : [(0.0, 0.5), (0.5, 1.0)]
        let edges = try intervals.enumerated().map { index, interval in
            let lower = min(interval.0, interval.1)
            let upper = max(interval.0, interval.1)
            let forwardPcurve = try sourcePcurve.trimmed(
                from: lower,
                to: upper,
                curveDomain: curve.parameterDomain,
                tolerance: .standard
            )
            return BRepSewingEdge(
                stableID: "exact:analytic-implicit:\(reversed):\(index)",
                curve: curve,
                startParameter: interval.0,
                endParameter: interval.1,
                startPoint: try curve.point(at: interval.0, tolerance: .standard),
                endPoint: try curve.point(at: interval.1, tolerance: .standard),
                surfaceParameterCurve: reversed
                    ? try forwardPcurve.reversed(tolerance: .standard)
                    : forwardPcurve
            )
        }
        return try sheet(
            surface: analyticSurface,
            stableID: "exact:analytic-implicit:\(reversed)",
            edges: edges
        )
    }

    static func surfaceLiftSheet(reversed: Bool) throws -> BRepModel {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.040, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.040, z: 0.0),
                    Point3D(x: 0.040, y: 0.040, z: 0.0),
                ],
            ]
        ))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.1, y: 0.2),
                Point2D(x: 0.5, y: 0.8),
                Point2D(x: 0.9, y: 0.2),
            ],
            weights: [1.0, 1.4, 1.0]
        ))
        let lift = SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: parameterCurve
        )
        try lift.validate(tolerance: .standard)
        let curve = Curve3D.surfaceLift(lift)
        let startParameter = reversed ? 1.0 : 0.0
        let endParameter = reversed ? 0.0 : 1.0
        let start = try curve.point(at: startParameter, tolerance: .standard)
        let end = try curve.point(at: endParameter, tolerance: .standard)
        let directedPcurve = reversed
            ? try parameterCurve.reversed(tolerance: .standard)
            : parameterCurve
        let startUV = try directedPcurve.startParameter(tolerance: .standard)
        let endUV = try directedPcurve.endParameter(tolerance: .standard)
        return try sheet(
            surface: surface,
            stableID: "exact:surface-lift:\(reversed)",
            edges: [
                BRepSewingEdge(
                    stableID: "exact:surface-lift:\(reversed):curve",
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: directedPcurve
                ),
                try lineEdge(
                    stableID: "exact:surface-lift:\(reversed):closure",
                    start: end,
                    end: start,
                    startUV: endUV,
                    endUV: startUV
                ),
            ]
        )
    }

    private static func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        startUV: SurfaceParameter,
        endUV: SurfaceParameter
    ) throws -> BRepSewingEdge {
        let delta = end - start
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(
                origin: start,
                direction: try delta.normalized(
                    tolerance: ModelingTolerance.standard.distance
                )
            )),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .affine(
                origin: Point2D(x: startUV.u, y: startUV.v),
                direction: Point2D(x: endUV.u - startUV.u, y: endUV.v - startUV.v),
                startParameter: 0.0,
                endParameter: 1.0
            )
        )
    }

    private static func circleEdge(
        stableID: String,
        curve: AnalyticCurve3D,
        startPoint: Point3D,
        endPoint: Point3D,
        pcurve: SurfaceParameterCurve
    ) throws -> BRepSewingEdge {
        let exactCurve = Curve3D.analytic(curve)
        let startParameter = try exactCurve.parameterProjection(
            of: startPoint,
            tolerance: .standard
        ).parameter
        let endParameter = try exactCurve.parameterProjection(
            of: endPoint,
            tolerance: .standard
        ).parameter
        return BRepSewingEdge(
            stableID: stableID,
            curve: exactCurve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: pcurve
        )
    }

    private static func openConicSheet(
        curve: Curve3D,
        lowerParameter: Double,
        upperParameter: Double,
        reversed: Bool,
        stableID: String
    ) throws -> BRepModel {
        let startParameter = reversed ? upperParameter : lowerParameter
        let endParameter = reversed ? lowerParameter : upperParameter
        let start = try curve.point(at: startParameter, tolerance: .standard)
        let end = try curve.point(at: endParameter, tolerance: .standard)
        let chord = start - end
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let pcurve = SurfaceParameterCurve.projectedAnalytic(
            try ProjectedAnalyticSurfaceParameterCurve(
                curve: curve,
                surface: surface,
                startParameter: startParameter,
                endParameter: endParameter,
                tolerance: .standard
            )
        )
        return try sheet(
            surface: surface,
            stableID: stableID,
            edges: [
                BRepSewingEdge(
                    stableID: "\(stableID):conic",
                    curve: curve,
                    startParameter: startParameter,
                    endParameter: endParameter,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: pcurve
                ),
                BRepSewingEdge(
                    stableID: "\(stableID):chord",
                    curve: .analytic(.line(
                        origin: end,
                        direction: try chord.normalized(
                            tolerance: ModelingTolerance.standard.distance
                        )
                    )),
                    startParameter: 0.0,
                    endParameter: chord.length,
                    startPoint: end,
                    endPoint: start,
                    surfaceParameterCurve: .affine(
                        origin: Point2D(x: end.x, y: end.y),
                        direction: Point2D(x: start.x - end.x, y: start.y - end.y),
                        startParameter: 0.0,
                        endParameter: 1.0
                    )
                ),
            ]
        )
    }

    private static func sheet(
        surface: Surface3D,
        stableID: String,
        edges: [BRepSewingEdge]
    ) throws -> BRepModel {
        try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "\(stableID):shell",
                patches: [BRepSewingFacePatch(
                    stableID: "\(stableID):face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "\(stableID):outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }
}
