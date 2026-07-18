import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel

enum ExactExchangeNURBSFixture {
    static func rationalPcurveSheet() throws -> BRepModel {
        let knots = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let weights = [1.0, 0.75, 1.0]
        let control2D = [
            Point2D(x: 0.040, y: 0.0),
            Point2D(x: 0.0, y: 0.030),
            Point2D(x: -0.040, y: 0.0),
        ]
        let control3D = control2D.map { Point3D(x: $0.x, y: $0.y, z: 0.0) }
        let curve2D = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: control2D,
            weights: weights
        )
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: control3D,
            weights: weights
        )
        let start = try curve3D.point(at: 0.0, tolerance: .standard)
        let end = try curve3D.point(at: 1.0, tolerance: .standard)
        let edges = [
            BRepSewingEdge(
                stableID: "exact:rational-pcurve:curve",
                curve: .bSpline(curve3D),
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .bSpline(curve2D)
            ),
            BRepSewingEdge(
                stableID: "exact:rational-pcurve:chord",
                curve: .line(Line3D(origin: end, direction: .unitX)),
                startParameter: 0.0,
                endParameter: 0.080,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .constantV(v: 0.0, uStart: -0.040, uEnd: 0.040)
            ),
        ]
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exact:rational-pcurve:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exact:rational-pcurve:face",
                    surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exact:rational-pcurve:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }

    static func partialRationalPcurveSheet(reversed: Bool) throws -> BRepModel {
        let knots = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let weights = [1.0, 0.75, 1.0]
        let control2D = [
            Point2D(x: 0.040, y: 0.0),
            Point2D(x: 0.0, y: 0.030),
            Point2D(x: -0.040, y: 0.0),
        ]
        let curve2D = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: control2D,
            weights: weights
        )
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: control2D.map { Point3D(x: $0.x, y: $0.y, z: 0.0) },
            weights: weights
        )
        let lower = 0.2
        let upper = 0.8
        let start = try curve3D.point(at: lower, tolerance: .standard)
        let end = try curve3D.point(at: upper, tolerance: .standard)
        let parameterStart = try curve2D.point(at: lower, tolerance: .standard)
        let parameterEnd = try curve2D.point(at: upper, tolerance: .standard)
        let chord = end - start
        let chordLength = chord.length
        let chordDirection = try (start - end).normalized(tolerance: ModelingTolerance.standard.distance)
        let edges = [
            BRepSewingEdge(
                stableID: "exact:partial-rational-pcurve:curve",
                curve: .bSpline(curve3D),
                startParameter: lower,
                endParameter: upper,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .bSpline(try curve2D.trimmed(
                    from: lower,
                    to: upper,
                    tolerance: .standard
                ))
            ),
            BRepSewingEdge(
                stableID: "exact:partial-rational-pcurve:chord",
                curve: .line(Line3D(origin: end, direction: chordDirection)),
                startParameter: 0.0,
                endParameter: chordLength,
                startPoint: end,
                endPoint: start,
                surfaceParameterCurve: .affine(
                    origin: parameterEnd,
                    direction: Point2D(
                        x: parameterStart.x - parameterEnd.x,
                        y: parameterStart.y - parameterEnd.y
                    ),
                    startParameter: 0.0,
                    endParameter: 1.0
                )
            ),
        ]
        var result = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exact:partial-rational-pcurve:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exact:partial-rational-pcurve:face",
                    surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exact:partial-rational-pcurve:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
        if reversed {
            result = try reversingBSplineEdges(in: result)
        }
        try result.validate(level: .exact, tolerance: .standard)
        return result
    }

    static func rationalSheet() throws -> BRepModel {
        let knots = [0.0, 0.0, 1.0, 1.0]
        let controlPoints = [
            [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 0.020, y: 0.0, z: 0.0)],
            [Point3D(x: 0.0, y: 0.010, z: 0.0), Point3D(x: 0.020, y: 0.010, z: 0.0)],
        ]
        let weights = [[1.0, 2.0], [2.0, 1.0]]
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: knots,
            vKnots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        let boundaries: [(
            controls: [Point3D],
            weights: [Double],
            pcurve: SurfaceParameterCurve
        )] = [
            ([controlPoints[0][0], controlPoints[0][1]], [weights[0][0], weights[0][1]],
             .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0)),
            ([controlPoints[0][1], controlPoints[1][1]], [weights[0][1], weights[1][1]],
             .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0)),
            ([controlPoints[1][1], controlPoints[1][0]], [weights[1][1], weights[1][0]],
             .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0)),
            ([controlPoints[1][0], controlPoints[0][0]], [weights[1][0], weights[0][0]],
             .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0)),
        ]
        let edges = try boundaries.enumerated().map { index, boundary in
            let curve = BSplineCurve3D(
                degree: 1,
                knots: knots,
                controlPoints: boundary.controls,
                weights: boundary.weights
            )
            return BRepSewingEdge(
                stableID: "exact:nurbs:edge:\(index)",
                curve: .bSpline(curve),
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: try curve.point(at: 0.0, tolerance: .standard),
                endPoint: try curve.point(at: 1.0, tolerance: .standard),
                surfaceParameterCurve: boundary.pcurve
            )
        }
        return try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "exact:nurbs:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "exact:nurbs:face",
                    surface: .bSpline(surface),
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "exact:nurbs:outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: .standard).brep
    }

    static func reversedRationalSheet() throws -> BRepModel {
        try reversingBSplineEdges(in: rationalSheet())
    }

    private static func reversingBSplineEdges(in source: BRepModel) throws -> BRepModel {
        var result = source
        var reversedEdgeIDs: Set<EdgeID> = []
        for edgeID in result.edges.keys.sorted() {
            guard var edge = result.edges[edgeID],
                  let trim = edge.trim,
                  case .bSpline = result.geometry.curves[edge.curveID] else {
                continue
            }
            reversedEdgeIDs.insert(edgeID)
            swap(&edge.startVertexID, &edge.endVertexID)
            edge.trim = CurveTrim(
                startParameter: trim.endParameter,
                endParameter: trim.startParameter
            )
            result.edges[edgeID] = edge
        }
        for loopID in result.loops.keys.sorted() {
            guard var loop = result.loops[loopID] else { continue }
            loop.coedges = loop.coedges.map { coedge in
                guard reversedEdgeIDs.contains(coedge.edgeID) else {
                    return coedge
                }
                var reversed = coedge
                reversed.orientation = coedge.orientation == .forward
                    ? .reversed
                    : .forward
                return reversed
            }
            result.loops[loopID] = loop
        }
        try result.validate(level: .exact, tolerance: .standard)
        return result
    }
}
