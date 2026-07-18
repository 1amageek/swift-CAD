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
