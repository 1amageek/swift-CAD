import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

/// Every refining path meets the chord bound together with the turning bound; the turning bound
/// never stands in for it.
@Suite("Tessellation fidelity")
struct TessellationFidelityTests {
    @Test(.timeLimit(.minutes(1)))
    func aLargeCylinderMeetsTheChordBoundAtTheStandardOptions() throws {
        // At radius 2 m one step of the standard turning bound deviates by about 2.4 mm, far
        // beyond the 0.1 mm chord bound, so only the chord count can meet it.
        let radius = 2.0
        let (model, mesh) = try tessellatedPrimitive(.cylinder(CylinderPrimitive(
            radius: length(radius),
            height: length(0.1)
        )))
        let deviation = try maximumMidpointDeviation(of: mesh, in: model) { point, surface in
            let origin: Point3D, axis: Vector3D
            switch surface {
            case let .cylinder(cylinder): (origin, axis) = (cylinder.origin, cylinder.axis)
            case let .analytic(.cylinder(center, direction, _)): (origin, axis) = (center, direction)
            default: return nil
            }
            let offset = point - origin
            return radius - (offset - axis * offset.dot(axis)).length
        }
        #expect(deviation > 0)
        #expect(deviation <= TessellationOptions.standard.linearTolerance * (1 + 1e-9))
    }

