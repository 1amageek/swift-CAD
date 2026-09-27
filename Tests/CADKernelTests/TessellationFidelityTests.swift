import Foundation
import Testing
import CADCore
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
