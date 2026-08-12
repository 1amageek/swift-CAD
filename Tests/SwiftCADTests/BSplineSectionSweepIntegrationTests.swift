import Foundation
import Testing
@testable import SwiftCAD
import CADTopology

@Suite("B-spline section sweep integration")
struct BSplineSectionSweepIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func curvedPathNormalSweepBuildsSectionInterpolatedSolid() throws {
        var profileSketchID: FeatureID?
        var editedPathID: FeatureID?
        let document = try CADDocument.millimeters(
            tolerance: .standard,
            named: "Section Sweep"
        ) { cad in
            let width = try cad.lengthParameter(named: "width", 8.0)
            let height = try cad.lengthParameter(named: "height", 6.0)

            let profile = try cad.sketch(on: .xy, named: "Profile") { sketch in
                sketch.rectangle(width: .parameter(width), height: .parameter(height))
            }
            profileSketchID = profile.featureID
            let startSource = try cad.sketch(on: .zx, named: "Bridge start source") { sketch in
                sketch.line(
                    from: sectionSweepBridgePoint(-20.0, 0.0),
                    to: sectionSweepBridgePoint(0.0, 0.0)
                )
            }
            let endSource = try cad.sketch(on: .zx, named: "Bridge end source") { sketch in
                sketch.line(
                    from: sectionSweepBridgePoint(20.0, 0.0),
                    to: sectionSweepBridgePoint(40.0, 0.0)
                )
            }
            let path = try cad.bridgeCurve(
                from: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: startSource.featureID),
                    end: .end,
                    requiredLevel: .tangent
                ),
                to: BridgeCurveEndpointReference(
                    curve: CurveOutputReference(featureID: endSource.featureID),
                    end: .start,
                    requiredLevel: .tangent
                ),
                continuityTolerances: .standard(modelingTolerance: .standard),
                named: "Bridge path"
            )
            let source = CurveOutputReference(featureID: path)
            let editedPath = try cad.editCurve(
                source,
                edits: [
                    .setControlPoint(CurveControlPointEdit(
                        target: CurveControlPointReference(curve: source, controlPointIndex: 1),
                        point: Point3D(x: 0.002, y: 0.0, z: 0.006)
                    ))
                ],
                named: "Edited path"
            )
            editedPathID = editedPath

            try cad.sweep(profile, along: editedPath, named: "Sweep")
        }

        let profileID = try #require(profileSketchID)
        let pathID = try #require(editedPathID)
        let plan = try SweepEvaluationPlanService().plan(
            document: document,
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            tolerance: .standard
        )
        #expect(plan.status == .supported)
        #expect(plan.pathShape == .curved)
        #expect(plan.evaluationKind == .bSplineSectionSweep)
        #expect(plan.outputTopologyKind == .bSplineSectionSweepSolid)

        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        #expect(evaluated.brep.bodies.count == 1)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)

        let pathCurve = try #require(evaluated.curves[pathID]?.first)
        let pathLength = sectionSweepPolylineLength(of: pathCurve.points)
        let profileArea = 0.008 * 0.006
        let expectedVolume = profileArea * pathLength
        let mesh = try #require(evaluated.meshes.values.first)
        let volume = sectionSweepMeshVolume(mesh)
        // The body interpolates exactly placed sections, so the enclosed
        // volume only approximates profile area times path length.
        #expect(abs(volume - expectedVolume) <= expectedVolume * 0.05)
    }
}

private func sectionSweepBridgePoint(_ z: Double, _ x: Double) -> SketchPoint {
    SketchPoint(
        x: .constant(.length(z, unit: .millimeter)),
        y: .constant(.length(x, unit: .millimeter))
    )
}

private func sectionSweepPolylineLength(of points: [Point3D]) -> Double {
    guard points.count >= 2 else {
        return 0.0
    }
    var length = 0.0
    for index in 1..<points.count {
        length += (points[index] - points[index - 1]).length
    }
    return length
}

private func sectionSweepMeshVolume(_ mesh: Mesh) -> Double {
    var total = 0.0
    var index = 0
    while index + 2 < mesh.indices.count {
        let first = mesh.positions[Int(mesh.indices[index])] - Point3D.origin
        let second = mesh.positions[Int(mesh.indices[index + 1])] - Point3D.origin
        let third = mesh.positions[Int(mesh.indices[index + 2])] - Point3D.origin
        total += first.cross(second).dot(third) / 6.0
        index += 3
    }
    return abs(total)
}
