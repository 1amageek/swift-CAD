import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
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

        #expect(first.validatedBRep.validationLevel == .exact)
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
            bodyKind: .sheet,
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

    @Test(.timeLimit(.minutes(1)))
    func explicitSewingTopologyPreservesVoidOwnerAcrossStableSorting() throws {
        let featureID = FeatureID()
        let template = try #require(
            cylinderRequest(featureID: featureID).shells.first
        )
        let firstOuter = renamed(
            template,
            shellStableID: "middle-outer",
            identityPrefix: "first",
            orientation: .forward
        )
        let secondOuter = renamed(
            template,
            shellStableID: "z-last-outer",
            identityPrefix: "second",
            orientation: .forward
        )
        let secondVoid = renamed(
            template,
            shellStableID: "a-first-void",
            identityPrefix: "second-void",
            orientation: .reversed
        )
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyTopology: .solid(components: [
                BRepSewingSolidComponent(
                    outerShellStableID: firstOuter.stableID
                ),
                BRepSewingSolidComponent(
                    outerShellStableID: secondOuter.stableID,
                    voidShellStableIDs: [secondVoid.stableID]
                ),
            ]),
            shells: [secondOuter, secondVoid, firstOuter]
        )

        let result = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        let body = try #require(result.brep.bodies[result.bodyID])
        let components = try #require(body.solidComponents)
        let secondFaceReference = try #require(
            result.stableReferences[.face("second:\(template.patches[0].stableID)")]
        )
        let secondVoidFaceReference = try #require(
            result.stableReferences[.face("second-void:\(template.patches[0].stableID)")]
        )
        guard case .face(let secondFaceID) = secondFaceReference,
              case .face(let secondVoidFaceID) = secondVoidFaceReference else {
            Issue.record("Expected stable face references for the explicit component fixture.")
            return
        }
        let secondOuterShellID = try #require(result.brep.shells.values.first {
            $0.faceIDs.contains(secondFaceID)
        }?.id)
        let secondVoidShellID = try #require(result.brep.shells.values.first {
            $0.faceIDs.contains(secondVoidFaceID)
        }?.id)

        #expect(components.count == 2)
        #expect(components[1].outerShellID == secondOuterShellID)
        #expect(components[1].voidShellIDs == [secondVoidShellID])
        try result.brep.validate(level: .exact, tolerance: tolerance)

        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: result.bodyID,
            featureID: FeatureID(),
            from: result.brep,
            tolerance: tolerance
        )
        guard case .solid(let extractedComponents) = extraction.request.bodyTopology else {
            Issue.record("Expected extraction to preserve explicit solid topology.")
            return
        }
        let resewn = try DefaultBRepSewer().sew(
            extraction.request,
            tolerance: tolerance
        )
        let resewnBody = try #require(resewn.brep.bodies[resewn.bodyID])
        let resewnComponents = try #require(resewnBody.solidComponents)

        #expect(extractedComponents.map(\.voidShellStableIDs.count) == [0, 1])
        #expect(resewnComponents.map(\.voidShellIDs.count) == [0, 1])
    }

    @Test
    func sewsEquivalentAnalyticAndRationalSharedEdges() throws {
        let request = try cylinderRequest(
            featureID: FeatureID(),
            rationalTopCapEdges: true
        )

        let result = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )

        #expect(result.brep.edges.count == 12)
        for index in 0..<4 {
            #expect(
                result.stableReferences[.edge("top-cap-\(index)")]
                    == result.stableReferences[.edge("side-\(index)-top")]
            )
        }
        try result.brep.validate(level: .volumetric, tolerance: tolerance)
    }

    @Test
    func sewsOperandSwappedImplicitIntersectionEdges() throws {
        let featureID = FeatureID()
        let horizontal = implicitHorizontalSurface()
        let vertical = implicitVerticalSurface()
        let source = try certifiedImplicitIntersection(
            first: horizontal,
            second: vertical,
            surfacesAreSwapped: false
        )
        let swapped = try certifiedImplicitIntersection(
            first: vertical,
            second: horizontal,
            surfacesAreSwapped: true
        )
        let surface = Surface3D.bSpline(horizontal)
        let sourceCurve = Curve3D.implicit(source)
        let swappedCurve = Curve3D.implicit(swapped)
        let start = try sourceCurve.point(at: 0.0, tolerance: tolerance)
        let end = try sourceCurve.point(at: 1.0, tolerance: tolerance)
        let sourceShared = BRepSewingEdge(
            stableID: "source-shared",
            curve: sourceCurve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: source,
                    role: .first,
                    tolerance: tolerance
                )
            )
        )
        let swappedShared = BRepSewingEdge(
            stableID: "swapped-shared",
            curve: swappedCurve,
            startParameter: 1.0,
            endParameter: 0.0,
            startPoint: end,
            endPoint: start,
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: swapped,
                    role: .second,
                    startFraction: 1.0,
                    endFraction: 0.0,
                    tolerance: tolerance
                )
            )
        )
        let left = SurfaceParameter(u: 0.0, v: 0.5)
        let right = SurfaceParameter(u: 1.0, v: 0.5)
        let sourceStart = SurfaceParameter(u: 0.5, v: 0.0)
        let sourceEnd = SurfaceParameter(u: 0.5, v: 1.0)
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "implicit-sheet",
                patches: [
                    BRepSewingFacePatch(
                        stableID: "left-face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "left-loop",
                            role: .outer,
                            edges: [
                                sourceShared,
                                try liftedEdge(
                                    stableID: "left-upper",
                                    surface: surface,
                                    start: sourceEnd,
                                    end: left
                                ),
                                try liftedEdge(
                                    stableID: "left-lower",
                                    surface: surface,
                                    start: left,
                                    end: sourceStart
                                ),
                            ]
                        )]
                    ),
                    BRepSewingFacePatch(
                        stableID: "right-face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "right-loop",
                            role: .outer,
                            edges: [
                                swappedShared,
                                try liftedEdge(
                                    stableID: "right-lower",
                                    surface: surface,
                                    start: sourceStart,
                                    end: right
                                ),
                                try liftedEdge(
                                    stableID: "right-upper",
                                    surface: surface,
                                    start: right,
                                    end: sourceEnd
                                ),
                            ]
                        )]
                    ),
                ]
            )]
        )

        let result = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )

        #expect(result.brep.faces.count == 2)
        #expect(result.brep.edges.count == 5)
        #expect(
            result.stableReferences[.edge("source-shared")]
                == result.stableReferences[.edge("swapped-shared")]
        )
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test
    func sewsImplicitIntersectionEdgesRecertifiedWithDifferentFreeCoordinate() throws {
        let horizontal = implicitHorizontalSurface()
        let diagonal = implicitDiagonalParameterSurface()
        let source = try certifiedSecondVIntersection(
            first: horizontal,
            second: diagonal
        )
        let recertified = try certifiedFreeUIntersection(
            first: horizontal,
            second: diagonal
        )
        let surface = Surface3D.bSpline(diagonal)
        let sourceCurve = Curve3D.implicit(source)
        let recertifiedCurve = Curve3D.implicit(recertified)
        let start = try sourceCurve.point(at: 0.0, tolerance: tolerance)
        let end = try sourceCurve.point(at: 1.0, tolerance: tolerance)
        let sourceShared = BRepSewingEdge(
            stableID: "free-v-shared",
            curve: sourceCurve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: source,
                    role: .second,
                    tolerance: tolerance
                )
            )
        )
        let recertifiedShared = BRepSewingEdge(
            stableID: "free-u-shared",
            curve: recertifiedCurve,
            startParameter: 1.0,
            endParameter: 0.0,
            startPoint: end,
            endPoint: start,
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: recertified,
                    role: .second,
                    startFraction: 1.0,
                    endFraction: 0.0,
                    tolerance: tolerance
                )
            )
        )
        let left = SurfaceParameter(u: 0.0, v: 0.9)
        let right = SurfaceParameter(u: 1.0, v: 0.1)
        let sourceStart = SurfaceParameter(u: 0.1, v: 0.1)
        let sourceEnd = SurfaceParameter(u: 0.9, v: 0.9)
        let request = BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "free-coordinate-sheet",
                patches: [
                    BRepSewingFacePatch(
                        stableID: "free-v-face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "free-v-loop",
                            role: .outer,
                            edges: [
                                sourceShared,
                                try liftedEdge(
                                    stableID: "free-v-upper",
                                    surface: surface,
                                    start: sourceEnd,
                                    end: left
                                ),
                                try liftedEdge(
                                    stableID: "free-v-lower",
                                    surface: surface,
                                    start: left,
                                    end: sourceStart
                                ),
                            ]
                        )]
                    ),
                    BRepSewingFacePatch(
                        stableID: "free-u-face",
                        surface: surface,
                        orientation: .forward,
                        loops: [BRepSewingLoop(
                            stableID: "free-u-loop",
                            role: .outer,
                            edges: [
                                recertifiedShared,
                                try liftedEdge(
                                    stableID: "free-u-lower",
                                    surface: surface,
                                    start: sourceStart,
                                    end: right
                                ),
                                try liftedEdge(
                                    stableID: "free-u-upper",
                                    surface: surface,
                                    start: right,
                                    end: sourceEnd
                                ),
                            ]
                        )]
                    ),
                ]
            )]
        )

        let result = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )

        #expect(result.brep.faces.count == 2)
        #expect(result.brep.edges.count == 5)
        #expect(
            result.stableReferences[.edge("free-v-shared")]
                == result.stableReferences[.edge("free-u-shared")]
        )
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test
    func sewsImplicitIntersectionFaceWithSelectedUAsGraphCoordinate() throws {
        let horizontal = implicitHorizontalSurface()
        let diagonal = implicitDiagonalParameterSurface()
        let intersection = try certifiedFreeUIntersection(
            first: horizontal,
            second: diagonal
        )
        let surface = Surface3D.bSpline(diagonal)
        let curve = Curve3D.implicit(intersection)
        let start = SurfaceParameter(u: 0.1, v: 0.1)
        let end = SurfaceParameter(u: 0.9, v: 0.9)
        let corner = SurfaceParameter(u: 0.0, v: 0.9)
        let implicitEdge = BRepSewingEdge(
            stableID: "free-u-implicit",
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: intersection,
                    role: .second,
                    tolerance: tolerance
                )
            )
        )
        let request = BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "free-u-shell",
                patches: [BRepSewingFacePatch(
                    stableID: "free-u-face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "free-u-loop",
                        role: .outer,
                        edges: [
                            implicitEdge,
                            try liftedEdge(
                                stableID: "free-u-upper",
                                surface: surface,
                                start: end,
                                end: corner
                            ),
                            try liftedEdge(
                                stableID: "free-u-left",
                                surface: surface,
                                start: corner,
                                end: start
                            ),
                        ]
                    )]
                )]
            )]
        )

        let result = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )

        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 3)
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    @Test
    func sewsImplicitIntersectionFaceWhenOtherSurfaceOwnsGraphCoordinate() throws {
        let horizontal = implicitHorizontalSurface()
        let diagonal = implicitDiagonalParameterSurface()
        let intersection = try certifiedFreeUIntersection(
            first: horizontal,
            second: diagonal
        )
        let surface = Surface3D.bSpline(horizontal)
        let curve = Curve3D.implicit(intersection)
        let start = SurfaceParameter(u: 0.5, v: 0.1)
        let end = SurfaceParameter(u: 0.5, v: 0.9)
        let corner = SurfaceParameter(u: 0.0, v: 0.9)
        let implicitEdge = BRepSewingEdge(
            stableID: "cross-surface-free-coordinate",
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: intersection,
                    role: .first,
                    tolerance: tolerance
                )
            )
        )
        let request = BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "cross-surface-shell",
                patches: [BRepSewingFacePatch(
                    stableID: "cross-surface-face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "cross-surface-loop",
                        role: .outer,
                        edges: [
                            implicitEdge,
                            try liftedEdge(
                                stableID: "cross-surface-upper",
                                surface: surface,
                                start: end,
                                end: corner
                            ),
                            try liftedEdge(
                                stableID: "cross-surface-lower",
                                surface: surface,
                                start: corner,
                                end: start
                            ),
                        ]
                    )]
                )]
            )]
        )

        let result = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )

        #expect(result.brep.faces.count == 1)
        #expect(result.brep.edges.count == 3)
        try result.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func renamed(
        _ shell: BRepSewingShell,
        shellStableID: String,
        identityPrefix: String,
        orientation: Orientation
    ) -> BRepSewingShell {
        BRepSewingShell(
            stableID: shellStableID,
            patches: shell.patches.map { patch in
                BRepSewingFacePatch(
                    stableID: "\(identityPrefix):\(patch.stableID)",
                    surface: patch.surface,
                    orientation: patch.orientation,
                    loops: patch.loops.map { loop in
                        BRepSewingLoop(
                            stableID: "\(identityPrefix):\(loop.stableID)",
                            role: loop.role,
                            edges: loop.edges.map { edge in
                                BRepSewingEdge(
                                    stableID: "\(identityPrefix):\(edge.stableID)",
                                    curve: edge.curve,
                                    startParameter: edge.startParameter,
                                    endParameter: edge.endParameter,
                                    startPoint: edge.startPoint,
                                    endPoint: edge.endPoint,
                                    surfaceParameterCurve: edge.surfaceParameterCurve,
                                    parentSubshapeIDs: edge.parentSubshapeIDs,
                                    startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                    endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
                                )
                            }
                        )
                    },
                    parentSubshapeIDs: patch.parentSubshapeIDs
                )
            },
            orientation: orientation
        )
    }

    private func cylinderRequest(
        featureID: FeatureID,
        rationalTopCapEdges: Bool = false
    ) throws -> BRepSewingRequest {
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
            let start = parameters[index]
            let end = parameters[index + 1]
            let parent = SubshapeID(
                featureID: featureID,
                role: "source-top-edge",
                ordinal: index
            )
            if rationalTopCapEdges {
                let curve = Curve3D.bSpline(try rationalCircularArc(
                    center: topCenter,
                    startAngle: start,
                    endAngle: end
                ))
                return BRepSewingEdge(
                    stableID: "top-cap-\(index)",
                    curve: curve,
                    startParameter: 0.0,
                    endParameter: 1.0,
                    startPoint: try topCircle.point(
                        at: start,
                        tolerance: tolerance
                    ),
                    endPoint: try topCircle.point(
                        at: end,
                        tolerance: tolerance
                    ),
                    surfaceParameterCurve: try scopedHarmonicPcurve(
                        topPcurve,
                        start: start,
                        end: end
                    ),
                    parentSubshapeIDs: [parent]
                )
            }
            return try circularEdge(
                stableID: "top-cap-\(index)",
                curve: topCircle,
                start: start,
                end: end,
                pcurve: topPcurve,
                parent: parent
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

    private func certifiedImplicitIntersection(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        surfacesAreSwapped: Bool
    ) throws -> CertifiedImplicitIntersectionCurve {
        let split = 0.25
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [
                try implicitGraphCell(
                    first: first,
                    second: second,
                    lower: 0.0,
                    upper: split,
                    surfacesAreSwapped: surfacesAreSwapped
                ),
                try implicitGraphCell(
                    first: first,
                    second: second,
                    lower: split,
                    upper: 1.0,
                    surfacesAreSwapped: surfacesAreSwapped
                ),
            ],
            isClosed: false,
            tolerance: tolerance
        )
    }

    private func certifiedFreeUIntersection(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) throws -> CertifiedImplicitIntersectionCurve {
        let lower = 0.1
        let upper = 0.9
        func parameters(at value: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(u: value, v: value)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01),
                secondU: try ScalarInterval(lower: lower, upper: upper),
                secondV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01)
            ),
            freeParameter: .secondU,
            direction: .forward,
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: 0.5),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
    }

    private func certifiedSecondVIntersection(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) throws -> CertifiedImplicitIntersectionCurve {
        let lowerValue = 0.1
        let upperValue = 0.9
        func parameters(at value: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(u: value, v: value)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: 0.09, upper: 0.91),
                secondU: try ScalarInterval(lower: 0.09, upper: 0.91),
                secondV: try ScalarInterval(lower: lowerValue, upper: upperValue)
            ),
            freeParameter: .secondV,
            direction: .forward,
            lowerAnchor: try parameters(at: lowerValue),
            midpointAnchor: try parameters(at: 0.5),
            upperAnchor: try parameters(at: upperValue),
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
    }

    private func implicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        lower: Double,
        upper: Double,
        surfacesAreSwapped: Bool
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        func parameters(
            at value: Double
        ) throws -> SurfaceIntersectionParameterPair {
            if surfacesAreSwapped {
                return try SurfaceIntersectionParameterPair(
                    first: SurfaceParameter(
                        u: (value + 1.0) / 3.0,
                        v: 0.5
                    ),
                    second: SurfaceParameter(u: 0.5, v: value)
                )
            }
            return try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(
                    u: (value + 1.0) / 3.0,
                    v: 0.5
                )
            )
        }
        let midpoint = lower + (upper - lower) * 0.5
        let horizontalU = try ScalarInterval(lower: 0.49, upper: 0.51)
        let verticalU = try ScalarInterval(
            lower: (lower + 1.0) / 3.0 - 0.01,
            upper: (upper + 1.0) / 3.0 + 0.01
        )
        let fixedV = try ScalarInterval(lower: 0.49, upper: 0.51)
        let freeV = try ScalarInterval(lower: lower, upper: upper)
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: surfacesAreSwapped
                ? SurfaceIntersectionParameterBox(
                    firstU: verticalU,
                    firstV: fixedV,
                    secondU: horizontalU,
                    secondV: freeV
                )
                : SurfaceIntersectionParameterBox(
                    firstU: horizontalU,
                    firstV: freeV,
                    secondU: verticalU,
                    secondV: fixedV
                ),
            freeParameter: surfacesAreSwapped ? .secondV : .firstV,
            direction: .forward,
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: midpoint),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
    }

    private func liftedEdge(
        stableID: String,
        surface: Surface3D,
        start: SurfaceParameter,
        end: SurfaceParameter
    ) throws -> BRepSewingEdge {
        let pcurve = SurfaceParameterCurve.affine(
            origin: Point2D(x: start.u, y: start.v),
            direction: Point2D(
                x: end.u - start.u,
                y: end.v - start.v
            ),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: pcurve
        ))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private func implicitHorizontalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }

    private func implicitVerticalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.5, y: -1.0, z: -1.0),
                    Point3D(x: 0.5, y: 2.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: -1.0, z: 1.0),
                    Point3D(x: 0.5, y: 2.0, z: 1.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }

    private func implicitDiagonalParameterSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.5, y: 0.0, z: 0.0),
                    Point3D(x: 0.5, y: 1.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 1.0),
                    Point3D(x: 0.5, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }

    private func rationalCircularArc(
        center: Point3D,
        startAngle: Double,
        endAngle: Double
    ) throws -> BSplineCurve3D {
        let middleAngle = startAngle + (endAngle - startAngle) * 0.5
        let middleWeight = cos((endAngle - startAngle) * 0.5)
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                center + Vector3D(
                    x: cos(startAngle),
                    y: sin(startAngle),
                    z: 0.0
                ),
                center + Vector3D(
                    x: cos(middleAngle) / middleWeight,
                    y: sin(middleAngle) / middleWeight,
                    z: 0.0
                ),
                center + Vector3D(
                    x: cos(endAngle),
                    y: sin(endAngle),
                    z: 0.0
                ),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func scopedHarmonicPcurve(
        _ pcurve: SurfaceParameterCurve,
        start: Double,
        end: Double
    ) throws -> SurfaceParameterCurve {
        guard case let .harmonic(center, cosine, sine, _, _) = pcurve else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Scoped harmonic construction requires a harmonic pcurve."
            )
        }
        return .harmonic(
            center: center,
            cosine: cosine,
            sine: sine,
            startParameter: start,
            endParameter: end
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
