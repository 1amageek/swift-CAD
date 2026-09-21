import Testing
import CADKernel
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

@Suite("Sheet extrude")
struct SheetExtrudeFeatureTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func sheetResultKindSewsTheWallWithoutTheTwoCaps() throws {
        let profileFeatureID = FeatureID()
        let profile = rectangleProfile(sourceFeatureID: profileFeatureID)
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            tolerance: tolerance
        )

        let solid = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: extrudeNode(profileFeatureID: profileFeatureID, resultKind: .solid),
            context: context
        )
        let sheet = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: extrudeNode(profileFeatureID: profileFeatureID, resultKind: .sheet),
            context: context
        )

        #expect(solid.brep.bodies.count == 1)
        #expect(solid.brep.bodies.values.first?.kind == .solid)
        #expect(solid.brep.faces.count == 6)

        #expect(sheet.brep.bodies.count == 1)
        #expect(sheet.brep.bodies.values.first?.kind == .sheet)
        // The wall alone: the same four side faces the solid has, minus the two caps.
        #expect(sheet.brep.faces.count == solid.brep.faces.count - 2)
        try sheet.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetExtrudeIsDeterministic() throws {
        let profileFeatureID = FeatureID()
        let profile = rectangleProfile(sourceFeatureID: profileFeatureID)
        let feature = extrudeNode(profileFeatureID: profileFeatureID, resultKind: .sheet)
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            tolerance: tolerance
        )

        let result = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature,
            context: context
        )
        let repeated = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature,
            context: context
        )

        #expect(result.brep == repeated.brep)
        #expect(result.lineage == repeated.lineage)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetExtrudeOfAProfileWithAHoleIsOneBodyOfTwoDisjointShells() throws {
        let profileFeatureID = FeatureID()
        let profile = Profile(
            sourceFeatureID: profileFeatureID,
            plane: .xy,
            outerLoop: ProfileLoop(vertices: [
                Point3D(x: -0.020, y: -0.020, z: 0.0),
                Point3D(x: 0.020, y: -0.020, z: 0.0),
                Point3D(x: 0.020, y: 0.020, z: 0.0),
                Point3D(x: -0.020, y: 0.020, z: 0.0),
            ]),
            innerLoops: [ProfileLoop(vertices: [
                Point3D(x: -0.010, y: -0.010, z: 0.0),
                Point3D(x: -0.010, y: 0.010, z: 0.0),
                Point3D(x: 0.010, y: 0.010, z: 0.0),
                Point3D(x: 0.010, y: -0.010, z: 0.0),
            ])]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            tolerance: tolerance
        )

        let sheet = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: extrudeNode(profileFeatureID: profileFeatureID, resultKind: .sheet),
            context: context
        )

        // Each boundary loop sweeps a wall of its own, and with no caps to join them the two
        // walls share no edge. That is one sheet body of two disjoint shells, which bound no
        // volume between them and claim none.
        #expect(sheet.brep.bodies.count == 1)
        #expect(sheet.brep.bodies.values.first?.kind == .sheet)
        #expect(sheet.brep.shells.count == 2)
        #expect(sheet.brep.faces.count == 8)
        try sheet.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func rectangleProfile(sourceFeatureID: FeatureID) -> Profile {
        Profile(
            sourceFeatureID: sourceFeatureID,
            plane: .xy,
            vertices: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.02, y: 0.0, z: 0.0),
                Point3D(x: 0.02, y: 0.012, z: 0.0),
                Point3D(x: 0.0, y: 0.012, z: 0.0),
            ]
        )
    }

    private func extrudeNode(
        profileFeatureID: FeatureID,
        resultKind: ExtrudeResultKind
    ) -> FeatureNode {
        FeatureNode(
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: profileFeatureID),
                distance: .constant(.length(0.03, unit: .meter)),
                resultKind: resultKind
            )),
            inputs: [FeatureInput(featureID: profileFeatureID, role: .profile)],
            outputs: [FeatureOutput(role: resultKind == .solid ? .body : .sheet)]
        )
    }
}
