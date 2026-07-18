import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel

enum ExactExchangeAnalyticFixture {
    static func cylindricalSheet() throws -> BRepModel {
        let radius = 0.020
        let height = 0.010
        let uEnd = Double.pi * 0.5
        let cylinder = Cylinder3D(origin: .origin, axis: .unitZ, radius: radius)
        let surface = Surface3D.cylinder(cylinder)
        let bottomStart = try surface.point(u: 0.0, v: 0.0, tolerance: .standard)
        let bottomEnd = try surface.point(u: uEnd, v: 0.0, tolerance: .standard)
        let topEnd = try surface.point(u: uEnd, v: height, tolerance: .standard)
        let topStart = try surface.point(u: 0.0, v: height, tolerance: .standard)
        let bottomCircle = Circle3D(center: .origin, normal: .unitZ, radius: radius)
        let topCircle = Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: height),
            normal: .unitZ,
            radius: radius
        )
        let edges = [
            BRepSewingEdge(
                stableID: "exact:cylinder:bottom",
                curve: .circle(bottomCircle),
                startParameter: 0.0,
                endParameter: uEnd,
                startPoint: bottomStart,
                endPoint: bottomEnd,
                surfaceParameterCurve: .constantV(v: 0.0, uStart: 0.0, uEnd: uEnd)
            ),
            BRepSewingEdge(
                stableID: "exact:cylinder:right",
                curve: .line(Line3D(origin: bottomEnd, direction: .unitZ)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: bottomEnd,
                endPoint: topEnd,
                surfaceParameterCurve: .constantU(u: uEnd, vStart: 0.0, vEnd: height)
            ),
            BRepSewingEdge(
                stableID: "exact:cylinder:top",
                curve: .circle(topCircle),
                startParameter: uEnd,
                endParameter: 0.0,
                startPoint: topEnd,
                endPoint: topStart,
                surfaceParameterCurve: .constantV(v: height, uStart: uEnd, uEnd: 0.0)
            ),
            BRepSewingEdge(
                stableID: "exact:cylinder:left",
                curve: .line(Line3D(origin: topStart, direction: -.unitZ)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: topStart,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(u: 0.0, vStart: height, vEnd: 0.0)
            ),
        ]
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exact:cylinder:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exact:cylinder:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exact:cylinder:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }

    static func seamCrossingCylindricalSheet() throws -> BRepModel {
        let radius = 0.020
        let height = 0.010
        let uStart = 2.0 * Double.pi - 0.7
        let uEnd = 2.0 * Double.pi + 0.6
        let cylinder = Cylinder3D(origin: .origin, axis: .unitZ, radius: radius)
        let surface = Surface3D.cylinder(cylinder)
        let bottomStart = try surface.point(u: uStart, v: 0.0, tolerance: .standard)
        let bottomEnd = try surface.point(u: uEnd, v: 0.0, tolerance: .standard)
        let topEnd = try surface.point(u: uEnd, v: height, tolerance: .standard)
        let topStart = try surface.point(u: uStart, v: height, tolerance: .standard)
        let bottomCircle = Circle3D(center: .origin, normal: .unitZ, radius: radius)
        let topCircle = Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: height),
            normal: .unitZ,
            radius: radius
        )
        let edges = [
            BRepSewingEdge(
                stableID: "exact:seam-cylinder:bottom",
                curve: .circle(bottomCircle),
                startParameter: uStart,
                endParameter: uEnd,
                startPoint: bottomStart,
                endPoint: bottomEnd,
                surfaceParameterCurve: .constantV(v: 0.0, uStart: uStart, uEnd: uEnd)
            ),
            BRepSewingEdge(
                stableID: "exact:seam-cylinder:right",
                curve: .line(Line3D(origin: bottomEnd, direction: .unitZ)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: bottomEnd,
                endPoint: topEnd,
                surfaceParameterCurve: .constantU(u: uEnd, vStart: 0.0, vEnd: height)
            ),
            BRepSewingEdge(
                stableID: "exact:seam-cylinder:top",
                curve: .circle(topCircle),
                startParameter: uEnd,
                endParameter: uStart,
                startPoint: topEnd,
                endPoint: topStart,
                surfaceParameterCurve: .constantV(v: height, uStart: uEnd, uEnd: uStart)
            ),
            BRepSewingEdge(
                stableID: "exact:seam-cylinder:left",
                curve: .line(Line3D(origin: topStart, direction: -.unitZ)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: topStart,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(u: uStart, vStart: height, vEnd: 0.0)
            ),
        ]
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exact:seam-cylinder:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exact:seam-cylinder:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exact:seam-cylinder:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }
}
