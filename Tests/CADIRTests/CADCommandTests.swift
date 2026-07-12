import CADCore
import CADIR
import Foundation
import Testing

struct CADCommandTests {
    @Test
    func sharedCommandRoundTripsWithStrictDiscriminator() throws {
        let command = CADCommand.suppressFeature(featureID: FeatureID(), suppressed: true)
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(CADCommand.self, from: data)
        #expect(decoded == command)
    }

    @Test
    func parameterCommandRoundTripsWithStrictDiscriminator() throws {
        let parameter = Parameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
        let command = CADCommand.upsertParameter(parameter)
        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )
        #expect(decoded == command)
    }

    @Test
    func featureRequestCarriesStableIdentityAndOperation() throws {
        let featureID = FeatureID()
        let request = FeatureRequest(
            id: featureID,
            name: "Development feature",
            operation: .polySpline(PolySplineFeature(
                sourceMesh: Mesh(
                    positions: [
                        Point3D(x: 0.0, y: 0.0, z: 0.0),
                        Point3D(x: 1.0, y: 0.0, z: 0.0),
                        Point3D(x: 0.0, y: 1.0, z: 0.0),
                    ],
                    normals: [],
                    indices: [0, 1, 2]
                )
            ))
        )
        let command = CADCommand.appendFeature(request)
        let decoded = try JSONDecoder().decode(
            CADCommand.self,
            from: JSONEncoder().encode(command)
        )
        #expect(decoded == command)
    }

    @Test
    func topologyLineageRequiresValidOutputIdentity() {
        let output = SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        let lineage = TopologyLineage(output: output, relation: .generated)
        #expect(lineage.isStructurallyValid)
    }

    @Test
    func subshapeSelectionRoundTripsByIdentity() throws {
        let selection = SelectionReference.subshape(
            SubshapeID(featureID: FeatureID(), role: "face", ordinal: 2)
        )
        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(SelectionReference.self, from: data)
        #expect(decoded == selection)
    }
}