    @Test(.timeLimit(.minutes(1)))
    func aTorusGridMeetsTheChordBoundAcrossBothDirections() throws {
        // A facet of a grid curved along both directions sags by the sum of the two directions'
        // sagittas at its diagonal's midpoint.
        let majorRadius = 4.0
        let minorRadius = 1.0
        let (model, mesh) = try tessellatedPrimitive(.torus(TorusPrimitive(
            majorRadius: length(majorRadius),
            minorRadius: length(minorRadius)
        )))
        let deviation = try maximumMidpointDeviation(of: mesh, in: model) { point, surface in
            guard case let .analytic(.torus(center, axis, major, minor)) = surface else { return nil }
            let offset = point - center
            let height = offset.dot(axis)
            let ring = (offset - axis * height).length
            return minor - ((ring - major) * (ring - major) + height * height).squareRoot()
        }
        #expect(deviation > 0)
        #expect(deviation <= TessellationOptions.standard.linearTolerance * (1 + 1e-9))
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangularParabolaRefinesForPositionNormalAndCurvatureIndependently() throws {
        let coarse = TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.5)
        let positionFine = TessellationOptions(linearTolerance: 1e-5, angularTolerance: 0.5)
        let normalFine = TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.01)
        let model = try rectangularBSplineSheet(surface: parabolicTessellationSurface(rise: 0.2))
        let original = model
        let tessellator = MeshTessellator(tolerance: .standard)
        let coarseMesh = try #require(try tessellator.tessellate(model: model, options: coarse).values.first)
        let positionMesh = try #require(try tessellator.tessellate(model: model, options: positionFine).values.first)
        let normalMesh = try #require(try tessellator.tessellate(model: model, options: normalFine).values.first)
        let higherCurvature = try rectangularBSplineSheet(surface: parabolicTessellationSurface(rise: 1))
        let curvatureMesh = try #require(try tessellator.tessellate(model: higherCurvature, options: coarse).values.first)
        #expect(positionMesh.indices.count > coarseMesh.indices.count)
        #expect(normalMesh.indices.count > coarseMesh.indices.count)
        #expect(curvatureMesh.indices.count > coarseMesh.indices.count)
        #expect(model == original)
        for (mesh, options, rise) in [(coarseMesh, coarse, 0.2), (positionMesh, positionFine, 0.2),
                                     (normalMesh, normalFine, 0.2), (curvatureMesh, coarse, 1.0)] {
            try verifyLiteralGraph(mesh, options: options, height: { u, _ in rise * u * u },
                                   normal: { u, _ in Vector3D(x: -2 * rise * u, y: 0, z: 1) })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangularSaddleBoundsTheMixedDerivativeInsideTriangles() throws {
        let rise = 0.4
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.origin, Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: rise)]])
        let model = try rectangularBSplineSheet(surface: surface)
        let options = TessellationOptions(linearTolerance: 1e-4, angularTolerance: 0.03)
        let mesh = try #require(try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options).values.first)
        try verifyLiteralGraph(mesh, options: options, height: { rise * $0 * $1 },
                               normal: { u, v in Vector3D(x: -rise * v, y: -rise * u, z: 1) })
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangularSplineBoundsEveryDiagonalByTheRequestedMaximumEdgeLength() throws {
        let model = try rectangularBSplineSheet(surface: parabolicTessellationSurface(rise: 0))
        let options = TessellationOptions(linearTolerance: 0.1, angularTolerance: 0.5, maxEdgeLength: 0.125)
        let mesh = try #require(try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options).values.first)
        var maximumLength = 0.0
        for triangle in 0..<(mesh.indices.count / 3) {
            let corners = (0..<3).map { mesh.positions[Int(mesh.indices[3 * triangle + $0])] }
            for edge in 0..<3 {
                maximumLength = max(maximumLength, (corners[(edge + 1) % 3] - corners[edge]).length)
            }
        }
        #expect(maximumLength <= 0.125 * (1 + 1e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC1KnotAndUnequalPositiveWeightsRetainTheirCertifiedSupports() throws {
        let refined = try parabolicTessellationSurface(rise: 0.2).insertingKnot(
            direction: .u, value: 0.5, tolerance: .standard)
        let options = TessellationOptions(linearTolerance: 1e-5, angularTolerance: 0.03, maxEdgeLength: 0.125)
        let model = try rectangularBSplineSheet(surface: refined)
        let mesh = try #require(try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options).values.first)
        try verifyLiteralGraph(mesh, options: options, height: { u, _ in 0.2 * u * u },
                               normal: { u, _ in Vector3D(x: -0.4 * u, y: 0, z: 1) })
        let rational = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.origin, Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]],
            weights: [[1, 2], [1, 2]])
        let rationalModel = try rectangularBSplineSheet(surface: rational)
        let rationalMesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(model: rationalModel, options: options).values.first)
        try verifyLiteralGraph(rationalMesh, options: options, height: { _, _ in 0 }, normal: { _, _ in .unitZ })
        var maximumEdge = 0.0
        for triangle in 0..<(rationalMesh.indices.count / 3) {
            let corners = (0..<3).map { rationalMesh.positions[Int(rationalMesh.indices[3 * triangle + $0])] }
            for edge in 0..<3 { maximumEdge = max(maximumEdge, (corners[(edge + 1) % 3] - corners[edge]).length) }
        }
        #expect(maximumEdge <= 0.125 * (1 + 1e-12))
    }

    @Test(.timeLimit(.minutes(1)))
    func originalC0KnotCannotBorrowContinuousNormalAuthority() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.origin, Point3D(x: 0.5, y: 0, z: 0.2), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0.2), Point3D(x: 1, y: 1, z: 0)]])
        let model = try rectangularBSplineSheet(surface: surface)
        #expect(throws: KernelError.self) {
            do {
                _ = try MeshTessellator(tolerance: .standard).tessellate(model: model)
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
                throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [CADGeometry.SurfaceParameterDirection.u, .v])
    func originalPeriodicC1RectanglesRetainLiteralGeometryAcrossTheSeam(direction: CADGeometry.SurfaceParameterDirection) throws {
        let options = TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.08, maxEdgeLength: 0.25)
        for range in [(0.0, 4.0), (3.5, 4.5)] {
            let model = try periodicExtrudedBSplineSheet(direction: direction, from: range.0, to: range.1)
            let original = model
            let mesh = try #require(try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options).values.first)
            try verifyLiteralPeriodicExtrusion(mesh, options: options)
            #expect(model == original)
            if range.0 == 0 {
                // Full native period must cover all four literal curved sides.
                #expect(mesh.positions.contains { abs($0.x - 0.75) <= 1e-12 })
                #expect(mesh.positions.contains { abs($0.x + 0.75) <= 1e-12 })
                #expect(mesh.positions.contains { abs($0.y - 0.75) <= 1e-12 })
                #expect(mesh.positions.contains { abs($0.y + 0.75) <= 1e-12 })
            } else {
                #expect(mesh.positions.allSatisfy { $0.x >= -1e-12 && $0.y >= -1e-12 })
                #expect(mesh.positions.contains { abs($0.x - 0.75) <= 1e-12 })
                #expect(mesh.positions.contains { abs($0.y - 0.75) <= 1e-12 })
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["c0", "disconnected", "periodExcess", "roundedPeriodExcess"])
    func periodicRectanglesRefuseUnprovedOriginalContracts(failure: String) throws {
        let range: (Double, Double)
        if failure == "roundedPeriodExcess" {
            range = (-Double(2).nextUp, 2)
            #expect(range.1 - range.0 == 4)
            // The represented lower endpoint is strictly below -2 while the upper is
            // exactly 2: their real difference exceeds the literal original period 4.
            #expect(range.0 < -2 && range.1 == 2)
        } else {
            range = failure == "periodExcess" ? (3.5, 8.5) : (0.0, 4.0)
        }
        let model = try periodicExtrudedBSplineSheet(direction: .u, from: range.0, to: range.1,
            degree: failure == "c0" ? 1 : 2, disconnectRawChart: failure == "disconnected",
            splitRims: failure == "roundedPeriodExcess")
        let original = model
        #expect(throws: KernelError.self) {
            do {
                _ = try MeshTessellator(tolerance: .standard).tessellate(model: model)
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
                throw error
            }
        }
        #expect(model == original)
    }

    private func verifyLiteralPeriodicExtrusion(_ mesh: Mesh, options: TessellationOptions) throws {
        func chart(_ point: Point3D) -> (deviation: Double, normal: Vector3D) {
            if abs(point.y) >= abs(point.x) {
                let sign = point.y >= 0 ? 1.0 : -1.0
                return (abs(point.y - sign * (0.75 - point.x * point.x)),
                        Vector3D(x: 2 * point.x, y: sign, z: 0))
            }
            let sign = point.x >= 0 ? 1.0 : -1.0
            return (abs(point.x - sign * (0.75 - point.y * point.y)),
                    Vector3D(x: sign, y: 2 * point.y, z: 0))
        }
        var vertexDeviation = 0.0, vertexNormalError = 0.0
        var interiorDeviation = 0.0, angularVariation = 0.0, maximumEdge = 0.0
        for index in mesh.positions.indices {
            let literal = chart(mesh.positions[index])
            vertexDeviation = max(vertexDeviation, literal.deviation)
            let n = try literal.normal.normalized(tolerance: 1e-300)
            vertexNormalError = max(vertexNormalError, (n - mesh.normals[index]).length)
        }
        let barycentrics = [(1.0 / 3, 1.0 / 3, 1.0 / 3), (0.5, 0.5, 0.0),
                            (0.5, 0.0, 0.5), (0.0, 0.5, 0.5), (0.5, 0.25, 0.25)]
        for triangle in 0..<(mesh.indices.count / 3) {
            let ids = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            let points = ids.map { mesh.positions[$0] }
            for edge in 0..<3 { maximumEdge = max(maximumEdge, (points[(edge + 1) % 3] - points[edge]).length) }
            for (a, b, c) in barycentrics {
                let point = Point3D(x: a * points[0].x + b * points[1].x + c * points[2].x,
                                    y: a * points[0].y + b * points[1].y + c * points[2].y,
                                    z: a * points[0].z + b * points[1].z + c * points[2].z)
                let literal = chart(point)
                interiorDeviation = max(interiorDeviation, literal.deviation)
                let n = try literal.normal.normalized(tolerance: 1e-300)
                for id in ids {
                    angularVariation = max(angularVariation,
                        atan2(n.cross(mesh.normals[id]).length, n.dot(mesh.normals[id])))
                }
            }
        }
        #expect(mesh.indices.isEmpty == false)
        #expect(vertexDeviation <= 1e-12)
        #expect(vertexNormalError <= 1e-11)
        #expect(interiorDeviation <= options.linearTolerance * (1 + 1e-10))
        #expect(angularVariation <= options.angularTolerance * (1 + 1e-10))
        #expect(maximumEdge <= (options.maxEdgeLength ?? .infinity) * (1 + 1e-10))
    }

    private func verifyLiteralGraph(
        _ mesh: Mesh, options: TessellationOptions,
        height: (Double, Double) -> Double, normal: (Double, Double) -> Vector3D
    ) throws {
        let barycentrics = [(1.0 / 3, 1.0 / 3, 1.0 / 3), (0.5, 0.5, 0.0),
                            (0.5, 0.0, 0.5), (0.0, 0.5, 0.5), (0.5, 0.25, 0.25)]
        #expect(mesh.indices.isEmpty == false)
        var maximumVertexDeviation = 0.0
        var maximumVertexNormalError = 0.0
        var maximumInteriorDeviation = 0.0
        var maximumNormalAngle = 0.0
        for index in mesh.positions.indices {
            let p = mesh.positions[index]
            maximumVertexDeviation = max(maximumVertexDeviation, abs(p.z - height(p.x, p.y)))
            let expected = try normal(p.x, p.y).normalized(tolerance: 1e-300)
            maximumVertexNormalError = max(maximumVertexNormalError, (mesh.normals[index] - expected).length)
        }
        for triangle in 0..<(mesh.indices.count / 3) {
            let ids = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            let corners = ids.map { mesh.positions[$0] }
            for (a, b, c) in barycentrics {
                let point = Point3D(x: a * corners[0].x + b * corners[1].x + c * corners[2].x,
                                    y: a * corners[0].y + b * corners[1].y + c * corners[2].y,
                                    z: a * corners[0].z + b * corners[1].z + c * corners[2].z)
                maximumInteriorDeviation = max(maximumInteriorDeviation, abs(point.z - height(point.x, point.y)))
                let exactNormal = try normal(point.x, point.y).normalized(tolerance: 1e-300)
                for id in ids {
                    let emitted = mesh.normals[id]
                    let angle = atan2(emitted.cross(exactNormal).length, emitted.dot(exactNormal))
                    maximumNormalAngle = max(maximumNormalAngle, angle)
                }
            }
        }
        #expect(maximumVertexDeviation <= 1e-12)
        #expect(maximumVertexNormalError <= 1e-11)
        #expect(maximumInteriorDeviation <= options.linearTolerance * (1 + 1e-10))
        #expect(maximumNormalAngle <= options.angularTolerance * (1 + 1e-10))
    }

    /// The largest distance from an emitted triangle's edge midpoints — including the diagonal
    /// of a grid cell — to the exact surface, over the faces `signedDistance` measures.
    private func maximumMidpointDeviation(
        of mesh: Mesh,
        in model: BRepModel,
        signedDistance: (Point3D, Surface3D) -> Double?
    ) throws -> Double {
        var deviation = 0.0
        var measured = 0
        var triangle = 0
        for run in mesh.faceRuns {
            defer { triangle += run.triangleCount }
            let face = try #require(model.faces[run.faceID])
            let surface = try #require(model.geometry.surfaces[face.surfaceID])
            for index in triangle..<(triangle + run.triangleCount) {
                let corners = (0..<3).map { mesh.positions[Int(mesh.indices[index * 3 + $0])] }
                for edge in 0..<3 {
                    let start = corners[edge], end = corners[(edge + 1) % 3]
                    let midpoint = start + (end - start) * 0.5
                    guard let distance = signedDistance(midpoint, surface) else { continue }
                    deviation = max(deviation, abs(distance))
                    measured += 1
                }
            }
        }
        #expect(measured > 0, "No triangle lay on the measured surface.")
        return deviation
    }

    private func tessellatedPrimitive(_ definition: PrimitiveDefinition) throws -> (BRepModel, Mesh) {
        let evaluated = try evaluatePrimitive(definition)
        let meshes = try MeshTessellator(tolerance: .standard).tessellate(
            model: evaluated.brep, options: .standard
        )
        return (evaluated.brep, try #require(meshes.values.first))
    }
}

