import Testing
import CADCore
import CADIR
@testable import CADExchange

@Suite("Native stable selection package")
struct NativeStableSelectionPackageTests {
    @Test
    func roundTripsExactEdgeWitness() throws {
        let featureID = FeatureID()
        let edge = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 0.010, y: 0.0, z: 0.0)
            )
        )
        let vertex = StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "vertex", ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
        let document = CADDocument(
            units: .millimeters,
            selectionDimensions: [
                SelectionDimension(
                    name: "Exact edge witness",
                    kind: .distance,
                    first: .subshape(edge),
                    second: .subshape(vertex),
                    target: .constant(.length(0.0, unit: .millimeter))
                ),
            ]
        )
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()

        try store.writePackage(for: document, to: sink)
        let loaded = try store.loadDocument(from: BorrowedBytes(sink.bytes))

        #expect(loaded.selectionDimensions == document.selectionDimensions)
    }
}
