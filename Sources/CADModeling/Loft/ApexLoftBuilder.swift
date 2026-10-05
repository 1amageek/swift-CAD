import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A Loft from one section to a vertex: each section span ruled to the apex, its rulings meeting
/// there. A straight span's face is the exact plane of its triangle; a curved span's is the ruled
/// surface between the span and the apex, its row at the apex collapsed to that point (a pole the
/// face's three edges meet at, as a cone's faces do). A closed section closes the solid with its
/// planar region.
package struct ApexLoftBuilder {
    private let tolerance: ModelingTolerance
    private let patches: ExactLinearSectionSweepFacePatchBuilder

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
    }

    package func request(spans: [ExactBSplineCurveSpan], isClosed: Bool, apex: Point3D, resultKind: LoftResultKind,
                         featureID: FeatureID) throws -> BRepSewingRequest {
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard spans.isEmpty == false else { throw failure(.invalidInput, "A Loft to a vertex has an empty section.") }
        guard resultKind == .sheet || isClosed else { throw failure(.invalidInput, "A solid Loft to a vertex needs a closed section.") }
        // The section's plane (a closed section's, or the plane of its points), its normal toward
        // the apex.
        let points = spans.flatMap(\.curve.controlPoints)
        let centroid = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(points.count))
        var normal = Vector3D.zero
        for (a, b) in zip(points, points.dropFirst() + points.prefix(1)) {
            normal = normal + (a - centroid).cross(b - centroid)
        }
        // An open straight section spans no plane of its own: it and the apex make one flat fan.
        let collinear = normal.length <= tolerance.distance * tolerance.distance
        guard collinear == false || isClosed == false else {
            throw failure(.invalidInput, "A closed section of a Loft to a vertex spans a plane.")
        }
        if collinear {
            normal = (points[points.count - 1] - points[0]).cross(apex - points[0])
            guard normal.length > tolerance.distance * tolerance.distance else {
                throw failure(.invalidInput, "A Loft's vertex lies on its straight section.")
            }
        }
        normal = try normal.normalized(tolerance: tolerance.distance)
        let planar = collinear || points.allSatisfy({ abs(($0 - centroid).dot(normal)) <= tolerance.distance })
        // A solid's section is a region, always planar; only a curve section, which lofts into a
        // sheet, may bend out of a plane.
        guard planar || resultKind == .sheet else {
            throw failure(.invalidInput, "A solid Loft to a vertex takes a planar section.")
        }
        let height = (apex - centroid).dot(normal)
        if height < 0 { normal = normal * -1 }
        guard collinear || planar == false || abs(height) > tolerance.distance else {
            throw failure(.invalidInput, "A Loft's vertex lies in its section's plane.")
        }
        // Rulings from a loop wound counterclockwise about the normal toward the apex face out; a
        // non-planar section's sheet keeps the rulings' own side, which every face shares.
        let winding = isClosed && planar ? try patches.profileWindingSign(spans, normal: normal, featureID: featureID) : 1
        let sideOrientation: Orientation = winding > 0 ? .forward : .reversed
        var faces: [BRepSewingFacePatch] = []
        for (index, span) in spans.enumerated() {
            let stableID = "loft:apex:side:\(index)"
            let curve = span.curve
            guard case let .closed(u0, u1) = curve.domain else { throw failure(.invalidInput, "A Loft section span is unbounded.") }
            let toApex = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [span.endPoint, apex])
            let fromApex = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [apex, span.startPoint])
            if try patches.isStraight(curve) {
                // The exact plane of the triangle.
                let planeNormal = try ((span.endPoint - span.startPoint).cross(apex - span.startPoint)).normalized(tolerance: tolerance.distance)
                let surface = Surface3D.plane(Plane3D(origin: span.startPoint, normal: planeNormal))
                let edges = try [(curve, "span"), (toApex, "to"), (fromApex, "from")].map { edgeCurve, name in
                    try patches.exactEdge(edgeCurve, reversed: false,
                                          surfaceParameterCurve: try patches.planarPcurve(edgeCurve, reversed: false, on: surface),
                                          stableID: "\(stableID):\(name)")
                }
                faces.append(BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: sideOrientation,
                    loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)]))
                continue
            }
            let ruled = BSplineSurface3D(uDegree: curve.degree, vDegree: 1, uKnots: curve.knots, vKnots: [0, 0, 1, 1],
                                         controlPoints: [curve.controlPoints, Array(repeating: apex, count: curve.controlPointCount)],
                                         weights: [curve.weights, curve.weights])
            try ruled.validate(tolerance: tolerance)
            let surface = Surface3D.bSpline(ruled)
            func line(_ start: Point3D, _ end: Point3D, _ pcurve: SurfaceParameterCurve, _ name: String) throws -> BRepSewingEdge {
                let delta = end - start
                return BRepSewingEdge(stableID: "\(stableID):\(name)",
                    curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
                    startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end, surfaceParameterCurve: pcurve)
            }
            let edges = [
                BRepSewingEdge(stableID: "\(stableID):span", curve: .bSpline(curve), startParameter: u0, endParameter: u1,
                               startPoint: span.startPoint, endPoint: span.endPoint,
                               surfaceParameterCurve: .constantV(v: 0, uStart: u0, uEnd: u1)),
                try line(span.endPoint, apex, .constantU(u: u1, vStart: 0, vEnd: 1), "to"),
                try line(apex, span.startPoint, .constantU(u: u0, vStart: 1, vEnd: 0), "from"),
            ]
            faces.append(BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: sideOrientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)]))
        }
        if resultKind == .solid {
            // The section's region, facing away from the apex: its loop runs clockwise about the
            // normal toward the apex.
            let surface = Surface3D.plane(Plane3D(origin: centroid, normal: normal * -1))
            let reversed = winding > 0
            let ordered = reversed ? Array(spans.reversed()) : spans
            let edges = try ordered.enumerated().map { index, span in
                try patches.exactEdge(span.curve, reversed: reversed,
                                      surfaceParameterCurve: try patches.planarPcurve(span.curve, reversed: reversed, on: surface),
                                      stableID: "loft:apex:cap:edge:\(index)")
            }
            faces.append(BRepSewingFacePatch(stableID: "loft:apex:cap", surface: surface, orientation: .forward,
                loops: [BRepSewingLoop(stableID: "loft:apex:cap:loop", role: .outer, edges: edges)]))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: resultKind == .solid ? .solid : .sheet,
                                 shells: [BRepSewingShell(stableID: "loft:apex:shell", patches: faces)])
    }
}
