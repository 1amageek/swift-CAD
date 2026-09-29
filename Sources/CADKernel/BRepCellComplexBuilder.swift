import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// The solids a set of face patches enclose, given patches that meet only along their boundary
/// edges (every crossing already split into edges). Each bounded region the patches divide space
/// into is one solid component of the result.
///
/// Patches with an edge no other patch shares cannot bound a region and are dropped, repeatedly.
/// Every remaining patch has two sides; around each edge the patches are ordered by angle, and the
/// two sides facing each wedge between consecutive patches bound the same region. The connected
/// sides are closed shells, oriented with normals out of their region. A shell a point just inside
/// its region lies within is the outer shell of a bounded region; any other shell bounds a void of
/// the smallest outer shell around it, or the unbounded region outside everything, which is
/// dropped.
struct BRepCellComplexBuilder {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    func request(patches: [BRepSewingFacePatch], featureID: FeatureID) throws -> BRepSewingRequest {
        try tolerance.validate()
        let fan = BRepSewingEdgeFan(tolerance: tolerance)
        var kept = patches.sorted { $0.stableID < $1.stableID }
        var groups: [[BRepSewingEdgeFan.Use]] = []
        // Drop patches with a free edge until none has one.
        while true {
            groups = try fan.groups(of: kept)
            let dangling = Set(groups.filter { $0.count == 1 }.map { $0[0].patchIndex })
            guard dangling.isEmpty == false else { break }
            kept = kept.enumerated().filter { dangling.contains($0.offset) == false }.map(\.element)
            guard kept.isEmpty == false else {
                throw KernelError(phase: .topology, code: .emptyResult, tolerance: tolerance,
                    message: "The operands enclose no region.")
            }
        }
        // Side 2i is patch i's front (its normal side), 2i + 1 its back.
        var parent = Array(0..<(2 * kept.count))
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        for group in groups {
            let rays = try fan.rays(group, patches: kept)
            for index in rays.indices {
                let next = (index + 1) % rays.count
                // The wedge after ray `index` and before ray `next`.
                let first = 2 * rays[index].use.patchIndex + (rays[index].frontFacesAfter ? 0 : 1)
                let second = 2 * rays[next].use.patchIndex + (rays[next].frontFacesAfter ? 1 : 0)
                union(first, second)
            }
        }
        var sidesByShell: [Int: [Int]] = [:]
        for side in 0..<(2 * kept.count) {
            sidesByShell[find(side), default: []].append(side)
        }
        // A side's normal points into its region, so the region's outward shell turns it: a front
        // side is its patch reversed, a back side the patch as it is.
        let adapter = BRepSewingPatchOrientationAdapter()
        var shells: [BRepSewingShell] = []
        for (index, sides) in sidesByShell.values.sorted(by: { $0.min()! < $1.min()! }).enumerated() {
            let shellID = "cell:shell:\(index)"
            let shellPatches = try sides.sorted().map { side -> BRepSewingFacePatch in
                let patch = kept[side / 2]
                let isFront = side.isMultiple(of: 2)
                let turned = try adapter.reorient(
                    patch,
                    to: isFront ? opposite(patch.orientation) : patch.orientation,
                    tolerance: tolerance
                )
                return renamed(turned, suffix: isFront ? "front" : "back")
            }
            shells.append(BRepSewingShell(stableID: shellID, patches: shellPatches))
        }
        let classified = try classify(shells, featureID: featureID)
        guard classified.isEmpty == false else {
            throw KernelError(phase: .topology, code: .emptyResult, tolerance: tolerance,
                message: "The operands enclose no region.")
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyTopology: .solid(components: classified.map {
                BRepSewingSolidComponent(outerShellStableID: $0.outer.stableID, voidShellStableIDs: $0.voids.map(\.stableID))
            }),
            shells: classified.flatMap { [$0.outer] + $0.voids }
        )
    }