/// `TessellationOptions.standard` stays feasible under `TessellationLimits.standard`: twelve
/// complete spheres of 1 m radius, the assembly size the limits were sized for, are admitted.
@Suite("Tessellation standard feasibility")
struct TessellationStandardFeasibilityTests {
    @Test(.timeLimit(.minutes(1)))
    func twelveUnitSpheresFitTheStandardLimits() throws {
        let evaluated = try evaluatePrimitive(.sphere(SpherePrimitive(radius: length(1.0))))
        let meshes = try MeshTessellator(tolerance: .standard).tessellate(
            model: evaluated.brep, options: .standard
        )
        let usage = try TessellationUsage(mesh: try #require(meshes.values.first))
        let assembly = TessellationUsage(
            vertexCount: usage.vertexCount * 12,
            indexCount: usage.indexCount * 12,
            triangleCount: usage.triangleCount * 12,
            byteCount: usage.byteCount * 12
        )
        #expect(assembly.firstResourceExceeding(.standard) == nil, "Twelve spheres need \(assembly).")
    }
}

private func evaluatePrimitive(_ definition: PrimitiveDefinition) throws -> EvaluatedDocument {
    let featureID = FeatureID()
    var document = CADDocument(units: .meters)
    let node = try FeatureNodeFactory.make(
        operation: .primitive(PrimitiveFeature(definition: definition)),
        id: featureID,
        name: "Primitive",
        in: document,
        tolerance: .standard
    )
    document.designGraph.nodes[featureID] = node
    document.designGraph.order = [featureID]
    document.designGraph.revision = document.designGraph.revision.advanced()
    return try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
}

private func length(_ value: Double) -> CADExpression {
    .constant(.length(value, unit: .meter))
}

/// The exact polynomial graph S(u,v)=(u,v,rise*u*u), authored as one original Bezier span.
func parabolicTessellationSurface(rise: Double) -> BSplineSurface3D {
    BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
        controlPoints: [
            [.origin, Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: rise)],
            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0), Point3D(x: 1, y: 1, z: rise)]])
}

