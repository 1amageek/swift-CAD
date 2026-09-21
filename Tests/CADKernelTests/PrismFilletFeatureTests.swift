import Testing
import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling
@testable import CADKernel

/// The general convex-prism all-edge fillet, checked against the two exact builders it
/// generalizes and against closed-form volumes for profiles neither of them can express.
@Suite("Prism fillet feature")
struct PrismFilletFeatureTests {

    @Test(.timeLimit(.minutes(1)))
    func prismFilletOfABoxMatchesTheBoxBuilder() throws {
        let document = extrudeDocument(sketch: rectangleProfileSketch(width: 0.04, depth: 0.02),
                                       height: 0.01)
        let radius = 0.00125
        let (routed, general) = try roundedBothWays(document, radius: radius)
        #expect(routed.faces.count == 26)
        expectSameSolid(general, routed)
    }

    @Test(.timeLimit(.minutes(1)))
    func prismFilletOfACylinderMatchesTheCylinderBuilder() throws {
        let document = extrudeDocument(sketch: circleProfileSketch(radius: 0.02), height: 0.03)
        let radius = 0.004
        let (routed, general) = try roundedBothWays(document, radius: radius)
        #expect(routed.faces.count == 14)
        expectSameSolid(general, routed)
    }

    @Test(.timeLimit(.minutes(1)))
    func hexagonalPrismAllEdgesProduceExactRoundedSolid() throws {
        let circumradius = 0.02
        let height = 0.03
        let radius = 0.004
        var document = extrudeDocument(sketch: regularPolygonProfileSketch(
            circumradius: circumradius, sides: 6), height: height)
        let sourceID = try #require(document.designGraph.order.last)
        let id = try appendAllEdgeFillet(radius: radius, after: sourceID, to: &document)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // Six lateral faces and six non-tangent corners: 3m + 3C + 2 faces, 7m + 5C edges,
        // 4m + 2C vertices.
        #expect(evaluated.brep.faces.count == 38)
        #expect(evaluated.brep.edges.count == 72)
        #expect(evaluated.brep.vertices.count == 36)
        #expect(planeCount(evaluated.brep) == 8)
        #expect(cylinderCount(evaluated.brep) == 18)
        #expect(sphereCount(evaluated.brep) == 12)
        #expect(torusCount(evaluated.brep) == 0)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges)
            .allSatisfy { $0.surfaceParameterCurve != nil })
        // Offsetting a regular hexagon inward by r shrinks its inradius by r, so the offset
        // profile is the hexagon of circumradius a - 2r / sqrt(3).
        let inset = circumradius - 2 * radius / 3.0.squareRoot()
        let expected = steinerVolume(
            area: 3 * 3.0.squareRoot() / 2 * inset * inset, perimeter: 6 * inset,
            height: height, radius: radius)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        let repeated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(restored)
        #expect(repeated.brep == evaluated.brep)
        #expect(repeated.subshapes == evaluated.subshapes)
        #expect(id != sourceID)
    }

    @Test(.timeLimit(.minutes(1)))
    func slotPrismAllEdgesProduceExactRoundedSolid() throws {
        let span = 0.03
        let profileRadius = 0.01
        let height = 0.02
        let radius = 0.003
        var document = extrudeDocument(sketch: slotProfileSketch(
            span: span, radius: profileRadius), height: height)
        let sourceID = try #require(document.designGraph.order.last)
        _ = try appendAllEdgeFillet(radius: radius, after: sourceID, to: &document)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        // Each end arrives as two quarter arcs, so six lateral faces meet at tangent seams:
        // the slot rounds without a single spherical patch and every arc carries a torus.
        #expect(evaluated.brep.faces.count == 20)
        #expect(evaluated.brep.edges.count == 42)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(planeCount(evaluated.brep) == 4)
        #expect(cylinderCount(evaluated.brep) == 8)
        #expect(torusCount(evaluated.brep) == 8)
        #expect(sphereCount(evaluated.brep) == 0)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges)
            .allSatisfy { $0.surfaceParameterCurve != nil })
        // The inward offset of a stadium keeps its two centers and loses r from its radius.
        let inset = profileRadius - radius
        let expected = steinerVolume(
            area: 2 * inset * span + .pi * inset * inset,
            perimeter: 2 * span + 2 * .pi * inset,
            height: height, radius: radius)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        let repeated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(restored)
        #expect(repeated.brep == evaluated.brep)
    }

    @Test(.timeLimit(.minutes(1)))
    func prismFilletRejectsARadiusItsOwnProfileCannotCarry() throws {
        let circumradius = 0.02
        let height = 0.03
        let hexagon = try prismBody(extrudeDocument(
            sketch: regularPolygonProfileSketch(circumradius: circumradius, sides: 6),
            height: height))
        // A straight run of length L between two turns of phi is consumed at
        // L = r (tan(phi/2) + tan(phi/2)); a hexagon turns by 60 degrees at every corner.
        let widthLimit = circumradius * 3.0.squareRoot() / 2
        #expect(throws: KernelError.self) { try round(hexagon, radius: widthLimit) }
        #expect(throws: KernelError.self) { try round(hexagon, radius: height / 2) }
        #expect(throws: KernelError.self) { try round(hexagon, radius: ModelingTolerance.standard.distance) }
        #expect(throws: Never.self) { try round(hexagon, radius: min(widthLimit, height / 2) * 0.9) }

        let slot = try prismBody(extrudeDocument(
            sketch: slotProfileSketch(span: 0.03, radius: 0.01), height: 0.02))
        // An outward arc of radius R keeps a rolling ball only while R - 2r stays positive.
        #expect(throws: KernelError.self) { try round(slot, radius: 0.005) }
        #expect(throws: Never.self) { try round(slot, radius: 0.0045) }
    }

    @Test(.timeLimit(.minutes(1)))
    func prismFilletRejectsANonConvexProfile() throws {
        let body = try prismBody(extrudeDocument(sketch: reflexProfileSketch(), height: 0.01))
        #expect(throws: KernelError.self) { try round(body, radius: 0.001) }
    }

    // MARK: - Rounding

    private struct PrismBody {
        let model: BRepModel
        let bodyID: BodyID
    }

    private func prismBody(_ document: CADDocument) throws -> PrismBody {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document)
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        return PrismBody(model: evaluated.brep, bodyID: bodyID)
    }

    @discardableResult
    private func round(_ body: PrismBody, radius: Double) throws -> BRepModel {
        let request = try RoundedPrismFilletBuilder(tolerance: .standard).request(
            bodyID: body.bodyID, radius: radius, featureID: FeatureID(), model: body.model)
        return try DefaultBRepSewer().sew(request, tolerance: .standard).brep
    }

    /// Rounds one prism twice: once down the routed path, which hands a box and a cylinder to
    /// their own exact builders, and once through the general builder under test.
    private func roundedBothWays(
        _ document: CADDocument, radius: Double
    ) throws -> (routed: BRepModel, general: BRepModel) {
        var document = document
        let sourceID = try #require(document.designGraph.order.last)
        let body = try prismBody(document)
        _ = try appendAllEdgeFillet(radius: radius, after: sourceID, to: &document)
        let routed = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
            .evaluate(document)
        try routed.brep.validate(level: .volumetric, tolerance: .standard)
        let general = try round(body, radius: radius)
        try general.validate(level: .volumetric, tolerance: .standard)
        return (routed.brep, general)
    }

    private func expectSameSolid(
        _ first: BRepModel, _ second: BRepModel, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(first.faces.count == second.faces.count, sourceLocation: sourceLocation)
        #expect(first.edges.count == second.edges.count, sourceLocation: sourceLocation)
        #expect(first.vertices.count == second.vertices.count, sourceLocation: sourceLocation)
        #expect(planeCount(first) == planeCount(second), sourceLocation: sourceLocation)
        #expect(cylinderCount(first) == cylinderCount(second), sourceLocation: sourceLocation)
        #expect(sphereCount(first) == sphereCount(second), sourceLocation: sourceLocation)
        #expect(torusCount(first) == torusCount(second), sourceLocation: sourceLocation)
        let left = sortedPoints(first)
        let right = sortedPoints(second)
        #expect(left.count == right.count, sourceLocation: sourceLocation)
        #expect(zip(left, right).allSatisfy { ($0 - $1).length < 1e-9 },
                sourceLocation: sourceLocation)
        do {
            let volumes = try (first.volume(tolerance: .standard), second.volume(tolerance: .standard))
            #expect(abs(volumes.0 - volumes.1) < 1e-14, sourceLocation: sourceLocation)
        } catch {
            Issue.record(error, sourceLocation: sourceLocation)
        }
    }

    // MARK: - Measures

    /// The volume of a convex prism grown by a ball of radius `r`, by Steiner's formula, where
    /// the profile is the cap inset by `r` and the height is the span between the inset caps.
    private func steinerVolume(
        area: Double, perimeter: Double, height: Double, radius: Double
    ) -> Double {
        let span = height - 2 * radius
        return area * span
            + radius * (2 * area + perimeter * span)
            + radius * radius * (.pi * span + .pi / 2 * perimeter)
            + 4 * .pi / 3 * radius * radius * radius
    }

    private func sortedPoints(_ model: BRepModel) -> [Point3D] {
        model.vertices.values.map(\.point).sorted {
            if $0.x != $1.x { return $0.x < $1.x }
            if $0.y != $1.y { return $0.y < $1.y }
            return $0.z < $1.z
        }
    }

    private func planeCount(_ model: BRepModel) -> Int {
        model.faces.values.count {
            if case .plane = model.geometry.surfaces[$0.surfaceID] { return true }
            return false
        }
    }

    private func cylinderCount(_ model: BRepModel) -> Int {
        model.faces.values.count {
            if case .cylinder = model.geometry.surfaces[$0.surfaceID] { return true }
            return false
        }
    }

    private func sphereCount(_ model: BRepModel) -> Int {
        model.faces.values.count {
            if case .analytic(.sphere) = model.geometry.surfaces[$0.surfaceID] { return true }
            return false
        }
    }

    private func torusCount(_ model: BRepModel) -> Int {
        model.faces.values.count {
            if case .analytic(.torus) = model.geometry.surfaces[$0.surfaceID] { return true }
            return false
        }
    }

    // MARK: - Documents

    private func appendAllEdgeFillet(
        radius: Double, after sourceID: FeatureID, to document: inout CADDocument
    ) throws -> FeatureID {
        let id = FeatureID()
        let operation = FeatureOperation.fillet(.init(
            target: .init(featureID: sourceID), edges: [],
            radius: .constant(.length(radius, unit: .meter)), allEdges: true))
        let node = try FeatureNodeFactory.make(
            operation: operation, id: id, in: document, tolerance: .standard)
        document.designGraph.nodes[id] = node
        document.designGraph.order.append(id)
        document.designGraph.dependencies.append(.init(source: sourceID, target: id))
        document.designGraph.revision = document.designGraph.revision.advanced()
        return id
    }

    private func extrudeDocument(sketch: Sketch, height: Double) -> CADDocument {
        let sketchFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        return CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchFeatureID: FeatureNode(
                        id: sketchFeatureID, operation: .sketch(sketch),
                        outputs: [FeatureOutput(role: .profile)]),
                    extrudeFeatureID: FeatureNode(
                        id: extrudeFeatureID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchFeatureID),
                            distance: .constant(.length(height, unit: .meter)),
                            direction: .normal)),
                        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]),
                ],
                order: [sketchFeatureID, extrudeFeatureID],
                dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
                revision: DocumentRevision(2)
            )
        )
    }

    // MARK: - Profiles

    private func sketchPoint(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
    }

    /// Closes a counterclockwise ring of points into a sketch of lines.
    private func closedLineSketch(_ points: [SketchPoint]) -> Sketch {
        let ids = points.map { _ in SketchEntityID() }
        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []
        for index in points.indices {
            let next = (index + 1) % points.count
            entities[ids[index]] = .line(SketchLine(start: points[index], end: points[next]))
            constraints.append(.coincident(.lineEnd(ids[index]), .lineStart(ids[next])))
        }
        return Sketch(plane: .xy, entities: entities, constraints: constraints, dimensions: [])
    }

    private func rectangleProfileSketch(width: Double, depth: Double) -> Sketch {
        closedLineSketch([
            sketchPoint(-width / 2, -depth / 2), sketchPoint(width / 2, -depth / 2),
            sketchPoint(width / 2, depth / 2), sketchPoint(-width / 2, depth / 2),
        ])
    }

    private func regularPolygonProfileSketch(circumradius: Double, sides: Int) -> Sketch {
        closedLineSketch((0..<sides).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sides)
            return sketchPoint(circumradius * cos(angle), circumradius * sin(angle))
        })
    }

    private func circleProfileSketch(radius: Double) -> Sketch {
        let id = SketchEntityID()
        return Sketch(
            plane: .xy,
            entities: [id: .circle(SketchCircle(
                center: sketchPoint(0, 0), radius: .constant(.length(radius, unit: .meter))))],
            constraints: [], dimensions: [])
    }

    /// A stadium: two runs of length `span` closed by two semicircular ends of `radius`.
    private func slotProfileSketch(span: Double, radius: Double) -> Sketch {
        let bottomID = SketchEntityID()
        let rightID = SketchEntityID()
        let topID = SketchEntityID()
        let leftID = SketchEntityID()
        return Sketch(
            plane: .xy,
            entities: [
                bottomID: .line(SketchLine(
                    start: sketchPoint(-span / 2, -radius), end: sketchPoint(span / 2, -radius))),
                rightID: .arc(SketchArc(
                    center: sketchPoint(span / 2, 0),
                    radius: .constant(.length(radius, unit: .meter)),
                    startAngle: .constant(.angle(-90.0, unit: .degree)),
                    endAngle: .constant(.angle(90.0, unit: .degree)))),
                topID: .line(SketchLine(
                    start: sketchPoint(span / 2, radius), end: sketchPoint(-span / 2, radius))),
                leftID: .arc(SketchArc(
                    center: sketchPoint(-span / 2, 0),
                    radius: .constant(.length(radius, unit: .meter)),
                    startAngle: .constant(.angle(90.0, unit: .degree)),
                    endAngle: .constant(.angle(270.0, unit: .degree)))),
            ],
            constraints: [
                .coincident(.lineEnd(bottomID), .arcStart(rightID)),
                .coincident(.arcEnd(rightID), .lineStart(topID)),
                .coincident(.lineEnd(topID), .arcStart(leftID)),
                .coincident(.arcEnd(leftID), .lineStart(bottomID)),
            ],
            dimensions: [])
    }

    /// An L profile, whose inner corner turns the wrong way for a rolling ball.
    private func reflexProfileSketch() -> Sketch {
        closedLineSketch([
            sketchPoint(0, 0), sketchPoint(0.03, 0), sketchPoint(0.03, 0.01),
            sketchPoint(0.01, 0.01), sketchPoint(0.01, 0.03), sketchPoint(0, 0.03),
        ])
    }
}
