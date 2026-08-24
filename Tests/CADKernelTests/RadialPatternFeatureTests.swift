import Foundation
import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Radial pattern feature")
struct RadialPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsRigidlyRotatedExactInstancesWithSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.radialPattern(RadialPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(.pi / 2.0, unit: .radian)),
            count: 4
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 4)
        #expect(evaluated.brep.faces.count == 24)
        #expect(evaluated.brep.edges.count == 48)
        #expect(evaluated.brep.vertices.count == 32)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 4.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let points = evaluated.brep.vertices.values.map(\.point)
        #expect(abs(try #require(points.map(\.x).min()) + 0.220) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.x).max()) - 0.020) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).min()) + 0.120) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).max()) - 0.120) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 105)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 104)
    }

    @Test(.timeLimit(.minutes(1)))
    func unionsCoincidentFullTurnInstanceExactly() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.radialPattern(RadialPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(2.0 * .pi, unit: .radian)),
            count: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 0.040 * 0.020 * 0.010
        ) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter {
            $0.output.featureID == patternID
        }
        #expect(patternLineage.isEmpty == false)
        #expect(patternLineage.flatMap(\.parents).allSatisfy {
            $0.featureID == sourceFeatureID
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func rotatesExactCylinderAroundNonparallelPatternAxis() throws {
        let primitiveID = FeatureID()
        let patternID = FeatureID()
        var document = CADDocument(units: .meters)
        document.designGraph.nodes[primitiveID] = try FeatureNodeFactory.make(
            operation: .primitive(PrimitiveFeature(definition: .cylinder(
                CylinderPrimitive(
                    radius: .constant(.length(0.010, unit: .meter)),
                    height: .constant(.length(0.020, unit: .meter))
                )
            ))),
            id: primitiveID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.order.append(primitiveID)
        document.designGraph.nodes[patternID] = try FeatureNodeFactory.make(
            operation: .radialPattern(RadialPatternFeature(
                target: PatternTargetReference(featureID: primitiveID),
                axisOrigin: Point3D(x: -0.050, y: 0.0, z: 0.0),
                axisDirection: .unitY,
                angularSpacing: .constant(.angle(.pi, unit: .radian)),
                count: 2
            )),
            id: patternID,
            in: document,
            tolerance: .standard
        )
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: primitiveID,
            target: patternID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(
            try evaluated.brep.volume(tolerance: .standard)
                - 2.0 * Double.pi * 0.010 * 0.010 * 0.020
        ) <= 1.0e-12)
        let cylinderAxes = evaluated.brep.geometry.surfaces.values.compactMap {
            surface -> Vector3D? in
            guard case let .cylinder(cylinder) = surface else { return nil }
            return cylinder.axis
        }
        #expect(cylinderAxes.contains { ($0 - Vector3D.unitZ).length <= 1.0e-12 })
        #expect(cylinderAxes.contains { ($0 + Vector3D.unitZ).length <= 1.0e-12 })
    }

    @Test(.timeLimit(.minutes(1)))
    func rotatesRemainingAnalyticPrimitivesWithoutChangingExactVolume() throws {
        let cases: [(name: String, definition: PrimitiveDefinition, volume: Double)] = [
            (
                "cone",
                .cone(ConePrimitive(
                    baseRadius: .constant(.length(0.010, unit: .meter)),
                    height: .constant(.length(0.020, unit: .meter))
                )),
                Double.pi * 0.010 * 0.010 * 0.020 / 3.0
            ),
            (
                "sphere",
                .sphere(SpherePrimitive(
                    radius: .constant(.length(0.010, unit: .meter))
                )),
                4.0 * Double.pi * 0.010 * 0.010 * 0.010 / 3.0
            ),
            (
                "torus",
                .torus(TorusPrimitive(
                    majorRadius: .constant(.length(0.020, unit: .meter)),
                    minorRadius: .constant(.length(0.005, unit: .meter))
                )),
                2.0 * Double.pi * Double.pi * 0.020 * 0.005 * 0.005
            ),
        ]

        for fixture in cases {
            let primitiveID = FeatureID()
            let patternID = FeatureID()
            var document = CADDocument(units: .meters)
            document.designGraph.nodes[primitiveID] = try FeatureNodeFactory.make(
                operation: .primitive(PrimitiveFeature(definition: fixture.definition)),
                id: primitiveID,
                name: fixture.name,
                in: document,
                tolerance: .standard
            )
            document.designGraph.order.append(primitiveID)
            document.designGraph.nodes[patternID] = try FeatureNodeFactory.make(
                operation: .radialPattern(RadialPatternFeature(
                    target: PatternTargetReference(featureID: primitiveID),
                    axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
                    axisDirection: .unitY,
                    angularSpacing: .constant(.angle(.pi, unit: .radian)),
                    count: 2
                )),
                id: patternID,
                in: document,
                tolerance: .standard
            )
            document.designGraph.order.append(patternID)
            document.designGraph.dependencies.append(DependencyEdge(
                source: primitiveID,
                target: patternID
            ))
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluated = try DocumentEvaluator(
                tolerance: .standard,
                artifactPolicy: .deferred
            ).evaluate(document)
            try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
            #expect(evaluated.brep.shells.count == 2, "\(fixture.name) shell count")
            #expect(
                abs(try evaluated.brep.volume(tolerance: .standard) - 2.0 * fixture.volume)
                    <= 1.0e-12,
                "\(fixture.name) exact volume"
            )
        }
    }
}