/// A complete sheet owner graph with four exact original-support surface-lift edges.
func rectangularBSplineSheet(surface: BSplineSurface3D, copies: Int = 1) throws -> BRepModel {
    let support = Surface3D.bSpline(surface)
    let pcurves: [SurfaceParameterCurve] = [
        .constantV(v: 0, uStart: 0, uEnd: 1), .constantU(u: 1, vStart: 0, vEnd: 1),
        .constantV(v: 1, uStart: 1, uEnd: 0), .constantU(u: 0, vStart: 1, vEnd: 0)]
    let corners = try [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].map {
        Vertex(point: try support.point(u: $0.0, v: $0.1, tolerance: .standard))
    }
    var model = BRepModel()
    for _ in 0..<copies {
        let vertices = corners.map { Vertex(point: $0.point) }
        var coedges: [Coedge] = []
        for index in 0..<4 {
            let curveID = CurveID()
            model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: pcurves[index]))
            let edge = Edge(curveID: curveID, startVertexID: vertices[index].id, endVertexID: vertices[(index + 1) % 4].id,
                            trim: CurveTrim(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: pcurves[index]))
        }
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        let surfaceID = SurfaceID()
        model.geometry.surfaces[surfaceID] = support
        let loop = Loop(coedges: coedges)
        let face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.loops[loop.id] = loop
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
    }
    return model
}

