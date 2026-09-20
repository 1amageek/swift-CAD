import Testing
import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Fillet feature")
struct FilletFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func allBoxEdgesProduceExactRoundedSolid() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let points = source.brep.vertices.values.map(\.point)
        let widths = [points.map(\.x), points.map(\.y), points.map(\.z)].map { $0.max()! - $0.min()! }
        let radius = widths.min()! / 8
        let id = FeatureID()
        let operation = FeatureOperation.fillet(.init(target: .init(featureID: sourceID),
            edges: [], radius: .constant(.length(radius, unit: .meter)), allEdges: true))
        let node = try FeatureNodeFactory.make(operation: operation, id: id, in: document, tolerance: .standard)
        document.designGraph.nodes[id] = node
        document.designGraph.order.append(id)
        document.designGraph.dependencies.append(.init(source: sourceID, target: id))
        document.designGraph.revision = document.designGraph.revision.advanced()
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 26)
        #expect(evaluated.brep.faces.values.filter {
            if case .cylinder = evaluated.brep.geometry.surfaces[$0.surfaceID] { return true }; return false
        }.count == 12)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy { $0.surfaceParameterCurve != nil })
        let inner = widths.map { $0 - 2 * radius }
        let expected = inner[0] * inner[1] * inner[2]
            + 2 * radius * (inner[0] * inner[1] + inner[1] * inner[2] + inner[2] * inner[0])
            + Double.pi * radius * radius * inner.reduce(0, +)
            + 4 * Double.pi / 3 * radius * radius * radius
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-10)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        let repeated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(restored)
        #expect(repeated.brep == evaluated.brep)
        #expect(repeated.subshapes == evaluated.subshapes)
        let mesh = try #require(MeshTessellator(tolerance: .standard).tessellate(
            model: evaluated.brep,
            options: .init(linearTolerance: radius / 20, angularTolerance: .pi / 16)
        ).values.first)
        #expect(!mesh.indices.isEmpty)
        // Increasing boundary samples alone must not leave long interior fans.
        for sides in [1, 3, 5, 50] {
            let angle = Double.pi / (2 * Double(sides))
            let deviation = radius * (1 - cos(angle / 2))
            let sampled = try #require(MeshTessellator(tolerance: .standard).tessellate(
                model: evaluated.brep, options: .init(linearTolerance: deviation, angularTolerance: angle)
            ).values.first)
            var triangleOffset = 0
            for run in sampled.faceRuns {
                defer { triangleOffset += run.triangleCount }
                let face = try #require(evaluated.brep.faces[run.faceID])
                guard case let .analytic(.sphere(center, sphereRadius)) = evaluated.brep.geometry.surfaces[face.surfaceID] else { continue }
                for triangle in triangleOffset..<(triangleOffset + run.triangleCount) {
                    let vertices = (0..<3).map { Int(sampled.indices[triangle * 3 + $0]) }
                    let radial = vertices.map { sampled.positions[$0] - center }
                    let centroid = (radial[0] + radial[1] + radial[2]) / 3
                    #expect(sphereRadius - centroid.length <= deviation)
                    for index in vertices {
                        let expectedNormal = try (sampled.positions[index] - center).normalized(tolerance: 1e-10)
                        #expect(sampled.normals[index].dot(expectedNormal) > 0.999999)
                    }
                }
            }
        }
        var quality = TessellationOptions.standard
        quality.featureOverrides[id] = .init(linearTolerance: radius / 5, angularTolerance: .pi / 4)
        let coarse = try DocumentEvaluator(tolerance: .standard, tessellationOptions: quality).evaluate(document)
        quality.featureOverrides[id] = .init(linearTolerance: radius / 50, angularTolerance: .pi / 16)
        let fine = try DocumentEvaluator(tolerance: .standard, tessellationOptions: quality).evaluate(document, reusing: coarse)
        #expect(coarse.brep == fine.brep)
        #expect(try #require(fine.meshes.values.first).indices.count > #require(coarse.meshes.values.first).indices.count)
        var pair = document
        var secondSource = try #require(pair.designGraph.nodes[sourceID])
        secondSource.id = FeatureID()
        try pair.appendFeature(secondSource, tolerance: .standard)
        let secondFillet = try FeatureNodeFactory.make(operation: .fillet(.init(
            target: .init(featureID: secondSource.id), edges: [],
            radius: .constant(.length(radius, unit: .meter)), allEdges: true)),
            id: FeatureID(), in: pair, tolerance: .standard)
        try pair.appendFeature(secondFillet, tolerance: .standard)
        quality.linearTolerance = radius / 5
        quality.angularTolerance = .pi / 4
        let mixed = try DocumentEvaluator(tolerance: .standard, tessellationOptions: quality).evaluate(pair)
        let triangleCounts = mixed.meshes.values.map { $0.indices.count }.sorted()
        #expect(triangleCounts.count == 2)
        #expect(triangleCounts[0] < triangleCounts[1])
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = mixed.meshes.values.reduce(0) { $0 + $1.positions.count } - 1
        #expect(throws: TessellationError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, tessellationOptions: quality,
                                      tessellationLimits: limits).evaluate(pair)
        }
        for coordinate in [\Point3D.x, \Point3D.y, \Point3D.z] {
            #expect(abs(try #require(mesh.positions.map { $0[keyPath: coordinate] }.min())
                - #require(points.map { $0[keyPath: coordinate] }.min())) < 1e-9)
            #expect(abs(try #require(mesh.positions.map { $0[keyPath: coordinate] }.max())
                - #require(points.map { $0[keyPath: coordinate] }.max())) < 1e-9)
        }
        for invalidRadius in [0, -radius, widths.min()! / 2, widths.max()!] {
            document.designGraph.nodes[id]?.operation = .fillet(.init(
                target: .init(featureID: sourceID), edges: [],
                radius: .constant(.length(invalidRadius, unit: .meter)), allEdges: true))
            #expect(throws: (any Error).self) {
                _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func allCylinderEdgesProduceExactRoundedSolid() throws {
        var document = makeCircleExtrudeDocument(documentUnits: .meters)
        let sourceID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let lateral = source.brep.faces.values.compactMap { face -> Cylinder3D? in
            guard case let .cylinder(cylinder) = source.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return cylinder
        }
        let caps = source.brep.faces.values.compactMap { face -> Plane3D? in
            guard case let .plane(plane) = source.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return plane
        }
        #expect(lateral.count == 4)
        #expect(caps.count == 2)
        let sourceCylinder = try #require(lateral.first)
        let axis = sourceCylinder.axis
        let cylinderRadius = sourceCylinder.radius
        let capHeights = caps.map { ($0.origin - sourceCylinder.origin).dot(axis) }
        let height = abs(capHeights[1] - capHeights[0])
        let base = sourceCylinder.origin + axis * capHeights.min()!
        let radius = min(cylinderRadius, height / 2) / 4
        let id = FeatureID()
        let operation = FeatureOperation.fillet(.init(target: .init(featureID: sourceID),
            edges: [], radius: .constant(.length(radius, unit: .meter)), allEdges: true))
        let node = try FeatureNodeFactory.make(operation: operation, id: id, in: document, tolerance: .standard)
        document.designGraph.nodes[id] = node
        document.designGraph.order.append(id)
        document.designGraph.dependencies.append(.init(source: sourceID, target: id))
        document.designGraph.revision = document.designGraph.revision.advanced()
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 14)
        #expect(evaluated.brep.edges.count == 28)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.brep.faces.values.filter {
            if case .plane = evaluated.brep.geometry.surfaces[$0.surfaceID] { return true }; return false
        }.count == 2)
        #expect(evaluated.brep.faces.values.filter {
            if case .cylinder = evaluated.brep.geometry.surfaces[$0.surfaceID] { return true }; return false
        }.count == 4)
        #expect(evaluated.brep.faces.values.filter {
            if case .analytic(.torus) = evaluated.brep.geometry.surfaces[$0.surfaceID] { return true }; return false
        }.count == 8)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy { $0.surfaceParameterCurve != nil })
        let expected = Double.pi * cylinderRadius * cylinderRadius * height
            - 2 * Double.pi * radius * radius * (2 * cylinderRadius - radius)
            + Double.pi * Double.pi * radius * radius * (cylinderRadius - radius)
            + 4 * Double.pi / 3 * radius * radius * radius
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        // The fillet keeps the source silhouette: the band still reaches the full radius
        // between the two caps, and the caps still sit on the original end planes.
        let filleted = evaluated.brep.vertices.values.map(\.point)
        let radialReach = filleted.map { point -> Double in
            let offset = point - base
            return (offset - axis * offset.dot(axis)).length
        }
        let axialReach = filleted.map { ($0 - base).dot(axis) }
        #expect(abs(try #require(radialReach.max()) - cylinderRadius) < 1e-12)
        #expect(abs(try #require(axialReach.min())) < 1e-12)
        #expect(abs(try #require(axialReach.max()) - height) < 1e-12)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        let repeated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(restored)
        #expect(repeated.brep == evaluated.brep)
        #expect(repeated.subshapes == evaluated.subshapes)
        // Toroidal fillet faces must honor the requested chordal and angular budgets.
        let angle = Double.pi / 16
        let deviation = radius * (1 - cos(angle / 2))
        let mesh = try #require(MeshTessellator(tolerance: .standard).tessellate(
            model: evaluated.brep, options: .init(linearTolerance: deviation, angularTolerance: angle)
        ).values.first)
        var triangleOffset = 0
        var toroidalTriangles = 0
        for run in mesh.faceRuns {
            defer { triangleOffset += run.triangleCount }
            let face = try #require(evaluated.brep.faces[run.faceID])
            guard case let .analytic(.torus(center, torusAxis, majorRadius, minorRadius)) =
                evaluated.brep.geometry.surfaces[face.surfaceID] else { continue }
            toroidalTriangles += run.triangleCount
            for triangle in triangleOffset..<(triangleOffset + run.triangleCount) {
                let vertices = (0..<3).map { Int(mesh.indices[triangle * 3 + $0]) }
                for index in vertices {
                    let offset = mesh.positions[index] - center
                    let radial = offset - torusAxis * offset.dot(torusAxis)
                    let tubeCenter = center + (try radial.normalized(tolerance: 1e-10)) * majorRadius
                    let tube = mesh.positions[index] - tubeCenter
                    #expect(abs(tube.length - minorRadius) < 1e-9)
                    let expectedNormal = try tube.normalized(tolerance: 1e-10)
                    #expect(mesh.normals[index].dot(expectedNormal) > 0.999999)
                }
            }
        }
        #expect(toroidalTriangles > 0)
        for invalidRadius in [0, -radius, cylinderRadius, height / 2] {
            document.designGraph.nodes[id]?.operation = .fillet(.init(
                target: .init(featureID: sourceID), edges: [],
                radius: .constant(.length(invalidRadius, unit: .meter)), allEdges: true))
            #expect(throws: (any Error).self) {
                _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func allEdgeFilletRejectsABodyThatIsNeitherABoxNorACylinder() throws {
        var document = CADDocument(units: .meters)
        let sourceID = FeatureID()
        let primitive = FeatureOperation.primitive(PrimitiveFeature(definition: .sphere(
            SpherePrimitive(radius: .constant(.length(1.0, unit: .meter)))
        )))
        let sourceNode = try FeatureNodeFactory.make(
            operation: primitive, id: sourceID, name: "sphere", in: document, tolerance: .standard)
        document.designGraph.nodes[sourceID] = sourceNode
        document.designGraph.order = [sourceID]
        document.designGraph.revision = document.designGraph.revision.advanced()
        let id = FeatureID()
        let operation = FeatureOperation.fillet(.init(target: .init(featureID: sourceID),
            edges: [], radius: .constant(.length(0.1, unit: .meter)), allEdges: true))
        let node = try FeatureNodeFactory.make(operation: operation, id: id, in: document, tolerance: .standard)
        document.designGraph.nodes[id] = node
        document.designGraph.order.append(id)
        document.designGraph.dependencies.append(.init(source: sourceID, target: id))
        document.designGraph.revision = document.designGraph.revision.advanced()
        var raised: (any Error)?
        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        } catch {
            raised = error
        }
        let kernelError = try #require(raised as? KernelError)
        #expect(kernelError.code == .invalidInput)
    }

    @Test(.timeLimit(.minutes(1)))
    func createsValidatedQuarterCylinderAndSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let selectedID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        )
        let selected = try source.stableSubshapeReference(for: selectedID)
        let edgeLength = try selectedEdgeLength(selectedID, source: source)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let radius = 0.002
        let filletID = FeatureID()
        let operation = FeatureOperation.fillet(FilletFeature(
            target: FilletTargetReference(featureID: sourceFeatureID),
            edges: [selected],
            radius: .constant(.length(radius, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: filletID, in: document, tolerance: .standard)
        document.designGraph.nodes[filletID] = node
        document.designGraph.order.append(filletID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: filletID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        let cylinders = evaluated.brep.faces.values.filter { face in
            guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            if case .cylinder = surface { return true }
            return false
        }
        #expect(cylinders.count == 1)
        let cylinderFace = try #require(cylinders.first)
        try verifyG1Tangency(of: cylinderFace, in: evaluated.brep)
        let expectedVolume = sourceVolume
            - radius * radius * (1.0 - Double.pi / 4.0) * edgeLength
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        let descendants = evaluated.lineage.values.filter {
            $0.output.featureID == filletID
                && $0.output.role == GeneratedSubshapeRole.edge.rawValue
                && $0.parents.contains(selected.subshapeID)
        }
        #expect(descendants.count == 2)
        #expect(descendants.allSatisfy { $0.relation == .split })
        do {
            _ = try evaluated.topologyReference(for: selected)
            Issue.record("A replaced sharp edge must not resolve to one fillet boundary implicitly.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == selected.subshapeID)
        }
    }

    private func selectedEdgeLength(
        _ subshapeID: SubshapeID,
        source: EvaluatedDocument
    ) throws -> Double {
        guard case let .edge(edgeID) = source.subshapes[subshapeID],
              let edge = source.brep.edges[edgeID],
              let start = source.brep.vertices[edge.startVertexID],
              let end = source.brep.vertices[edge.endVertexID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                tolerance: .standard,
                message: "Fillet fixture edge could not be measured."
            )
        }
        return (end.point - start.point).length
    }

    private func verifyG1Tangency(
        of cylinderFace: Face,
        in model: BRepModel
    ) throws {
        let cylinderSurface = try #require(model.geometry.surfaces[cylinderFace.surfaceID])
        let loopID = try #require(cylinderFace.loops.first)
        let loop = try #require(model.loops[loopID])
        var verifiedBoundaryCount = 0
        for coedge in loop.coedges {
            let edge = try #require(model.edges[coedge.edgeID])
            guard case .line = model.geometry.curves[edge.curveID],
                  let pcurve = coedge.surfaceParameterCurve else {
                continue
            }
            let parameter = try pcurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: .standard
            )
            let cylinderGeometry = try cylinderSurface.differentialGeometry(
                atU: parameter.u,
                v: parameter.v,
                tolerance: .standard
            )
            let cylinderNormal = cylinderFace.orientation == .forward
                ? cylinderGeometry.normal
                : -cylinderGeometry.normal
            let adjacent = try #require(model.faces.values.first { candidate in
                guard candidate.id != cylinderFace.id else { return false }
                return candidate.loops.contains { candidateLoopID in
                    model.loops[candidateLoopID]?.coedges.contains {
                        $0.edgeID == coedge.edgeID
                    } == true
                }
            })
            guard case let .plane(plane) = model.geometry.surfaces[adjacent.surfaceID] else {
                continue
            }
            let planeNormal = adjacent.orientation == .forward ? plane.normal : -plane.normal
            #expect(cylinderNormal.dot(planeNormal) >= 1.0 - 1.0e-10)
            verifiedBoundaryCount += 1
        }
        #expect(verifiedBoundaryCount == 2)
    }
}
