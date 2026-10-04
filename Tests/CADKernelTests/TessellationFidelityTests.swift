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