    /// Outer shells of bounded regions with the voids each holds; the unbounded region's shells
    /// are dropped.
    private func classify(_ shells: [BRepSewingShell], featureID: FeatureID) throws -> [(outer: BRepSewingShell, voids: [BRepSewingShell])] {
        struct Probe {
            let shell: BRepSewingShell
            let model: BRepModel
            let faceIDs: [FaceID]
            let bounds: BoundingBox3D
            /// A point just inside the shell's region.
            let inside: Point3D
        }
        let crossings = BRepRayFaceCrossings(
            intersector: DefaultCurveSurfaceIntersector(),
            facePointContainment: DefaultFacePointContainmentTester()
        )
        let probes = try shells.map { shell -> Probe in
            let sewn = try DefaultBRepSewer().sew(
                BRepSewingRequest(featureID: featureID, bodyTopology: .sheet(shellStableIDs: [shell.stableID]), shells: [shell]),
                tolerance: tolerance
            )
            guard let body = sewn.brep.bodies[sewn.bodyID], let shellID = body.shellIDs.first,
                  let faceIDs = sewn.brep.shells[shellID]?.faceIDs, let faceID = faceIDs.first,
                  let face = sewn.brep.faces[faceID], let surface = sewn.brep.geometry.surfaces[face.surfaceID] else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                    message: "A region shell did not sew.")
            }
            let sample = try BRepFaceInteriorPointSampler().sample(on: faceID, in: sewn.brep, tolerance: tolerance)
            let point = sample.point
            let geometric = try surface.normal(u: sample.parameter.u, v: sample.parameter.v, tolerance: tolerance)
                .normalized(tolerance: tolerance.distance)
            let outward = face.orientation == .forward ? geometric : geometric * -1.0
            let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: sewn.bodyID, in: sewn.brep, tolerance: tolerance)
            let step = max(tolerance.distance * 100, (bounds.maximum - bounds.minimum).length * 1e-6)
            return Probe(shell: shell, model: sewn.brep, faceIDs: faceIDs, bounds: bounds, inside: point + outward * -step)
        }
        func encloses(_ probe: Probe, _ point: Point3D) throws -> Bool {
            let upper = crossings.upperBound(from: point, bounds: probe.bounds, tolerance: tolerance)
            var counts: [Bool] = []
            for direction in try BRepRayFaceCrossings.directions(tolerance: tolerance) {
                do {
                    let count = try crossings.crossings(
                        from: point, direction: direction, upperBound: upper, faceIDs: probe.faceIDs,
                        model: probe.model, containmentSession: nil, tolerance: tolerance
                    ).count
                    counts.append(count.isMultiple(of: 2) == false)
                } catch let error as KernelError where error.code == .nonDiscreteIntersection {
                    continue
                }
            }
            guard let first = counts.first, counts.allSatisfy({ $0 == first }) else {
                throw KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "A region shell's nesting could not be decided.")
            }
            return first
        }
        var outers: [(probe: Probe, volume: Double)] = []
        var others: [Probe] = []
        for probe in probes {
            if try encloses(probe, probe.inside) {
                let solid = try DefaultBRepSewer().sew(
                    BRepSewingRequest(featureID: featureID, bodyTopology: .solid(components: [
                        BRepSewingSolidComponent(outerShellStableID: probe.shell.stableID, voidShellStableIDs: []),
                    ]), shells: [probe.shell]),
                    tolerance: tolerance
                )
                outers.append((probe, try solid.brep.volume(of: solid.bodyID, tolerance: tolerance)))
            } else {
                others.append(probe)
            }
        }
        var voids: [Int: [BRepSewingShell]] = [:]
        for other in others {
            // A void shell's region lies around it: the smallest outer shell holding that belongs
            // to the region the void is cut out of.
            let holders = try outers.indices.filter { try encloses(outers[$0].probe, other.inside) }
            guard let holder = holders.min(by: { outers[$0].volume < outers[$1].volume }) else { continue }
            voids[holder, default: []].append(try voidShell(other.shell))
        }
        return outers.indices.map { (outers[$0].probe.shell, voids[$0] ?? []) }
    }

    /// A void shell's faces face out of the cavity, the shell reversed: `shell` faces out of its
    /// region, into the cavity, so each face turns back.
    private func voidShell(_ shell: BRepSewingShell) throws -> BRepSewingShell {
        let adapter = BRepSewingPatchOrientationAdapter()
        return BRepSewingShell(
            stableID: shell.stableID,
            patches: try shell.patches.map { try adapter.reorient($0, to: opposite($0.orientation), tolerance: tolerance) },
            orientation: .reversed
        )
    }

    private func opposite(_ orientation: Orientation) -> Orientation {
        orientation == .forward ? .reversed : .forward
    }

    /// One side of a patch, its identities made the side's own: both sides of a patch are sewn.
    private func renamed(_ patch: BRepSewingFacePatch, suffix: String) -> BRepSewingFacePatch {
        BRepSewingFacePatch(
            stableID: "\(patch.stableID):\(suffix)",
            surface: patch.surface,
            orientation: patch.orientation,
            loops: patch.loops.map { loop in
                BRepSewingLoop(
                    stableID: "\(loop.stableID):\(suffix)",
                    role: loop.role,
                    edges: loop.edges.map { edge in
                        BRepSewingEdge(
                            stableID: "\(edge.stableID):\(suffix)",
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
    }
}