/// A literal uniform quadratic periodic extrusion with raw unwrapped constant-coordinate sides.
/// Full turns split both closed rims so every native edge has distinct endpoints; one seam edge
/// has two opposite uses. Alternate stored edges are reversed to exercise actual coedge use.
func periodicExtrudedBSplineSheet(
    direction: SurfaceParameterDirection, from lower: Double, to upper: Double,
    degree: Int = 2, disconnectRawChart: Bool = false, splitRims: Bool = false, copies: Int = 1
) throws -> BRepModel {
    let controls = [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0),
                    Point3D(x: -1, y: 0, z: 0), Point3D(x: 0, y: -1, z: 0)]
    let periodicU = direction == .u
    let net = periodicU ? [controls, controls.map { $0 + Vector3D.unitZ }]
        : controls.map { [$0, $0 + Vector3D.unitZ] }
    let spline = try BSplineSurface3D.periodic(
        uDegree: periodicU ? degree : 1, vDegree: periodicU ? 1 : degree,
        uKnots: periodicU ? [0, 1, 2, 3, 4] : [0, 0, 1, 1],
        vKnots: periodicU ? [0, 0, 1, 1] : [0, 1, 2, 3, 4],
        controlPoints: net, isUPeriodic: periodicU, isVPeriodic: !periodicU, tolerance: .standard)
    let support = Surface3D.bSpline(spline)
    let fullPeriod = lower == 0 && upper == 4
    let rawCorners: [(Double, Double)]
    if fullPeriod || splitRims {
        let middle = lower + (upper - lower) * 0.5
        rawCorners = [(lower, 0), (middle, 0), (upper, 0), (upper, 1), (middle, 1), (lower, 1)]
    } else {
        rawCorners = [(lower, 0), (upper, 0), (upper, 1), (lower, 1)]
    }
    func pcurve(from start: (Double, Double), to end: (Double, Double)) -> SurfaceParameterCurve {
        if start.0 == end.0 {
            return periodicU ? .constantU(u: start.0, vStart: start.1, vEnd: end.1)
                : .constantV(v: start.0, uStart: start.1, uEnd: end.1)
        }
        return periodicU ? .constantV(v: start.1, uStart: start.0, uEnd: end.0)
            : .constantU(u: start.1, vStart: start.0, vEnd: end.0)
    }
    func literalPoint(_ parameter: Double, height: Double) -> Point3D {
        let remainder = parameter.truncatingRemainder(dividingBy: 4)
        let representative = remainder < 0 ? remainder + 4 : remainder
        let cell = Int(floor(representative)), t = representative - Double(cell)
        let first: Point3D
        if degree == 2 {
            first = Point3D(x: 0.5 - t, y: 0.5 + t - t * t, z: height)
        } else {
            first = Point3D(x: 1 - t, y: t, z: height)
        }
        switch cell {
        case 0: return first
        case 1: return Point3D(x: -first.y, y: first.x, z: height)
        case 2: return Point3D(x: -first.x, y: -first.y, z: height)
        default: return Point3D(x: first.y, y: -first.x, z: height)
        }
    }
    var model = BRepModel()
    for _ in 0..<copies {
        var vertices: [SurfaceParameter: Vertex] = [:]
        func vertex(_ corner: (Double, Double)) -> Vertex {
            let phase = corner.0.truncatingRemainder(dividingBy: 4)
            let key = SurfaceParameter(u: phase, v: corner.1)
            if let existing = vertices[key] { return existing }
            let created = Vertex(point: literalPoint(corner.0, height: corner.1))
            vertices[key] = created
            return created
        }
        var coedges: [Coedge] = []
        var seam: Edge?
        for index in rawCorners.indices {
            let start = rawCorners[index], end = rawCorners[(index + 1) % rawCorners.count]
            let use = pcurve(from: start, to: end)
            let startVertex = vertex(start), endVertex = vertex(end)
            if fullPeriod && index == 5, let seam {
                coedges.append(Coedge(edgeID: seam.id, orientation: .reversed, surfaceParameterCurve: use))
                continue
            }
            let reverseStorage = index % 2 == 1
            let storedPcurve: SurfaceParameterCurve
            if fullPeriod && index == 2 {
                storedPcurve = pcurve(from: (0, 0), to: (0, 1))
            } else {
                storedPcurve = reverseStorage ? try use.reversed(tolerance: .standard) : use
            }
            let curveID = CurveID()
            model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: storedPcurve))
            let edge = Edge(curveID: curveID,
                startVertexID: reverseStorage ? endVertex.id : startVertex.id,
                endVertexID: reverseStorage ? startVertex.id : endVertex.id,
                trim: CurveTrim(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            let orientedPcurve: SurfaceParameterCurve
            if fullPeriod && index == 2 {
                seam = edge
                orientedPcurve = .periodicTranslation(base: storedPcurve,
                    uShift: periodicU ? 4 : 0, vShift: periodicU ? 0 : 4)
            } else if disconnectRawChart && index == 0 {
                orientedPcurve = .periodicTranslation(base: use,
                    uShift: periodicU ? 4 : 0, vShift: periodicU ? 0 : 4)
            } else {
                orientedPcurve = use
            }
            coedges.append(Coedge(edgeID: edge.id, orientation: reverseStorage ? .reversed : .forward,
                                  surfaceParameterCurve: orientedPcurve))
        }
        for vertex in vertices.values { model.vertices[vertex.id] = vertex }
        let surfaceID = SurfaceID(), loop = Loop(coedges: coedges)
        let face = Face(surfaceID: surfaceID, loops: [loop.id], orientation: periodicU ? .forward : .reversed)
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support
        model.loops[loop.id] = loop
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
    }
    return model
}
