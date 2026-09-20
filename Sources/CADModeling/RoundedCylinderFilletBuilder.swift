import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Exact all-edge fillet of a circular cylinder, independent of display sampling.
struct RoundedCylinderFilletBuilder {
    let tolerance: ModelingTolerance

    func request(
        bodyID: BodyID,
        radius: Double,
        featureID: FeatureID,
        model: BRepModel
    ) throws -> BRepSewingRequest {
        let source = try sourceCylinder(bodyID: bodyID, model: model)
        guard radius.isFinite,
              radius > tolerance.distance,
              source.radius - radius > tolerance.distance,
              source.height - 2.0 * radius > tolerance.distance else {
            throw invalid(
                "Cylinder fillet radius must be positive, below the cylinder radius, and below half its height."
            )
        }

        let axis = source.axis
        let outerRadius = source.radius
        let innerRadius = outerRadius - radius
        let bandHeight = source.height - 2.0 * radius
        let bottomCenter = source.origin
        let topCenter = bottomCenter + axis * source.height
        let lowRing = bottomCenter + axis * radius
        let highRing = topCenter + axis * -radius
        let quarter = Double.pi * 0.5

        // Both patches meeting on a boundary read its curve and endpoints from the same
        // expression, so the sewer sees one edge instead of two coincident ones.
        let directions = (0..<4).map { index -> Vector3D in
            let angle = Double(index) * quarter
            return source.reference * cos(angle) + source.binormal * sin(angle)
        }
        let midDirections = (0..<4).map { index -> Vector3D in
            let angle = (Double(index) + 0.5) * quarter
            return source.reference * cos(angle) + source.binormal * sin(angle)
        }
        func bottomRimPoint(_ index: Int) -> Point3D {
            bottomCenter + directions[index % 4] * innerRadius
        }
        func topRimPoint(_ index: Int) -> Point3D {
            topCenter + directions[index % 4] * innerRadius
        }
        func lowBandPoint(_ index: Int) -> Point3D {
            lowRing + directions[index % 4] * outerRadius
        }
        func highBandPoint(_ index: Int) -> Point3D {
            highRing + directions[index % 4] * outerRadius
        }

        let bottomRim = AnalyticCurve3D.circle(center: bottomCenter, normal: axis, radius: innerRadius)
        let topRim = AnalyticCurve3D.circle(center: topCenter, normal: axis, radius: innerRadius)
        let lowBand = AnalyticCurve3D.circle(center: lowRing, normal: axis, radius: outerRadius)
        let highBand = AnalyticCurve3D.circle(center: highRing, normal: axis, radius: outerRadius)

        let band = Surface3D.cylinder(Cylinder3D(origin: lowRing, axis: axis, radius: outerRadius))
        let bottomTorus = Surface3D.analytic(.torus(
            center: lowRing,
            axis: axis,
            majorRadius: innerRadius,
            minorRadius: radius
        ))
        let topTorus = Surface3D.analytic(.torus(
            center: highRing,
            axis: axis,
            majorRadius: innerRadius,
            minorRadius: radius
        ))
        let bottomCap = Surface3D.plane(Plane3D(origin: bottomCenter, normal: axis * -1.0))
        let topCap = Surface3D.plane(Plane3D(origin: topCenter, normal: axis))

        let bandSeam = try band.parameterProjection(of: lowBandPoint(0), tolerance: tolerance).u
        let bottomSeam = try bottomTorus.parameterProjection(of: lowBandPoint(0), tolerance: tolerance).u
        let topSeam = try topTorus.parameterProjection(of: highBandPoint(0), tolerance: tolerance).u

        let primitives = PrimitiveBRepRequestBuilder(tolerance: tolerance)
        var patches: [BRepSewingFacePatch] = []
        func patch(_ id: String, _ surface: Surface3D, _ edges: [BRepSewingEdge]) -> BRepSewingFacePatch {
            .init(
                stableID: id,
                surface: surface,
                orientation: .forward,
                loops: [.init(stableID: id + ":loop", role: .outer, edges: edges)]
            )
        }
        func meridian(_ center: Point3D, _ index: Int) throws -> AnalyticCurve3D {
            let direction = directions[index % 4]
            return .circle(
                center: center + direction * innerRadius,
                normal: try axis.cross(direction).normalized(tolerance: tolerance.distance),
                radius: radius
            )
        }
        func meridianPoint(_ center: Point3D, _ index: Int, _ v: Double) -> Point3D {
            center
                + directions[index % 4] * (innerRadius + radius * cos(v))
                + axis * (radius * sin(v))
        }

        // Four cylindrical quarters keep the original outer radius between the fillets.
        for index in 0..<4 {
            let id = "cylinder-fillet:band:\(index)"
            let u0 = bandSeam + Double(index) * quarter
            let u1 = u0 + quarter
            let low = try primitives.circleEdge(
                stableID: id + ":low",
                definition: lowBand,
                startPoint: lowBandPoint(index),
                midpoint: lowRing + midDirections[index] * outerRadius,
                endPoint: lowBandPoint(index + 1),
                pcurve: { _, _ in .constantV(v: 0.0, uStart: u0, uEnd: u1) }
            )
            let up = try primitives.lineEdge(
                stableID: id + ":up",
                from: lowBandPoint(index + 1),
                to: highBandPoint(index + 1),
                pcurve: .constantU(u: u1, vStart: 0.0, vEnd: bandHeight)
            )
            let high = try primitives.circleEdge(
                stableID: id + ":high",
                definition: highBand,
                startPoint: highBandPoint(index + 1),
                midpoint: highRing + midDirections[index] * outerRadius,
                endPoint: highBandPoint(index),
                pcurve: { _, _ in .constantV(v: bandHeight, uStart: u1, uEnd: u0) }
            )
            let down = try primitives.lineEdge(
                stableID: id + ":down",
                from: highBandPoint(index),
                to: lowBandPoint(index),
                pcurve: .constantU(u: u0, vStart: bandHeight, vEnd: 0.0)
            )
            patches.append(patch(id, band, [low, up, high, down]))
        }

        // Four toroidal quarters blend the bottom cap into the band.
        for index in 0..<4 {
            let id = "cylinder-fillet:bottom:\(index)"
            let u0 = bottomSeam + Double(index) * quarter
            let u1 = u0 + quarter
            let v0 = Double.pi * 1.5
            let v1 = Double.pi * 2.0
            let vMid = (v0 + v1) * 0.5
            let bottom = try primitives.circleEdge(
                stableID: id + ":bottom",
                definition: bottomRim,
                startPoint: bottomRimPoint(index),
                midpoint: bottomCenter + midDirections[index] * innerRadius,
                endPoint: bottomRimPoint(index + 1),
                pcurve: { _, _ in .constantV(v: v0, uStart: u0, uEnd: u1) }
            )
            let right = try primitives.circleEdge(
                stableID: id + ":right",
                definition: try meridian(lowRing, index + 1),
                startPoint: bottomRimPoint(index + 1),
                midpoint: meridianPoint(lowRing, index + 1, vMid),
                endPoint: lowBandPoint(index + 1),
                pcurve: { _, _ in .constantU(u: u1, vStart: v0, vEnd: v1) }
            )
            let top = try primitives.circleEdge(
                stableID: id + ":top",
                definition: lowBand,
                startPoint: lowBandPoint(index + 1),
                midpoint: lowRing + midDirections[index] * outerRadius,
                endPoint: lowBandPoint(index),
                pcurve: { _, _ in .constantV(v: v1, uStart: u1, uEnd: u0) }
            )
            let left = try primitives.circleEdge(
                stableID: id + ":left",
                definition: try meridian(lowRing, index),
                startPoint: lowBandPoint(index),
                midpoint: meridianPoint(lowRing, index, vMid),
                endPoint: bottomRimPoint(index),
                pcurve: { _, _ in .constantU(u: u0, vStart: v1, vEnd: v0) }
            )
            patches.append(patch(id, bottomTorus, [bottom, right, top, left]))
        }

        // Four toroidal quarters blend the band into the top cap.
        for index in 0..<4 {
            let id = "cylinder-fillet:top:\(index)"
            let u0 = topSeam + Double(index) * quarter
            let u1 = u0 + quarter
            let v0 = 0.0
            let v1 = Double.pi * 0.5
            let vMid = (v0 + v1) * 0.5
            let bottom = try primitives.circleEdge(
                stableID: id + ":bottom",
                definition: highBand,
                startPoint: highBandPoint(index),
                midpoint: highRing + midDirections[index] * outerRadius,
                endPoint: highBandPoint(index + 1),
                pcurve: { _, _ in .constantV(v: v0, uStart: u0, uEnd: u1) }
            )
            let right = try primitives.circleEdge(
                stableID: id + ":right",
                definition: try meridian(highRing, index + 1),
                startPoint: highBandPoint(index + 1),
                midpoint: meridianPoint(highRing, index + 1, vMid),
                endPoint: topRimPoint(index + 1),
                pcurve: { _, _ in .constantU(u: u1, vStart: v0, vEnd: v1) }
            )
            let top = try primitives.circleEdge(
                stableID: id + ":top",
                definition: topRim,
                startPoint: topRimPoint(index + 1),
                midpoint: topCenter + midDirections[index] * innerRadius,
                endPoint: topRimPoint(index),
                pcurve: { _, _ in .constantV(v: v1, uStart: u1, uEnd: u0) }
            )
            let left = try primitives.circleEdge(
                stableID: id + ":left",
                definition: try meridian(highRing, index),
                startPoint: topRimPoint(index),
                midpoint: meridianPoint(highRing, index, vMid),
                endPoint: highBandPoint(index),
                pcurve: { _, _ in .constantU(u: u0, vStart: v1, vEnd: v0) }
            )
            patches.append(patch(id, topTorus, [bottom, right, top, left]))
        }

        // Two inset planar caps close the shell, traversed against their fillet neighbors.
        var bottomCapEdges: [BRepSewingEdge] = []
        for step in 0..<4 {
            let index = 3 - step
            bottomCapEdges.append(try primitives.circleEdge(
                stableID: "cylinder-fillet:cap:bottom:\(index)",
                definition: bottomRim,
                startPoint: bottomRimPoint(index + 1),
                midpoint: bottomCenter + midDirections[index] * innerRadius,
                endPoint: bottomRimPoint(index),
                pcurve: { start, end in
                    try primitives.planarHarmonicPcurve(
                        curve: .analytic(bottomRim),
                        center: bottomCenter,
                        startParameter: start,
                        endParameter: end,
                        surface: bottomCap
                    )
                }
            ))
        }
        patches.append(patch("cylinder-fillet:cap:bottom", bottomCap, bottomCapEdges))

        var topCapEdges: [BRepSewingEdge] = []
        for index in 0..<4 {
            topCapEdges.append(try primitives.circleEdge(
                stableID: "cylinder-fillet:cap:top:\(index)",
                definition: topRim,
                startPoint: topRimPoint(index),
                midpoint: topCenter + midDirections[index] * innerRadius,
                endPoint: topRimPoint(index + 1),
                pcurve: { start, end in
                    try primitives.planarHarmonicPcurve(
                        curve: .analytic(topRim),
                        center: topCenter,
                        startParameter: start,
                        endParameter: end,
                        surface: topCap
                    )
                }
            ))
        }
        patches.append(patch("cylinder-fillet:cap:top", topCap, topCapEdges))

        return .init(
            featureID: featureID,
            bodyKind: .solid,
            shells: [.init(stableID: "cylinder-fillet:shell", patches: patches)]
        )
    }

