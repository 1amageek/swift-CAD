import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Exact B-rep sewing")
struct BRepSewerTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func sewsDeterministicExactCylinderWithFaceLocalPcurves() throws {
        let featureID = FeatureID()
        let request = try cylinderRequest(featureID: featureID)
        let sewer = DefaultBRepSewer()

        let first = try sewer.sew(request, tolerance: tolerance)
        let second = try sewer.sew(request, tolerance: tolerance)

        #expect(first.brep == second.brep)
        #expect(first.bodyID == second.bodyID)
        #expect(first.subshapes == second.subshapes)
        #expect(first.lineage == second.lineage)
        #expect(first.brep.bodies.count == 1)
        #expect(first.brep.shells.count == 1)
        #expect(first.brep.faces.count == 6)
        #expect(first.brep.loops.count == 6)
        #expect(first.brep.edges.count == 12)
        #expect(first.brep.vertices.count == 8)
        #expect(first.brep.loops.values.flatMap(\.edges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        let hasValidLineage = first.lineage.values.allSatisfy { $0.isStructurallyValid }
        #expect(hasValidLineage)
        try first.brep.validate(level: .exact, tolerance: tolerance)

        var reconstructedPcurves = first.brep
        for loopID in Array(reconstructedPcurves.loops.keys) {
            guard var loop = reconstructedPcurves.loops[loopID] else { continue }
            for index in loop.coedges.indices {
                loop.coedges[index].surfaceParameterCurve = nil
            }
            reconstructedPcurves.loops[loopID] = loop
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &reconstructedPcurves,
            tolerance: tolerance
        )
        try reconstructedPcurves.validate(level: .exact, tolerance: tolerance)
        #expect(reconstructedPcurves.loops.values.flatMap(\.edges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })

