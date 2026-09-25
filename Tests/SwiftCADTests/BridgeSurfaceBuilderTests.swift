import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import SwiftCAD

@Suite("Bridge surface Builder")
struct BridgeSurfaceBuilderTests {
    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func bridgesTwoLiveSheetEdgesAndSurvivesCodableReplay() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        let sourceFeatureID = try builder.bSplineSurface(sourceSurface(), named: "Source sheet")
        let sourceDocument = try builder.build()
        let evaluator = DocumentEvaluator(
            tolerance: Self.testTolerance,
            artifactPolicy: .deferred
        )
        let source = try evaluator.evaluate(sourceDocument)
        let sourceBoundaries = try source.subshapes.entries.compactMap {
            subshapeID, topology -> StableSubshapeReference? in
            guard subshapeID.featureID == sourceFeatureID,
                  case .edge = topology else { return nil }
            return try source.stableSubshapeReference(for: subshapeID)
        }.sorted { $0.subshapeID < $1.subshapeID }
        let boundaries = Array(sourceBoundaries.prefix(2))
        #expect(boundaries.count == 2)
        let firstBoundary = try #require(boundaries.first)
        let secondBoundary = try #require(boundaries.dropFirst().first)

        let bridgeFeatureID = try builder.bridgeSurface(
            startBoundary: firstBoundary,
            endBoundary: secondBoundary,
            endOrientation: .reversed,
            named: "Exact boundary bridge"
        )
        let document = try builder.build(name: "Bridge surface")
        let replayed = try replayCodableCommands(from: document)
        #expect(
            try replayed.sourceFingerprint(tolerance: Self.testTolerance)
                == document.sourceFingerprint(tolerance: Self.testTolerance)
        )

        let evaluated = try evaluator.evaluate(replayed)
        try evaluated.brep.validate(level: .exact, tolerance: Self.testTolerance)
        #expect(evaluated.brep.bodies.count == 2)
        #expect(evaluated.brep.faces.count == 2)
        #expect(evaluated.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(source.brep.faces.allSatisfy { evaluated.brep.faces[$0.key] == $0.value })
        guard case let .bridgeSurface(bridge)? = replayed.designGraph.nodes[bridgeFeatureID]?.operation else {
            Issue.record("The persisted bridge must retain its two stable source boundaries.")
            return
        }
        #expect(bridge.startBoundary == firstBoundary)
        #expect(bridge.endBoundary == secondBoundary)
        #expect(bridge.endOrientation == .reversed)

        let bridgeFaceID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == bridgeFeatureID else { return false }
            if case .face = value { return true }
            return false
        }.flatMap { _, value -> FaceID? in
            if case let .face(faceID) = value { return faceID }
            return nil
        })
        let bridgeFace = try #require(evaluated.brep.faces[bridgeFaceID])
        guard case let .bSpline(surface) = try #require(
            evaluated.brep.geometry.surfaces[bridgeFace.surfaceID]
        ) else {
            Issue.record("A bridge between exact source boundaries must remain an exact B-spline sheet.")
            return
        }
        #expect(surface.vDegree == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func rationalBoundaryReferencesPreserveBothOrientations(reverseEnd: Bool, affine: Bool) throws {
        let start = BSplineCurve3D(
            degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0.5), Point3D(x: 2, y: 0, z: 0)],
            weights: [1, 0.6, 1]
        )
        let end = BSplineCurve3D(
            degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0, y: 2, z: 0), Point3D(x: 1, y: 2, z: 0.8), Point3D(x: 2, y: 2, z: 0)],
            weights: [0.8, 1.7, 1.2]
        )
        let sourceEnd = try reverseEnd ? end.reversed(tolerance: Self.testTolerance) : end
        func strip(_ curve: BSplineCurve3D, offset: Double) -> BSplineSurface3D {
            BSplineSurface3D(
                uDegree: curve.degree, vDegree: 1,
                uKnots: curve.knots, vKnots: [0, 0, 1, 1],
                controlPoints: [curve.controlPoints, curve.controlPoints.map { $0 + Vector3D(x: 0, y: offset, z: 0) }],
                weights: [curve.weights, curve.weights]
            )
        }
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        let startID = try builder.bSplineSurface(strip(start, offset: -0.25))
        let endID = try builder.bSplineSurface(strip(sourceEnd, offset: 0.25))
        let evaluator = DocumentEvaluator(tolerance: Self.testTolerance, artifactPolicy: .deferred)
        let source = try evaluator.evaluate(builder.build())
        func reference(_ featureID: FeatureID, y: Double) throws -> StableSubshapeReference {
            let entry = try #require(source.subshapes.entries.first { key, value in
                guard key.featureID == featureID, case let .edge(id) = value,
                      let edge = source.brep.edges[id],
                      let first = source.brep.vertices[edge.startVertexID]?.point,
                      let last = source.brep.vertices[edge.endVertexID]?.point else { return false }
                return first.y == y && last.y == y
            })
            return try source.stableSubshapeReference(for: entry.key)
        }
        let map = try affine ? AffineTransform3D(basisX: Vector3D(x: 1.2, y: 0, z: 0),
            basisY: Vector3D(x: 0.2, y: 2, z: 0), basisZ: .unitZ,
            translation: Vector3D(x: 0, y: 1, z: 0.2)) : nil
        let bridgeID = try builder.bridgeSurface(
            startBoundary: reference(startID, y: 0), endBoundary: reference(endID, y: 2),
            endOrientation: reverseEnd ? .reversed : .forward, endTransform: map
        )
        let document = try replayCodableCommands(from: builder.build())
        let result = try evaluator.evaluate(document)
        #expect(result.brep.bodies.count == 3)
        #expect(source.brep.bodies.allSatisfy { result.brep.bodies[$0.key] == $0.value })
        let topology = try #require(result.subshapes.entries.first { key, value in
            guard key.featureID == bridgeID, case .face = value else { return false }
            return true
        }?.value)
        guard case let .face(faceID) = topology,
              let face = result.brep.faces[faceID],
              case let .bSpline(surface)? = result.brep.geometry.surfaces[face.surfaceID] else {
            Issue.record("A rational bridge must retain an exact B-spline surface.")
            return
        }
        #expect(surface.isRational)
        for index in 0...16 {
            let u = Double(index) / 16
            let a = try start.point(at: u, tolerance: Self.testTolerance)
            let sourcePoint = try end.point(at: u, tolerance: Self.testTolerance)
            let b = map?.applying(to: sourcePoint) ?? sourcePoint
            for v in [0.0, 0.37, 1.0] {
                let actual = try surface.point(u: u, v: v, tolerance: Self.testTolerance)
                #expect((actual - (a + (b - a) * v)).length <= Self.testTolerance.distance)
            }
        }
        try result.brep.validate(level: .exact, tolerance: Self.testTolerance)
    }

    private func replayCodableCommands(from source: CADDocument) throws -> CADDocument {
        let editor = DocumentEditor()
        var result = CADDocument(units: source.units, metadata: source.metadata)
        for featureID in source.designGraph.order {
            let node = try #require(source.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            result = try editor.apply(decoded, to: result, tolerance: Self.testTolerance)
        }
        return result
    }

    private func sourceSurface() -> BSplineSurface3D {
        BSplineSurface3D.cubicBezierPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 2.0, y: 1.0, z: 0.5),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )
    }
}
