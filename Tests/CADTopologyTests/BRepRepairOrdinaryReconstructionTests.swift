import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Testing

@Suite("Ordinary original curve reconstruction", .timeLimit(.minutes(1)))
struct BRepRepairOrdinaryReconstructionTests {
    @Test
    func missingSpatialCurveReconstructsFromTheWholeIncidentPlaneChart() throws {
        var fixture = BRepRepairExecutionFixture.square()
        // Confirm that the authored source is valid before removing its spatial representation.
        try fixture.model.validate(level: .exact, tolerance: .standard)
        fixture.model.geometry.curves[fixture.curveIDs[0]] = nil
        let original = fixture.model
        let result = try DefaultBRepRepairer().repair(original,
            request: .init(actions: [.reconstructCurveRepresentations],
                validationRequest: .init(scopes: [.references, .pcurves])), tolerance: .standard)
        let edge = try #require(result.model.edges[fixture.edgeIDs[0]])
        let curve = try #require(result.model.geometry.curves[edge.curveID])
        let surface = try #require(result.model.geometry.surfaces[fixture.surfaceID])
        let loop = try #require(result.model.loops[fixture.loopID])
        let chart = try #require(loop.coedges[0].surfaceParameterCurve)
        guard case .surfaceLift(let lift) = curve else {
            Issue.record("The repair did not retain the incident plane's original surface lift.")
            return
        }
        #expect(lift.surface == surface && lift.parameterCurve == chart)
        #expect(edge.trim == CurveTrim(startParameter: 0, endParameter: 1))
        #expect(!result.before.isValid && result.after.isValid)
        #expect(result.diagnostics.isEmpty)
        #expect(result.model != original)
        #expect(fixture.model == original && original.geometry.curves[edge.curveID] == nil)
        #expect(result.changes.contains { $0.action == .reconstructCurveRepresentations
            && $0.generatedEntityIDs.contains(edge.curveID.description) })
        for face in result.model.faces.values {
            let host = try #require(result.model.geometry.surfaces[face.surfaceID])
            for loopID in face.loops {
                let incident = try #require(result.model.loops[loopID])
                for use in incident.coedges where use.edgeID == edge.id {
                    let local = try #require(use.surfaceParameterCurve)
                    try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: curve,
                        from: use.orientation == .forward ? 0 : 1,
                        to: use.orientation == .forward ? 1 : 0, surface: host, parameterCurve: local,
                        options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536),
                        tolerance: .standard)
                }
            }
        }
        #expect(try curve.point(at: 0, tolerance: .standard) == fixture.model.vertices[edge.startVertexID]?.point)
        #expect(try curve.point(at: 1, tolerance: .standard) == fixture.model.vertices[edge.endVertexID]?.point)
        try result.model.validate(level: .exact, tolerance: .standard)
    }
}