        try first.brep.validate(level: .volumetric, tolerance: tolerance)
        #expect(abs(try first.brep.volume(tolerance: tolerance) - 2.0 * Double.pi) <= tolerance.distance)
    }

    @Test
    func rejectsOpenSolidBeforePublishingTopology() throws {
        let featureID = FeatureID()
        let complete = try cylinderRequest(featureID: featureID)
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "cylinder-shell",
                patches: Array(complete.shells[0].patches.dropLast())
            )]
        )

        do {
            _ = try DefaultBRepSewer().sew(request, tolerance: tolerance)
            Issue.record("An open solid must not be published as a sewn B-rep.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .topologyFailure)
        }
    }

    @Test
    func preservesReversedShellOrientationAcrossExtractionAndResewing() throws {
        let sourceRequest = try cylinderRequest(featureID: FeatureID())
        let reversedRequest = BRepSewingRequest(
            featureID: sourceRequest.featureID,
            bodyKind: sourceRequest.bodyKind,
            shells: sourceRequest.shells.map { shell in
                BRepSewingShell(
                    stableID: shell.stableID,
                    patches: shell.patches,
                    orientation: .reversed
                )
            }
        )
        let source = try DefaultBRepSewer().sew(reversedRequest, tolerance: tolerance)
        let sourceBody = try #require(source.brep.bodies[source.bodyID])
        let sourceShellID = try #require(sourceBody.shellIDs.first)
        #expect(source.brep.shells[sourceShellID]?.orientation == .reversed)

        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: source.bodyID,
            featureID: FeatureID(),
            from: source.brep,
            tolerance: tolerance
        )
        #expect(extraction.request.shells.count == 1)
        #expect(extraction.request.shells[0].orientation == .reversed)

        let resewn = try DefaultBRepSewer().sew(extraction.request, tolerance: tolerance)
        let resewnBody = try #require(resewn.brep.bodies[resewn.bodyID])
        let resewnShellID = try #require(resewnBody.shellIDs.first)
        #expect(resewn.brep.shells[resewnShellID]?.orientation == .reversed)
        try resewn.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func cylinderRequest(featureID: FeatureID) throws -> BRepSewingRequest {
        let height = 2.0
        let bottomCenter = Point3D(x: 0.0, y: 0.0, z: -1.0)
        let topCenter = Point3D(x: 0.0, y: 0.0, z: 1.0)
        let cylinderSurface = Surface3D.cylinder(Cylinder3D(
            origin: bottomCenter,
            axis: .unitZ,
            radius: 1.0
        ))
        let bottomSurface = Surface3D.plane(Plane3D(origin: bottomCenter, normal: -Vector3D.unitZ))
        let topSurface = Surface3D.plane(Plane3D(origin: topCenter, normal: .unitZ))
        let bottomCircle = Curve3D.circle(Circle3D(
            center: bottomCenter,
            normal: .unitZ,
            radius: 1.0
        ))
        let topCircle = Curve3D.circle(Circle3D(
            center: topCenter,
            normal: .unitZ,
            radius: 1.0
        ))
        let quarter = Double.pi / 2.0
        let parameters = (0...4).map { Double($0) * quarter }
        let bottomPcurve = try harmonicPcurve(for: bottomCircle, on: bottomSurface)
        let topPcurve = try harmonicPcurve(for: topCircle, on: topSurface)

        let bottomEdges = try (0..<4).reversed().map { index in
            try circularEdge(
                stableID: "bottom-cap-\(index)",
                curve: bottomCircle,
                start: parameters[index + 1],
                end: parameters[index],
                pcurve: bottomPcurve,
                parent: SubshapeID(featureID: featureID, role: "source-bottom-edge", ordinal: index)
            )
        }
        let topEdges = try (0..<4).map { index in
            try circularEdge(
                stableID: "top-cap-\(index)",
                curve: topCircle,
                start: parameters[index],
                end: parameters[index + 1],
                pcurve: topPcurve,
                parent: SubshapeID(featureID: featureID, role: "source-top-edge", ordinal: index)
            )
        }
        var patches = [
            BRepSewingFacePatch(
                stableID: "bottom-cap",
                surface: bottomSurface,
                orientation: .forward,
                loops: [BRepSewingLoop(stableID: "bottom-cap-loop", role: .outer, edges: bottomEdges)],
                parentSubshapeIDs: [SubshapeID(featureID: featureID, role: "source-face", ordinal: 0)]
            ),
        ]
        for index in 0..<4 {
            let start = parameters[index]
            let end = parameters[index + 1]
            let bottomArc = try circularEdge(
                stableID: "side-\(index)-bottom",
                curve: bottomCircle,
                start: start,
                end: end,
                pcurve: .constantV(v: 0.0, uStart: start, uEnd: end),
                parent: SubshapeID(featureID: featureID, role: "source-bottom-edge", ordinal: index)
            )
            let endVertical = try verticalEdge(
                stableID: "side-\(index)-end",
                cylinderSurface: cylinderSurface,
                angle: end,
                startHeight: 0.0,
                endHeight: height,
                parent: SubshapeID(featureID: featureID, role: "source-vertical-edge", ordinal: (index + 1) % 4)
            )
            let topArc = try circularEdge(
                stableID: "side-\(index)-top",
                curve: topCircle,
                start: end,
                end: start,
                pcurve: .constantV(v: height, uStart: end, uEnd: start),
                parent: SubshapeID(featureID: featureID, role: "source-top-edge", ordinal: index)
            )
            let startVertical = try verticalEdge(
                stableID: "side-\(index)-start",
                cylinderSurface: cylinderSurface,
                angle: start,
                startHeight: height,
                endHeight: 0.0,
                parent: SubshapeID(featureID: featureID, role: "source-vertical-edge", ordinal: index)
            )
            patches.append(BRepSewingFacePatch(
                stableID: "side-\(index)",
                surface: cylinderSurface,
                orientation: .forward,
                loops: [BRepSewingLoop(
                    stableID: "side-\(index)-loop",
                    role: .outer,
                    edges: [bottomArc, endVertical, topArc, startVertical]
                )],
                parentSubshapeIDs: [SubshapeID(featureID: featureID, role: "source-face", ordinal: index + 1)]
            ))
        }
        patches.append(BRepSewingFacePatch(
            stableID: "top-cap",
            surface: topSurface,
            orientation: .forward,
            loops: [BRepSewingLoop(stableID: "top-cap-loop", role: .outer, edges: topEdges)],
            parentSubshapeIDs: [SubshapeID(featureID: featureID, role: "source-face", ordinal: 5)]
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "cylinder-shell", patches: patches)]
        )
    }

    private func circularEdge(
        stableID: String,
        curve: Curve3D,
        start: Double,
        end: Double,
        pcurve: SurfaceParameterCurve,
        parent: SubshapeID
    ) throws -> BRepSewingEdge {
        let scopedPcurve: SurfaceParameterCurve
        guard case let .harmonic(center, cosine, sine, _, _) = pcurve else {
            return BRepSewingEdge(
                stableID: stableID,
                curve: curve,
                startParameter: start,
                endParameter: end,
                startPoint: try curve.point(at: start, tolerance: tolerance),
                endPoint: try curve.point(at: end, tolerance: tolerance),
                surfaceParameterCurve: pcurve,
                parentSubshapeIDs: [parent]
            )
        }
        scopedPcurve = .harmonic(
            center: center,
            cosine: cosine,
            sine: sine,
            startParameter: start,
            endParameter: end
        )
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: scopedPcurve,
            parentSubshapeIDs: [parent]
        )
    }

    private func verticalEdge(
        stableID: String,
        cylinderSurface: Surface3D,
        angle: Double,
        startHeight: Double,
        endHeight: Double,
        parent: SubshapeID
    ) throws -> BRepSewingEdge {
        let bottom = try cylinderSurface.point(u: angle, v: 0.0, tolerance: tolerance)
        let curve = Curve3D.line(Line3D(origin: bottom, direction: .unitZ))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: startHeight,
            endParameter: endHeight,
            startPoint: try curve.point(at: startHeight, tolerance: tolerance),
            endPoint: try curve.point(at: endHeight, tolerance: tolerance),
            surfaceParameterCurve: .constantU(
                u: angle,
                vStart: startHeight,
                vEnd: endHeight
            ),
            parentSubshapeIDs: [parent]
        )
    }

    private func harmonicPcurve(
        for circle: Curve3D,
        on surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        guard case let .circle(definition) = circle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Harmonic pcurve construction requires an exact circle."
            )
        }
        let center = try surface.parameterProjection(of: definition.center, tolerance: tolerance)
        let cosinePoint = try surface.parameterProjection(
            of: circle.point(at: 0.0, tolerance: tolerance),
            tolerance: tolerance
        )
        let sinePoint = try surface.parameterProjection(
            of: circle.point(at: Double.pi / 2.0, tolerance: tolerance),
            tolerance: tolerance
        )
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosinePoint.u - center.u, y: cosinePoint.v - center.v),
            sine: Point2D(x: sinePoint.u - center.u, y: sinePoint.v - center.v),
            startParameter: 0.0,
            endParameter: Double.pi * 2.0
        )
    }
}
