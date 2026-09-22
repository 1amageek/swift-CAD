import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel

@Suite("Involute gear section", .timeLimit(.minutes(1)))
struct InvoluteGearProfileTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

    private func profile(fillet: Double = 0.00076, budget: Int = 4096, allowance: Double = 1e-7) throws -> Profile {
        try InvoluteGearProfileBuilder().profile(sourceFeatureID: FeatureID(), toothCount: 32,
            baseRadius: 0.032 * cos(.pi / 9), pitchRadius: 0.032,
            tipRadius: 0.034, rootRadius: 0.0295, pitchToothAngle: .pi / 32,
            filletRadius: fillet, maximumError: allowance, maximumSegments: budget, tolerance: tolerance)
    }

    @Test func arcCoordinatesMatchIndependentHighPrecisionReference() throws {
        // mpmath 1.3.0, 100 decimal digits, exact binary64 dimension inputs:
        // rb=0x1.ecab6898b71c7p-6, tooth angle=0x1.921fb54442d18p-4.
        // Reference uses analytic circle midpoints at teeth 0, 7 and 31.
        let reference: [(Int, Double, Double)] = [
            (0, 0.02962127508954343122646109, -0.002128675290972473045066876),
            (1, 0.03400000000000000244249065, 0),
            (2, 0.02962127508954343122646109, 0.002128675290972473045066876),
            (3, 0.02935794943682980659739489, 0.002891505639722037606479529),
            (28, 0.007866597487891211831028038, 0.02863682664661548402089892),
            (29, 0.006633070948548361583347974, 0.03334669953370983766584908),
            (30, 0.003691050703603481548186027, 0.02946739454258267463040542),
            (31, 0.002891505639722037606479529, 0.02935794943682980659739489),
            (124, 0.02863682664661548402089892, -0.007866597487891211831028038),
            (125, 0.03334669953370983766584908, -0.006633070948548361583347974),
            (126, 0.02946739454258267463040542, -0.003691050703603481548186027),
            (127, 0.02935794943682980659739489, -0.002891505639722037606479529)
        ]
        for allowance in [1e-7, 1e-8] {
            let section = try profile(allowance: allowance)
            let arcs = section.boundarySegments.compactMap { segment -> ProfileCircularArcSegment? in
                if case .circularArc(let arc) = segment { return arc }
                return nil
            }
            #expect(arcs.count == 128)
            for (index, x, y) in reference {
                let arc = arcs[index]
                let radial = try (arc.start - arc.center).normalized(tolerance: tolerance.distance) * arc.radius
                let a = arc.sweepAngle / 2
                let midpoint = arc.center + Vector3D(x: cos(a) * radial.x - sin(a) * radial.y,
                    y: sin(a) * radial.x + cos(a) * radial.y, z: 0)
                #expect((midpoint - Point3D(x: x, y: y, z: 0)).length < allowance)
            }
        }
        for allowance in [0, -1, Double.nan, Double.leastNonzeroMagnitude, 1e-18] {
            #expect(throws: KernelError.self) { try self.profile(allowance: allowance) }
        }
    }

    @Test func closedBoundaryPitchThicknessAndRootTangency() throws {
        let profile = try profile()
        let segments = profile.boundarySegments
        func endpoints(_ segment: ProfileBoundarySegment) -> (Point3D, Point3D) {
            switch segment {
            case .line(let line): (line.start, line.end)
            case .circularArc(let arc): (arc.start, arc.end)
            case .spline(let spline): (spline.curve.controlPoints[0], spline.curve.controlPoints.last!)
            }
        }
        for index in segments.indices {
            let end = endpoints(segments[index]).1
            let start = endpoints(segments[(index + 1) % segments.count]).0
            #expect(end == start)
            if case .circularArc(let arc) = segments[index] {
                let v = arc.start - arc.center
                let rotated = arc.center + Vector3D(
                    x: cos(arc.sweepAngle) * v.x - sin(arc.sweepAngle) * v.y,
                    y: sin(arc.sweepAngle) * v.x + cos(arc.sweepAngle) * v.y, z: 0)
                #expect((rotated - arc.end).length < tolerance.distance)
            }
        }
        let pitchRoll = tan(Double.pi / 9)
        let pitchSpan = try #require(segments.compactMap { segment -> BSplineCurve3D? in
            guard case .spline(let spline) = segment,
                  case .closed(let a, let b) = spline.curve.domain,
                  a <= pitchRoll, pitchRoll <= b else { return nil }
            return spline.curve
        }.first)
        let pitchPoint = try pitchSpan.point(at: pitchRoll, tolerance: tolerance)
        #expect(abs(hypot(pitchPoint.x, pitchPoint.y) - 0.032) < 1e-7)
        #expect(abs(atan2(pitchPoint.y, pitchPoint.x) + .pi / 64) < 5e-6)
        guard case .circularArc(let rootFillet) = segments[0],
              case .spline(let leftFlank) = segments[1] else {
            Issue.record("Expected root fillet followed by involute flank"); return
        }
        let radial = rootFillet.end - rootFillet.center
        let arcTangent = try Vector3D(x: radial.y, y: -radial.x, z: 0).normalized(tolerance: tolerance.distance)
        let curveTangent = try (leftFlank.curve.controlPoints[1] - leftFlank.curve.controlPoints[0])
            .normalized(tolerance: tolerance.distance)
        #expect(arcTangent.dot(curveTangent) > 1 - 1e-10)
        #expect(abs(hypot(rootFillet.start.x, rootFillet.start.y) - 0.0295) < 1e-12)
        #expect(throws: KernelError.self) { try self.profile(fillet: 0.00001) }
        #expect(throws: KernelError.self) { try self.profile(budget: 100) }
    }

    @Test func nativeDoubleHelicalSolid() throws {
        let clock = ContinuousClock()
        let started = clock.now
        let gear = InvoluteGearFeature(toothCount: 32, dimensions: [
            .baseRadius: .constant(.length(0.032 * cos(.pi / 9), unit: .meter)),
            .pitchRadius: .constant(.length(0.032, unit: .meter)),
            .tipRadius: .constant(.length(0.034, unit: .meter)),
            .rootRadius: .constant(.length(0.0295, unit: .meter)),
            .filletRadius: .constant(.length(0.00076, unit: .meter)),
            .pitchToothAngle: .constant(.angle(.pi / 32, unit: .radian)),
            .width: .constant(.length(0.01, unit: .meter)),
            .twistAngle: .constant(.angle(0.1, unit: .radian)),
            .profileError: .constant(.length(1e-7, unit: .meter)),
            .sweepError: .constant(.length(1e-6, unit: .meter))
        ], doubleHelical: true)
        var document = CADDocument(units: .meters)
        let feature = try FeatureNodeFactory.make(operation: .involuteGear(gear),
            in: document, tolerance: tolerance)
        document.designGraph = DesignGraph(nodes: [feature.id: feature], order: [feature.id])
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(document))
        #expect(restored.designGraph == document.designGraph)
        let result = try DocumentEvaluator(tolerance: tolerance).evaluateExact(restored)
        let evaluated = clock.now
        print("Gear source round-trip and evaluation: \(started.duration(to: evaluated))")
        #expect(result.brep.bodies.count == 1)
        try result.brep.validate(level: .exact, tolerance: tolerance)
        let validated = clock.now
        print("Gear validation: \(evaluated.duration(to: validated))")
        defer { print("Gear tessellation attempt: \(validated.duration(to: clock.now))") }
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(model: result.brep)
        #expect(meshes.count == 1)
        for mesh in meshes.values { try mesh.validate(tolerance: tolerance) }
    }
}
