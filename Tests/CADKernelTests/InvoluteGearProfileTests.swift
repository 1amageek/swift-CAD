import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Involute gear section", .timeLimit(.minutes(3)))
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
        let document = try nativeGearDocument()
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

    @Test func nativeHelicalToothCapAdmitsRollingBallContacts() throws {
        let result = try DocumentEvaluator(tolerance: tolerance).evaluateExact(nativeGearDocument())
        let model = result.brep
        let shell = try #require(model.shells.values.first)
        let (flank, flankSurface, cap, capSurface) = try selectedNativeTooth(model: model, shell: shell)
        let radius = 0.0001
        let first = OffsetSurface3D(source: flankSurface,
            distance: flank.orientation == shell.orientation ? -radius : radius)
        let second = OffsetSurface3D(source: capSurface,
            distance: cap.orientation == shell.orientation ? -radius : radius)
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(first)), second: .procedural(.offset(second)), tolerance: tolerance)
        guard case let .curve(component) = try #require(intersections.first),
              case let .closed(lower, upper) = component.curve.parameterDomain else {
            Issue.record("The native tooth offsets must produce a bounded contact component.")
            return
        }
        let evaluator = try RollingBallSectionEvaluator(
            first: first, second: second, intersection: component, tolerance: tolerance)
        let blend = try evaluator.blendSurface(
            fromCurveParameter: lower, toCurveParameter: upper,
            options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let section = try evaluator.section(atCurveParameter: lower + (upper - lower) * fraction)
            let start = try blend.point(u: fraction, v: 0)
            let end = try blend.point(u: fraction, v: 1)
            #expect((start - section.firstContactPoint).length <= tolerance.distance)
            #expect((end - section.secondContactPoint).length <= tolerance.distance)
            #expect(abs((start - section.center).length - radius) <= tolerance.distance)
            #expect(abs((end - section.center).length - radius) <= tolerance.distance)
        }
        guard case let .surfaceLift(rail) = blend.firstContact else {
            Issue.record("The tooth contact must retain its source-surface parameter curve.")
            return
        }
        let boundary = BRepSewingEdge(
            stableID: "tooth-contact",
            curve: blend.firstContact, startParameter: 0, endParameter: 1,
            startPoint: try blend.firstContact.point(at: 0, tolerance: tolerance),
            endPoint: try blend.firstContact.point(at: 1, tolerance: tolerance),
            surfaceParameterCurve: rail.parameterCurve)
        #expect(throws: KernelError.self) {
            try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: .init(
                distance: tolerance.distance / 2, angle: tolerance.angle, relative: tolerance.relative))
                .build(faceID: flank.id, boundaries: [], model: model,
                       sourceSubshapes: result.subshapes.entries, tolerance: tolerance)
        }
        let removedOnLeft = try blend.crossSectionLiesOnLeft(of: .first,
            maximumSubdivisionDepth: 20, maximumCellCount: 65_536)
        let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
            faceID: flank.id,
            boundaries: [BooleanFaceArrangementBoundary(
                reference: .init(facePair: .init(targetFaceID: flank.id, toolFaceID: cap.id),
                                 componentID: .init(ordinal: 0)),
                segmentOrdinal: 0, faceID: flank.id, edge: boundary,
                forwardLeftAction: removedOnLeft ? .discard : .keep,
                forwardRightAction: removedOnLeft ? .keep : .discard)],
            model: model, sourceSubshapes: result.subshapes.entries,
            tolerance: tolerance)
        #expect(partition.isPartitioned)
        let patch = try #require(partition.patches.first)
        #expect(partition.patches.count == 1)
        #expect(patch.surface == flankSurface)
        try patch.validate(tolerance: tolerance)
        let capEdges = Set(cap.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] })
        let selectedEdges = flank.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] }
            .filter { capEdges.contains($0) }
        #expect(selectedEdges.count == 1)
        for edgeID in selectedEdges {
            let edge = try #require(model.edges[edgeID])
            let originalCurve = try #require(model.geometry.curves[edge.curveID])
            #expect(patch.loops.allSatisfy { loop in
                loop.edges.allSatisfy { $0.curve != originalCurve }
            })
        }
        let contactEdge = try #require(patch.loops.flatMap(\.edges).first {
            $0.curve == blend.firstContact
        })
        let blendPatch = try RollingBallBlendPatchBuilder().build(
            blend: blend, stableID: "native-tooth-blend",
            orientation: contactEdge.startParameter < contactEdge.endParameter ? .reversed : .forward,
            parentSubshapeIDs: result.subshapes.entries.compactMap { key, value in
                value == .face(flank.id) || value == .face(cap.id) ? key : nil
            }, tolerance: tolerance)
        let sewn = try DefaultBRepSewer().sew(.init(
            featureID: FeatureID(), bodyKind: .sheet,
            shells: [.init(stableID: "native-tooth-treatment", patches: [patch, blendPatch])]),
            tolerance: tolerance)
        try sewn.brep.validate(level: .exact, tolerance: tolerance)
        #expect(sewn.brep.faces.count == 2)
        let uses = Dictionary(grouping: sewn.brep.loops.values.flatMap(\.edges), by: \.edgeID)
        #expect(uses.values.filter { $0.count == 2 }.count == 1)
        let selectedEdgeID = try #require(selectedEdges.first)
        let tangentChain = try RollingBallTangentChainResolver().resolve(
            selectedEdge: selectedEdgeID, partner: cap.id, shell: shell,
            model: model, tolerance: tolerance)
        #expect(tangentChain.count >= 3)
        #expect(Set(tangentChain).count == tangentChain.count)
        let oppositeSeed = try #require(tangentChain.last)
        let reverseChain = try RollingBallTangentChainResolver().resolve(
            selectedEdge: oppositeSeed, partner: cap.id, shell: shell,
            model: model, tolerance: tolerance)
        #expect(Set(reverseChain) == Set(tangentChain))
        #expect(throws: KernelError.self) {
            try RollingBallTangentChainResolver().resolve(
                selectedEdge: EdgeID(), partner: cap.id, shell: shell,
                model: model, tolerance: tolerance)
        }
        var treatmentPatches = [patch, blendPatch]
        var nativeBlends = [selectedEdgeID: blend]
        for (chainIndex, chainEdgeID) in tangentChain.dropFirst().enumerated() {
            FileHandle.standardError.write(Data("Rolling-ball span \(chainIndex + 2)/\(tangentChain.count)\n".utf8))
            let endFaces = try shell.faceIDs.filter { faceID in
                guard faceID != flank.id, faceID != cap.id else { return false }
                let face = try #require(model.faces[faceID])
                return try face.loops.contains { loopID in
                    let loop = try #require(model.loops[loopID])
                    return loop.edges.contains { coedge in
                        coedge.edgeID == chainEdgeID
                    }
                }
            }
            #expect(endFaces.count == 1)
            let endFaceID = try #require(endFaces.first)
            let endFace = try #require(model.faces[endFaceID])
            let endSurface = try #require(model.geometry.surfaces[endFace.surfaceID])
            let nextOffset = OffsetSurface3D(source: endSurface,
                distance: endFace.orientation == shell.orientation ? -radius : radius)
            let nextIntersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .procedural(.offset(nextOffset)), second: .procedural(.offset(second)),
                tolerance: tolerance)
            guard case let .curve(nextComponent) = try #require(nextIntersections.first),
                  case let .closed(nextLower, nextUpper) = nextComponent.curve.parameterDomain else {
                Issue.record("A smooth neighbor must retain its bounded contact component."); return
            }
            let nextBlend = try RollingBallSectionEvaluator(first: nextOffset, second: second,
                intersection: nextComponent, tolerance: tolerance).blendSurface(
                    fromCurveParameter: nextLower, toCurveParameter: nextUpper,
                    options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
            nativeBlends[chainEdgeID] = nextBlend
            guard case let .surfaceLift(nextRail) = nextBlend.firstContact else {
                Issue.record("The neighboring contact must retain its source chart."); return
            }
            let nextContact = BRepSewingEdge(
                stableID: "tooth-contact:\(endFaceID)", curve: nextBlend.firstContact,
                startParameter: 0, endParameter: 1,
                startPoint: try nextBlend.firstContact.point(at: 0, tolerance: tolerance),
                endPoint: try nextBlend.firstContact.point(at: 1, tolerance: tolerance),
                surfaceParameterCurve: nextRail.parameterCurve)
            let nextRemovedOnLeft = try nextBlend.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: 20, maximumCellCount: 65_536)
            let nextPartition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: endFaceID,
                boundaries: [.init(
                    reference: .init(facePair: .init(targetFaceID: endFaceID, toolFaceID: cap.id),
                                     componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: endFaceID, edge: nextContact,
                    forwardLeftAction: nextRemovedOnLeft ? .discard : .keep,
                    forwardRightAction: nextRemovedOnLeft ? .keep : .discard)],
                model: model, sourceSubshapes: result.subshapes.entries, tolerance: tolerance)
            #expect(nextPartition.isPartitioned)
            #expect(nextPartition.patches.count == 1)
            let retainedNeighbor = try #require(nextPartition.patches.first)
            #expect(retainedNeighbor.surface == endSurface)
            treatmentPatches.append(retainedNeighbor)
            let retainedContact = try #require(retainedNeighbor.loops.flatMap(\.edges).first {
                $0.curve == nextBlend.firstContact
            })
            let nextPatch = try RollingBallBlendPatchBuilder().build(blend: nextBlend,
                stableID: "native-tooth-blend:\(endFaceID)",
                orientation: retainedContact.startParameter < retainedContact.endParameter ? .reversed : .forward,
                parentSubshapeIDs: result.subshapes.entries.compactMap { key, value in
                    value == .face(endFaceID) || value == .face(cap.id) ? key : nil
                }, tolerance: tolerance)
            treatmentPatches.append(nextPatch)
        }
        let continued = try DefaultBRepSewer().sew(.init(featureID: FeatureID(), bodyKind: .sheet,
            shells: [.init(stableID: "native-tooth-continuation", patches: treatmentPatches)]),
            tolerance: tolerance)
        try continued.brep.validate(level: .exact, tolerance: tolerance)
        #expect(continued.brep.faces.count == 2 * tangentChain.count)
        let continuedUses = Dictionary(grouping: continued.brep.loops.values.flatMap(\.edges), by: \.edgeID)
        #expect(continuedUses.values.filter { $0.count == 2 }.count == 3 * tangentChain.count - 2)
        try verifyNativeCap(model: model, cap: cap, sourceSubshapes: result.subshapes.entries,
            chain: Set(tangentChain), blends: nativeBlends, treatmentPatches: treatmentPatches)
    }

    private func verifyNativeCap(model: BRepModel, cap: Face,
        sourceSubshapes: [SubshapeID: TopologyReference], chain: Set<EdgeID>,
        blends: [EdgeID: RollingBallBlendSurface3D],
        treatmentPatches: [BRepSewingFacePatch]) throws {
        var blendPatches = treatmentPatches.filter {
            if case .procedural(.rollingBall) = $0.surface { return true }
            return false
        }
        try #require(blendPatches.count == chain.count)
        let source = try SourceBRepFacePatchBuilder().build(faceID: cap.id, stableID: "native-cap",
            from: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance).patch
        let loopIndex = try #require(cap.loops.firstIndex { id in
            model.loops[id]?.edges.contains { chain.contains($0.edgeID) } == true
        })
        let coedges = try #require(model.loops[cap.loops[loopIndex]]).edges
        let mask = coedges.map { chain.contains($0.edgeID) }
        let starts = coedges.indices.filter { mask[$0] && !mask[($0 + coedges.count - 1) % coedges.count] }
        try #require(starts.count == 1)
        var index = try #require(starts.first)
        var ordered: [Int] = []
        while mask[index] { ordered.append(index); index = (index + 1) % coedges.count }
        try #require(ordered.count == chain.count)
        var rails = try ordered.map { index in
            let blend = try #require(blends[coedges[index].edgeID])
            guard case .surfaceLift(let lift) = blend.secondContact else {
                throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                    message: "A native cap rail must retain its source-surface lift.")
            }
            return BRepSewingEdge(stableID: "cap-contact:\(coedges[index].edgeID)",
                curve: blend.secondContact, startParameter: 0, endParameter: 1,
                startPoint: try blend.secondContact.point(at: 0, tolerance: tolerance),
                endPoint: try blend.secondContact.point(at: 1, tolerance: tolerance),
                surfaceParameterCurve: lift.parameterCurve)
        }
        let adapter = BRepSewingPatchOrientationAdapter()
        func near(_ first: Point3D, _ second: Point3D) -> Bool {
            (first - second).length <= tolerance.distance
        }
        try #require(rails.count >= 2)
        if !near(rails[0].endPoint, rails[1].startPoint) && !near(rails[0].endPoint, rails[1].endPoint) {
            rails[0] = try adapter.reversed(rails[0], tolerance: tolerance)
        }
        for index in 1..<rails.count {
            if !near(rails[index - 1].endPoint, rails[index].startPoint) {
                rails[index] = try adapter.reversed(rails[index], tolerance: tolerance)
            }
            try #require(near(rails[index - 1].endPoint, rails[index].startPoint))
        }
        let fixtures = try ["NativeTerminalTrim", "SecondNativeTerminalTrim"].map { name in
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(name).json")
            return try JSONDecoder().decode(NativeTerminalTrimTests.Fixture.self, from: Data(contentsOf: url))
        }
        for position in [0, rails.count - 1] {
            let coedge = coedges[ordered[position]]
            let edge = try #require(model.edges[coedge.edgeID])
            let vertex = (position == 0) == (coedge.orientation == .forward)
                ? edge.startVertexID : edge.endVertexID
            let fixture = try #require(fixtures.first { $0.terminal.stableID == "terminal:\(vertex)" })
            guard case .implicit(let implicit) = fixture.terminal.curve,
                  case .procedural(.rollingBall(let extended)) = implicit.firstSurface else {
                Issue.record("The native terminal must retain its blend support."); return
            }
            let normal = try #require(blends[coedge.edgeID])
            let patchIndex = try #require(blendPatches.firstIndex {
                $0.surface == .procedural(.rollingBall(normal))
            })
            let originalPatch = blendPatches[patchIndex]
            let junction = position == 0 ? rails[position].endParameter : rails[position].startParameter
            let firstContact = try normal.firstContact.point(at: junction, tolerance: tolerance)
            let secondContact = try normal.secondContact.point(at: junction, tolerance: tolerance)
            let builder = RollingBallBlendPatchBuilder()
            let u = try builder.junctionParameter(blend: extended, firstContact: firstContact,
                secondContact: secondContact, tolerance: tolerance)
            let parameters = SurfaceParameterCurve.certifiedImplicit(try .init(
                intersection: implicit, role: .first, tolerance: tolerance))
            let atStart = try parameters.startParameter(tolerance: tolerance).v == 1
            let terminal = BRepSewingEdge(stableID: fixture.terminal.stableID, curve: fixture.terminal.curve,
                startParameter: 0, endParameter: 1, startPoint: fixture.terminal.startPoint,
                endPoint: fixture.terminal.endPoint, surfaceParameterCurve: parameters)
            let patch = try builder.build(blend: extended, stableID: "cap-terminal:\(position)",
                orientation: .forward, parentSubshapeIDs: [],
                uRange: ScalarInterval(lower: atStart ? 0 : u, upper: atStart ? u : 1),
                terminal: atStart ? .start(terminal) : .end(terminal), tolerance: tolerance)
            var rail = try #require(patch.loops.flatMap(\.edges).first { $0.curve == extended.secondContact })
            if !near(position == 0 ? rail.endPoint : rail.startPoint, secondContact) {
                rail = try adapter.reversed(rail, tolerance: tolerance)
            }
            try #require(near(position == 0 ? rail.endPoint : rail.startPoint, secondContact))
            rails[position] = rail
            blendPatches[patchIndex] = try builder.build(blend: extended,
                stableID: originalPatch.stableID, orientation: originalPatch.orientation,
                parentSubshapeIDs: originalPatch.parentSubshapeIDs,
                uRange: ScalarInterval(lower: atStart ? 0 : u, upper: atStart ? u : 1),
                terminal: atStart ? .start(terminal) : .end(terminal), tolerance: tolerance)
        }
        let replacements = Dictionary(uniqueKeysWithValues: ordered.indices.map {
            (source.loops[loopIndex].edges[ordered[$0]].stableID, rails[$0])
        })
        print("Rebuilding native cap with \(replacements.count) shared contact rails")
        let result = try RollingBallCapPatchBuilder().build(source: source,
            replacing: replacements, tolerance: tolerance)
        #expect(result.surface == source.surface)
        #expect(result.loops[loopIndex].edges.count == source.loops[loopIndex].edges.count)
        let identities = Set(replacements.keys)
        #expect(result.loops[loopIndex].edges.filter { identities.contains($0.stableID) }.count == rails.count)
        for edge in result.loops[loopIndex].edges {
            if let rail = replacements[edge.stableID] { #expect(edge.curve == rail.curve) }
        }
        try result.validate(tolerance: tolerance)
        let retainedFaces = treatmentPatches.filter {
            if case .procedural(.rollingBall) = $0.surface { return false }
            return true
        }
        let retained = try DefaultBRepSewer().sew(.init(featureID: FeatureID(), bodyKind: .sheet,
            shells: [.init(stableID: "native-cap-blends-and-retained-faces",
                patches: [result] + blendPatches + retainedFaces)]), tolerance: tolerance)
        try retained.brep.validate(level: .exact, tolerance: tolerance)
        #expect(retained.brep.faces.count == 2 * chain.count + 1)
        let retainedUses = Dictionary(grouping: retained.brep.loops.values.flatMap(\.edges), by: \.edgeID)
        #expect(retainedUses.values.filter { $0.count == 2 }.count == 4 * chain.count - 2)
    }

    @Test func nativeTerminalSurfacesAdmitBlendTrims() throws {
        try verifyNativeTerminal(index: 0)
    }

    @Test(arguments: [0, 1]) func nativeTerminalJoinsAdjacentBlend(index: Int) throws {
        let result = try DocumentEvaluator(tolerance: tolerance).evaluateExact(nativeGearDocument())
        let model = result.brep
        let shell = try #require(model.shells.values.first)
        let (flank, _, cap, capSurface) = try selectedNativeTooth(model: model, shell: shell)
        func edges(_ face: Face) -> Set<EdgeID> {
            Set(face.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] })
        }
        let seed = try #require(edges(flank).intersection(edges(cap)).first)
        let chain = Set(try RollingBallTangentChainResolver().resolve(selectedEdge: seed,
            partner: cap.id, shell: shell, model: model, tolerance: tolerance))
        var incidence: [VertexID: Int] = [:]
        for id in chain {
            let edge = try #require(model.edges[id])
            incidence[edge.startVertexID, default: 0] += 1
            incidence[edge.endVertexID, default: 0] += 1
        }
        let terminals = incidence.filter { $0.value == 1 }.map(\.key).sorted()
        try #require(terminals.count == 2)
        let terminal = terminals[index]
        let endEdgeID = try #require(chain.first { id in
            model.edges[id]?.startVertexID == terminal || model.edges[id]?.endVertexID == terminal
        })
        let endEdge = try #require(model.edges[endEdgeID])
        let junctionVertex = endEdge.startVertexID == terminal ? endEdge.endVertexID : endEdge.startVertexID
        let adjacentEdgeID = try #require(chain.first { id in
            id != endEdgeID && (model.edges[id]?.startVertexID == junctionVertex
                || model.edges[id]?.endVertexID == junctionVertex)
        })
        let source = try #require(model.faces.values.first { $0.id != cap.id && edges($0).contains(endEdgeID) })
        let adjacent = try #require(model.faces.values.first { $0.id != cap.id && edges($0).contains(adjacentEdgeID) })
        let seams = edges(source).intersection(edges(adjacent))
        try #require(seams.count == 1)
        let seamID = try #require(seams.first)
        let seamCurveID = try #require(model.edges[seamID]).curveID
        let seamCurve = try #require(model.geometry.curves[seamCurveID])
        let original = try SourceBRepFacePatchBuilder().build(faceID: adjacent.id,
            stableID: "adjacent-source", from: model, sourceSubshapes: result.subshapes.entries,
            tolerance: tolerance).patch
        let seam = try #require(original.loops.flatMap(\.edges).first { $0.curve == seamCurve })
        let first = OffsetSurface3D(source: try #require(model.geometry.surfaces[adjacent.surfaceID]),
            distance: adjacent.orientation == shell.orientation ? -0.0001 : 0.0001)
        let second = OffsetSurface3D(source: capSurface,
            distance: cap.orientation == shell.orientation ? -0.0001 : 0.0001)
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(first)), second: .procedural(.offset(second)), tolerance: tolerance)
        guard case .curve(let contact) = try #require(intersections.first),
              case .closed(let lower, let upper) = contact.curve.parameterDomain else {
            Issue.record("An adjacent native blend requires a bounded contact curve."); return
        }
        let neighbor = try RollingBallSectionEvaluator(first: first, second: second,
            intersection: contact, tolerance: tolerance).blendSurface(fromCurveParameter: lower,
                toCurveParameter: upper, options: .init(maximumSubdivisionDepth: 20,
                maximumCellCount: 65_536))
        let sharedEnds = try [0.0, 1.0].filter { parameter in
            try BRepSewingEdgeSubdivider().contains(neighbor.firstContact.point(at: parameter,
                tolerance: tolerance), on: seam, tolerance: tolerance)
        }
        try #require(sharedEnds.count == 1)
        let sharedEnd = try #require(sharedEnds.first)
        let fixtureName = index == 0 ? "NativeTerminalTrim" : "SecondNativeTerminalTrim"
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
        let fixture = try JSONDecoder().decode(NativeTerminalTrimTests.Fixture.self, from: Data(contentsOf: url))
        guard case .implicit(let implicit) = fixture.terminal.curve,
              case .procedural(.rollingBall(let blend)) = implicit.firstSurface else {
            Issue.record("The captured native terminal must retain its blend."); return
        }
        let firstContact = try neighbor.firstContact.point(at: sharedEnd, tolerance: tolerance)
        let secondContact = try neighbor.secondContact.point(at: sharedEnd, tolerance: tolerance)
        let builder = RollingBallBlendPatchBuilder()
        let u = try builder.junctionParameter(blend: blend, firstContact: firstContact,
            secondContact: secondContact, tolerance: tolerance)
        let boundary = BRepSewingEdge(stableID: fixture.terminal.stableID, curve: fixture.terminal.curve,
            startParameter: 0, endParameter: 1, startPoint: fixture.terminal.startPoint,
            endPoint: fixture.terminal.endPoint, surfaceParameterCurve: .certifiedImplicit(
                try .init(intersection: implicit, role: .first, tolerance: tolerance)))
        let trimmed = try builder.build(blend: blend, stableID: "terminal", orientation: .forward,
            parentSubshapeIDs: [], uRange: ScalarInterval(lower: index == 0 ? u : 0,
                upper: index == 0 ? 1 : u), terminal: index == 0 ? .end(boundary) : .start(boundary),
            tolerance: tolerance)
        let neighborPatch = try builder.build(blend: neighbor, stableID: "neighbor",
            orientation: (index == 0) == (sharedEnd == 1) ? .forward : .reversed,
            parentSubshapeIDs: [], tolerance: tolerance)
        let sewn = try DefaultBRepSewer().sew(.init(featureID: FeatureID(), bodyKind: .sheet,
            shells: [.init(stableID: "joined-native-terminal", patches: [trimmed, neighborPatch])]),
            tolerance: tolerance)
        try sewn.brep.validate(level: .exact, tolerance: tolerance)
        #expect(sewn.brep.faces.count == 2)
        let uses = Dictionary(grouping: sewn.brep.loops.values.flatMap(\.edges), by: \.edgeID)
        #expect(uses.values.filter { $0.count == 2 }.count == 1)
        #expect(throws: KernelError.self) {
            _ = try builder.junctionParameter(blend: blend, firstContact: firstContact,
                secondContact: secondContact + Vector3D(x: 0, y: 0, z: 0.001), tolerance: tolerance)
        }
    }

    @Test func secondNativeTerminalSurfaceAdmitsBlendTrim() throws {
        try verifyNativeTerminal(index: 1)
    }

    private func verifyNativeTerminal(index: Int) throws {
        let result = try DocumentEvaluator(tolerance: tolerance).evaluateExact(nativeGearDocument())
        let model = result.brep
        let shell = try #require(model.shells.values.first)
        let (flank, _, cap, _) = try selectedNativeTooth(model: model, shell: shell)
        let capEdges = cap.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] }
        let flankEdges = Set(flank.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] })
        let seed = try #require(capEdges.first { flankEdges.contains($0) })
        let chain = Set(try RollingBallTangentChainResolver().resolve(
            selectedEdge: seed, partner: cap.id, shell: shell, model: model, tolerance: tolerance))
        var incidence: [VertexID: Int] = [:]
        for edgeID in chain {
            let edge = try #require(model.edges[edgeID])
            incidence[edge.startVertexID, default: 0] += 1
            incidence[edge.endVertexID, default: 0] += 1
        }
        let terminals = Set(incidence.filter { $0.value == 1 }.map(\.key))
        #expect(terminals.count == 2)
        for vertexID in terminals.sorted().dropFirst(index).prefix(1) {
            let outside = try #require(capEdges.first { edgeID in
                guard !chain.contains(edgeID), let edge = model.edges[edgeID] else { return false }
                return edge.startVertexID == vertexID || edge.endVertexID == vertexID
            })
            let neighbors = shell.faceIDs.filter { faceID in
                guard faceID != cap.id, let face = model.faces[faceID] else { return false }
                return face.loops.contains { model.loops[$0]?.edges.contains { $0.edgeID == outside } == true }
            }
            #expect(neighbors.count == 1)
            let neighborID = try #require(neighbors.first)
            let neighbor = try #require(model.faces[neighborID])
            guard case .bSpline(let surface) = model.geometry.surfaces[neighbor.surfaceID] else {
                Issue.record("The native terminal must retain its original spline chart."); continue
            }
            let origin = surface.controlPoints[0][0]
            let alongU = surface.controlPoints[0][surface.uControlPointCount - 1] - origin
            let alongV = surface.controlPoints[surface.vControlPointCount - 1][0] - origin
            let normal = try alongU.cross(alongV).normalized(tolerance: tolerance.distance)
            let nonplanarity = surface.controlPoints.flatMap { $0 }.map {
                abs(($0 - origin).dot(normal))
            }.max() ?? 0
            #expect(nonplanarity > tolerance.distance)
            let inside = try #require(chain.first { edgeID in
                guard let edge = model.edges[edgeID] else { return false }
                return edge.startVertexID == vertexID || edge.endVertexID == vertexID
            })
            let sourceID = try #require(shell.faceIDs.first { faceID in
                guard faceID != cap.id, let face = model.faces[faceID] else { return false }
                return face.loops.contains { model.loops[$0]?.edges.contains { $0.edgeID == inside } == true }
            })
            let sourceFace = try #require(model.faces[sourceID])
            let originalSourceSurface = try #require(model.geometry.surfaces[sourceFace.surfaceID])
            guard case .bSpline(let sourceSpline) = originalSourceSurface,
                  case .closed(let u0, let u1) = sourceSpline.uDomain,
                  case .closed(let v0, let v1) = sourceSpline.vDomain else {
                Issue.record("A terminal computation requires its original finite chart."); return
            }
            let support = try sourceSpline.continuedBezierSupport(
                over: SurfaceParameterBox(u: ScalarInterval(lower: u0 - (u1 - u0) * 0.25,
                                                           upper: u1 + (u1 - u0) * 0.25),
                                          v: ScalarInterval(lower: v0, upper: v1)),
                maximumDeviation: tolerance.distance * 0.01, tolerance: tolerance)
            #expect(support.maximumDeviation <= tolerance.distance * 0.01)
            #expect(model.geometry.surfaces[sourceFace.surfaceID] == originalSourceSurface)
            let sourceSurface = Surface3D.bSpline(support.surface)
            let capSurface = try #require(model.geometry.surfaces[cap.surfaceID])
            let first = OffsetSurface3D(source: sourceSurface,
                distance: sourceFace.orientation == shell.orientation ? -0.0001 : 0.0001)
            let second = OffsetSurface3D(source: capSurface,
                distance: cap.orientation == shell.orientation ? -0.0001 : 0.0001)
            print("Terminal \(vertexID): intersecting extended offset supports")
            let contacts = try DefaultSurfaceSurfaceIntersector().intersections(
                first: .procedural(.offset(first)), second: .procedural(.offset(second)), tolerance: tolerance)
            guard case .curve(let contact) = try #require(contacts.first),
                  case .closed(let lower, let upper) = contact.curve.parameterDomain else {
                Issue.record("The terminal source must retain its bounded contact."); return
            }
            print("Terminal \(vertexID): constructing rolling-ball surface")
            let blend = try RollingBallSectionEvaluator(first: first, second: second,
                intersection: contact, tolerance: tolerance).blendSurface(
                    fromCurveParameter: lower, toCurveParameter: upper,
                    options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
            let blendSurface = Surface3D.procedural(.rollingBall(blend))
            guard case .closed(let neighborU0, let neighborU1) = surface.uDomain,
                  case .closed(let neighborV0, let neighborV1) = surface.vDomain else {
                Issue.record("A terminal neighbor requires a finite chart."); return
            }
            let neighborSupport = try surface.continuedBezierSupport(
                over: SurfaceParameterBox(
                    u: ScalarInterval(lower: neighborU0 - (neighborU1 - neighborU0) * 0.25,
                                      upper: neighborU1 + (neighborU1 - neighborU0) * 0.25),
                    v: ScalarInterval(lower: neighborV0 - (neighborV1 - neighborV0) * 0.25,
                                      upper: neighborV1 + (neighborV1 - neighborV0) * 0.25)),
                maximumDeviation: tolerance.distance * 0.01, tolerance: tolerance)
            #expect(model.geometry.surfaces[neighbor.surfaceID] == .bSpline(surface))
            print("Terminal \(vertexID): intersecting temporary neighboring support")
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: blendSurface, second: .bSpline(neighborSupport.surface),
                options: .init(maximumSubdivisionCells: 4096, maximumRootAttempts: 4096), tolerance: tolerance)
            #expect(intersections.count == 1)
            guard case .curve(let trim) = try #require(intersections.first) else {
                Issue.record("A terminal requires a curve shared with its original neighbor."); return
            }
            guard case .implicit(let implicit) = trim.truth else {
                Issue.record("A terminal trim requires its native implicit certificate."); return
            }
            let transferred = try implicit.transferredParameterCurve(on: .second, to: .bSpline(surface),
                maximumSpanCount: 4096,
                options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 16384), tolerance: tolerance)
            try transferred.validate(on: .bSpline(surface), tolerance: tolerance)
            let terminalEdge = BRepSewingEdge(stableID: "terminal:\(vertexID)",
                curve: trim.curve, startParameter: 0, endParameter: 1,
                startPoint: try trim.curve.point(at: 0, tolerance: tolerance),
                endPoint: try trim.curve.point(at: 1, tolerance: tolerance),
                surfaceParameterCurve: transferred)
            print("Terminal \(vertexID): partitioning original neighboring face")
            let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
                faceID: neighborID,
                boundaries: [.init(reference: .init(
                    facePair: .init(targetFaceID: neighborID, toolFaceID: cap.id), componentID: .init(ordinal: 0)),
                    segmentOrdinal: 0, faceID: neighborID, edge: terminalEdge,
                    forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true)],
                model: model, sourceSubshapes: result.subshapes.entries, tolerance: tolerance)
            #expect(partition.isPartitioned)
            #expect(partition.patches.count == 2)
            let corner = try #require(model.vertices[vertexID]).point
            let retained = partition.patches.filter { patch in
                !patch.loops.contains { loop in loop.edges.contains {
                    ($0.startPoint - corner).length <= tolerance.distance
                        || ($0.endPoint - corner).length <= tolerance.distance
                } }
            }
            #expect(retained.count == 1)
            for patch in retained {
                #expect(patch.surface == .bSpline(surface))
                try patch.validate(tolerance: tolerance)
            }
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let a = try trim.surfaceParameter(on: .first, atNormalizedFraction: fraction, tolerance: tolerance)
                let b = try trim.surfaceParameter(on: .second, atNormalizedFraction: fraction, tolerance: tolerance)
                let p = try blendSurface.point(u: a.u, v: a.v, tolerance: tolerance)
                let q = try surface.point(u: b.u, v: b.v, tolerance: tolerance)
                #expect((p - q).length <= tolerance.distance)
            }
        }
    }

    private func selectedNativeTooth(model: BRepModel, shell: Shell) throws -> (Face, Surface3D, Face, Surface3D) {
        var selected: (Face, Surface3D, Face, Surface3D)?
        for faceID in shell.faceIDs.sorted() {
            let face = try #require(model.faces[faceID])
            guard case let .bSpline(spline) = model.geometry.surfaces[face.surfaceID],
                  case let .closed(u0, u1) = spline.uDomain,
                  case let .closed(v0, v1) = spline.vDomain else { continue }
            let surface = Surface3D.bSpline(spline)
            let middle = try surface.point(u: (u0 + u1) / 2, v: (v0 + v1) / 2, tolerance: tolerance)
            let radial = hypot(middle.x, middle.y)
            guard radial > 0.032 * cos(.pi / 9), radial < 0.0339 else { continue }
            let edgeIDs = Set(face.loops.flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] })
            for capID in shell.faceIDs.sorted() {
                let cap = try #require(model.faces[capID])
                guard let capSurface = model.geometry.surfaces[cap.surfaceID],
                      case .plane = capSurface,
                      cap.loops.contains(where: { loopID in
                          model.loops[loopID]?.edges.contains(where: { edgeIDs.contains($0.edgeID) }) == true
                      }) else { continue }
                selected = (face, surface, cap, capSurface)
                break
            }
            if selected != nil { break }
        }
        return try #require(selected)
    }

    private func nativeGearDocument() throws -> CADDocument {
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
        // Keep ID-ordered tooth selection reproducible across diagnostic runs.
        let featureID = FeatureID(try #require(UUID(uuidString: "07225DE4-267A-43F0-A264-25646D03B227")))
        let feature = try FeatureNodeFactory.make(operation: .involuteGear(gear),
            id: featureID, in: document, tolerance: tolerance)
        document.designGraph = DesignGraph(nodes: [feature.id: feature], order: [feature.id])
        return document
    }
}
