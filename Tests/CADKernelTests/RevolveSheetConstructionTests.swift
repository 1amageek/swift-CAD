import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel
@testable import CADModeling

@Suite("Exact open-generator revolution", .timeLimit(.minutes(1)))
struct RevolveSheetConstructionTests {
    @Test(arguments: [Double.pi, -Double.pi, 2 * Double.pi], [false, true])
    func openGeneratorProducesUncappedSheet(angle: Double, rational: Bool) throws {
        let curve = rational
            ? BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.025, y: 0.01, z: 0),
                    Point3D(x: 0.03, y: 0.03, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)],
                weights: [1, 0.8, 1.2, 1])
            : BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)])
        let section = try section(curve)
        let result = try build(section, angle: angle)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == (abs(angle) > Double.pi ? 4 : 2))
        #expect(result.subshapes.keys.allSatisfy {
            $0.role != GeneratedSubshapeRole.startFace.rawValue && $0.role != GeneratedSubshapeRole.endFace.rawValue
        })
        for geometry in result.brep.geometry.surfaces.values {
            guard case .bSpline(let surface) = geometry else {
                Issue.record("Expected an exact rational rotation surface.")
                continue
            }
            for v in [0.15, 0.5, 0.85] {
                let original = try curve.point(at: v, tolerance: .standard)
                let rotated = try surface.point(u: 0.37, v: v, tolerance: .standard)
                #expect(abs(hypot(rotated.x, rotated.z) - original.x) < 1e-8)
                #expect(abs(rotated.y - original.y) < 1e-8)
            }
        }
    }

    @Test func axisCrossingAndInvalidAnglesAreRejected() throws {
        let crossing = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: -0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)]))
        #expect(throws: (any Error).self) { try build(crossing, angle: .pi) }
        let valid = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)]))
        for angle in [0, Double.infinity, Double.nan, 3 * Double.pi] {
            #expect(throws: (any Error).self) { try build(valid, angle: angle) }
        }
    }

    private func section(_ curve: BSplineCurve3D) throws -> EvaluatedCurve {
        EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [try curve.point(at: 0, tolerance: .standard), try curve.point(at: 1, tolerance: .standard)],
            plane: .xy, exactCurve: .bSpline(curve), exactParameterDomain: .closed(0, 1),
            exactPointParameters: [0, 1])
    }

    private func build(_ section: EvaluatedCurve, angle: Double) throws -> EvaluationResult {
        try CurvedRevolveBodyBuilder.buildSheet(axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: angle, section: section, featureID: FeatureID(),
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], tolerance: .standard), sewer: DefaultBRepSewer())
    }
}