    /// The axis, base, radius, and seam direction the rounded shell is rebuilt from.
    private struct SourceCylinder {
        let origin: Point3D
        let axis: Vector3D
        let reference: Vector3D
        let binormal: Vector3D
        let radius: Double
        let height: Double
    }

    private func sourceCylinder(bodyID: BodyID, model: BRepModel) throws -> SourceCylinder {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let vertices = scope.references.compactMap { reference -> Vertex? in
            guard case .vertex(let id) = reference else { return nil }
            return model.vertices[id]
        }.sorted { a, b in
            if a.point.x != b.point.x { return a.point.x < b.point.x }
            if a.point.y != b.point.y { return a.point.y < b.point.y }
            return a.point.z < b.point.z
        }
        let edges = scope.references.compactMap { reference -> Edge? in
            guard case .edge(let id) = reference else { return nil }
            return model.edges[id]
        }
        let faces = scope.references.compactMap { reference -> Face? in
            guard case .face(let id) = reference else { return nil }
            return model.faces[id]
        }
        guard vertices.count == 8, edges.count == 12, faces.count == 6,
              let seed = vertices.first else {
            throw invalid("All-edge fillet requires a circular cylinder.")
        }
        var lateral: [Cylinder3D] = []
        var caps: [Plane3D] = []
        for face in faces {
            guard face.loops.count == 1 else {
                throw invalid("All-edge cylinder fillet requires single-loop faces.")
            }
            switch model.geometry.surfaces[face.surfaceID] {
            case .cylinder(let cylinder): lateral.append(cylinder)
            case .plane(let plane): caps.append(plane)
            default:
                throw invalid("All-edge cylinder fillet requires four lateral faces and two planar caps.")
            }
        }
        guard lateral.count == 4, caps.count == 2, let first = lateral.first else {
            throw invalid("All-edge cylinder fillet requires four lateral faces and two planar caps.")
        }
        let axis = try first.axis.normalized(tolerance: tolerance.distance)
        let radius = first.radius
        guard radius > tolerance.distance else {
            throw invalid("All-edge cylinder fillet requires a positive cylinder radius.")
        }
        for cylinder in lateral.dropFirst() {
            let candidate = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let offset = cylinder.origin - first.origin
            guard abs(cylinder.radius - radius) <= tolerance.distance,
                  abs(abs(candidate.dot(axis)) - 1.0) <= tolerance.angle,
                  (offset - axis * offset.dot(axis)).length <= tolerance.distance else {
                throw invalid("All-edge cylinder fillet requires one shared lateral surface.")
            }
        }
        for cap in caps {
            guard abs(abs(cap.normal.dot(axis)) - 1.0) <= tolerance.angle else {
                throw invalid("All-edge cylinder fillet requires caps perpendicular to the axis.")
            }
        }
        let heights = caps.map { ($0.origin - first.origin).dot(axis) }
        let height = abs(heights[1] - heights[0])
        guard height > tolerance.distance else {
            throw invalid("All-edge cylinder fillet requires caps separated along the axis.")
        }
        var rims = 0
        var seams = 0
        for edge in edges {
            switch model.geometry.curves[edge.curveID] {
            case .circle(let circle):
                guard abs(circle.radius - radius) <= tolerance.distance,
                      abs(abs(circle.normal.dot(axis)) - 1.0) <= tolerance.angle else {
                    throw invalid("All-edge cylinder fillet requires rim arcs of the cylinder radius.")
                }
                rims += 1
            case .line:
                seams += 1
            default:
                throw invalid("All-edge cylinder fillet requires circular rims and straight seams.")
            }
        }
        guard rims == 8, seams == 4 else {
            throw invalid("All-edge cylinder fillet requires eight rim arcs and four axial seams.")
        }
        // The frame starts at the lower cap so that a symmetric or reversed extrusion
        // rebuilds from the same base as one that starts at its sketch plane.
        let origin = first.origin + axis * min(heights[0], heights[1])
        let offset = seed.point - origin
        let radial = offset - axis * offset.dot(axis)
        guard abs(radial.length - radius) <= tolerance.distance else {
            throw invalid("All-edge cylinder fillet requires source vertices on the lateral surface.")
        }
        let reference = try radial.normalized(tolerance: tolerance.distance)
        let binormal = try axis.cross(reference).normalized(tolerance: tolerance.distance)
        return SourceCylinder(
            origin: origin,
            axis: axis,
            reference: reference,
            binormal: binormal,
            radius: radius,
            height: height
        )
    }

    private func invalid(_ message: String) -> KernelError {
        .init(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
