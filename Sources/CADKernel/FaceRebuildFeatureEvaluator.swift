import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Rebuild Face: each chosen face takes a B-spline surface fitted to its own on the same
/// parameters, so its trimming curves stay valid, and the body keeps its topology in its place.
///
/// The fitted rectangle is the face's parameter extent when the feature shrinks, and otherwise
/// the surface's own domain where it has one (a B-spline's knot range; an analytic surface's face
/// extent), widened past each side by the extension fractions; a B-spline is read past its domain
/// as its end spans continued (`BSplineSurfaceNaturalContinuation`). An explicit layout is
/// fitted as given; a tolerance takes as few bicubic spans as keep within it
/// (`MappedBSplineSurfaceFitter`).
///
/// A face whose new surface keeps within a quarter of the distance tolerance of its edges along
/// their trimming curves takes it in place, its edges, vertices and trimming curves kept. One that
/// strays further is sewn anew on its new surface: a sheet of its own (every edge open) with each
/// edge a B-spline fitted along its trimming curve within that quarter, a face sharing edges with
/// them re-solved where its new surface crosses its neighbouring planes (`RebuiltFaceEdgeResolver`).
struct FaceRebuildFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    init(resolver: ParameterResolving = ParameterResolver(), subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try rebuild(feature: feature, context: context)
        }
    }

    private func rebuild(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceRebuild(rebuild) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Rebuild Face evaluator requires a faceRebuild feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try rebuild.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let model = context.brep
        var deviation: Double?
        if case let .tolerance(expression) = rebuild.method {
            let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
            guard quantity.kind == .length, quantity.value.isFinite, quantity.value > 0 else {
                throw failure(.invalidInput, feature.id, tolerance, "Rebuild Face tolerance must be a positive length.")
            }
            deviation = quantity.value
        }
        let bodyID = try context.bodyID(generatedBy: rebuild.target.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let faceIDs = try rebuild.faces.map { reference -> FaceID in
            let resolved = try subshapeResolver.topologyReference(
                for: reference, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
            )
            guard case let .face(faceID) = resolved, scope.references.contains(.face(faceID)) else {
                throw KernelError(phase: .evaluation, code: .missingReference, featureID: feature.id, subshapeID: reference.subshapeID,
                                  tolerance: tolerance, message: "A Rebuild Face selection did not resolve to a face of its body.")
            }
            return faceID
        }
        guard Set(faceIDs).count == faceIDs.count else {
            throw failure(.invalidInput, feature.id, tolerance, "Rebuild Face selections resolve to the same face.")
        }
        // Square's Refit: each face an untrimmed sheet on its own edges, which it keeps, its
        // coedges along the sheet's boundary.
        if case let .square(refit) = rebuild.method {
            var result = model
            var ids = FeatureTopologyIDAllocator(featureID: feature.id)
            for faceID in faceIDs {
                let refitted = try SquareFaceRefitter(tolerance: tolerance).refit(
                    faceID, refit: refit, source: rebuild.target.featureID, context: context, featureID: feature.id
                )
                guard var face = result.faces[faceID], let loopID = face.loops.first, var loop = result.loops[loopID] else {
                    throw TopologyError.missingReference("A refitted face is missing.")
                }
                var surfaceID = ids.nextSurfaceID()
                while result.geometry.surfaces[surfaceID] != nil { surfaceID = ids.nextSurfaceID() }
                result.geometry.surfaces[surfaceID] = .bSpline(refitted.surface)
                face.surfaceID = surfaceID
                face.orientation = refitted.orientation
                for index in loop.coedges.indices { loop.coedges[index].surfaceParameterCurve = refitted.pcurves[index] }
                result.loops[loopID] = loop
                result.faces[faceID] = face
            }
            let referencedSurfaces = Set(result.faces.values.map(\.surfaceID))
            result.geometry.surfaces = result.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
            try result.validate(level: model.bodies[bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
            let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: result, context: context)
            return EvaluationResult(brep: result, subshapes: identity.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes),
                                    lineage: identity.lineage)
        }
        var surfaces: [FaceID: BSplineSurface3D] = [:]
        for faceID in faceIDs {
            surfaces[faceID] = try refitted(faceID, rebuild: rebuild, deviation: deviation, model: model, featureID: feature.id, tolerance: tolerance)
        }

        // How far each new surface strays from the face's edges along their trimming curves.
        var strays: [FaceID: Double] = [:]
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let old = model.geometry.surfaces[face.surfaceID], let fitted = surfaces[faceID] else {
                throw TopologyError.missingReference("A rebuilt face is missing.")
            }
            let new = Surface3D.bSpline(fitted)
            var stray = 0.0
            for loopID in face.loops {
                for coedge in model.loops[loopID]?.coedges ?? [] {
                    guard let pcurve = coedge.surfaceParameterCurve else {
                        throw failure(.missingReference, feature.id, tolerance, "An edge of a face to rebuild has no trimming curve.")
                    }
                    for index in 0...16 {
                        let parameter = try pcurve.parameter(atNormalizedFraction: Double(index) / 16, tolerance: tolerance)
                        stray = max(stray, (try new.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                            - (try old.point(u: parameter.u, v: parameter.v, tolerance: tolerance))).length)
                    }
                }
            }
            strays[faceID] = stray
        }
        // A face whose new surface keeps within a quarter of the distance tolerance of its edges
        // takes it in place; any other must be a sheet of its own, sewn anew on fitted edges.
        let inPlace = faceIDs.filter { (strays[$0] ?? .infinity) <= tolerance.distance / 4 }
        let coarse = faceIDs.filter { (strays[$0] ?? .infinity) > tolerance.distance / 4 }
        var facesOfEdge: [EdgeID: Int] = [:]
        for case let .face(faceID) in scope.references {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: 0] += 1 }
            }
        }
        // A coarse face sharing edges has them re-solved onto its new surface where its neighbours
        // cross it (`RebuiltFaceEdgeResolver`), one face after another on the patches the last
        // left: such faces do not meet each other or share a corner, so a neighbour they share has
        // each one's edges moved apart from the other's.
        var bordered: [FaceID: Set<FaceID>] = [:]
        var cornersOf: [FaceID: Set<VertexID>] = [:]
        for faceID in coarse {
            let edges = (model.faces[faceID]?.loops ?? []).flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] }
            guard edges.allSatisfy({ facesOfEdge[$0] == 1 }) == false else { continue }
            guard edges.allSatisfy({ facesOfEdge[$0] == 2 }) else {
                throw failure(.unsupportedCapability, feature.id, tolerance, "A face rebuilt coarsely has all its edges open or all shared.")
            }
            let around = Set(model.faces.keys.filter { other in
                other != faceID && (model.faces[other]?.loops ?? []).contains { loopID in
                    model.loops[loopID]?.coedges.contains { edges.contains($0.edgeID) } ?? false
                }
            })
            let corners = Set(edges.flatMap { edgeID -> [VertexID] in
                guard let edge = model.edges[edgeID] else { return [] }
                return [edge.startVertexID, edge.endVertexID]
            })
            guard around.isDisjoint(with: coarse), cornersOf.values.allSatisfy({ $0.isDisjoint(with: corners) }) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): faces rebuilt coarser than their edges allow
                // that meet each other or share a corner need their edges re-solved together,
                // which is not built, so they are refused. Production path:
                // FaceRebuildFeatureEvaluator. Complete only when such faces are rebuilt together,
                // verified by two adjacent curved faces rebuilt coarsely.
                throw failure(.unsupportedCapability, feature.id, tolerance,
                              "Faces rebuilt coarser than their edges allow are apart, with no corner in common.")
            }
            bordered[faceID] = around
            cornersOf[faceID] = corners
        }
        // In place: each face takes its new surface, its edges, vertices and trimming curves kept,
        // since the surface is refitted on the face's own parameters and keeps that close to them.
        var result = model
        var ids = FeatureTopologyIDAllocator(featureID: feature.id)
        for faceID in inPlace {
            guard var face = result.faces[faceID], let fitted = surfaces[faceID] else {
                throw TopologyError.missingReference("A rebuilt face is missing.")
            }
            var surfaceID = ids.nextSurfaceID()
            while result.geometry.surfaces[surfaceID] != nil { surfaceID = ids.nextSurfaceID() }
            result.geometry.surfaces[surfaceID] = .bSpline(fitted)
            face.surfaceID = surfaceID
            result.faces[faceID] = face
        }
        let referencedSurfaces = Set(result.faces.values.map(\.surfaceID))
        result.geometry.surfaces = result.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
        let subshapes: [SubshapeID: TopologyReference]
        let lineage: [SubshapeID: TopologyLineage]
        if coarse.isEmpty {
            let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: result, context: context)
            subshapes = identity.subshapes
            lineage = identity.lineage
        } else {
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: bodyID, featureID: feature.id, from: result, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
            )
            guard let body = result.bodies[bodyID] else { throw TopologyError.missingReference("A rebuilt body is missing.") }
            let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 4)
            let sewnAnew = Set(coarse)
            var shells: [BRepSewingShell] = []
            // The extractor names shell i of the body "shell:i" and its face j "shell:i:face:j".
            for (shellIndex, shell) in extraction.request.shells.enumerated() {
                guard shellIndex < body.shellIDs.count, let sourceShell = result.shells[body.shellIDs[shellIndex]],
                      sourceShell.faceIDs.count == shell.patches.count else {
                    throw failure(.missingReference, feature.id, tolerance, "Rebuild Face lost the order of the body's faces.")
                }
                var patches = try zip(sourceShell.faceIDs, shell.patches).map { faceID, patch -> BRepSewingFacePatch in
                    guard sewnAnew.contains(faceID), bordered[faceID] == nil, let fitted = surfaces[faceID] else { return patch }
                    return try resewn(patch, on: fitted, curveFitter: curveFitter, featureID: feature.id, tolerance: tolerance)
                }
                for faceID in sourceShell.faceIDs where bordered[faceID] != nil {
                    guard let fitted = surfaces[faceID] else { throw TopologyError.missingReference("A rebuilt face lost its surface.") }
                    patches = try RebuiltFaceEdgeResolver(tolerance: tolerance).resolve(
                        faceID: faceID, surface: fitted, patches: Array(zip(sourceShell.faceIDs, patches)).map { ($0.0, $0.1) },
                        model: result, featureID: feature.id)
                }
                shells.append(BRepSewingShell(stableID: shell.stableID, patches: patches, orientation: shell.orientation))
            }
            let sewn = try DefaultBRepSewer().sew(
                BRepSewingRequest(featureID: feature.id, bodyTopology: extraction.request.bodyTopology, shells: shells), tolerance: tolerance
            )
            result = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: result)
            subshapes = sewn.subshapes
            lineage = sewn.lineage
        }
        try result.validate(level: model.bodies[bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
        return EvaluationResult(brep: result, subshapes: subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes), lineage: lineage)
    }

    /// The face's new surface: its support refitted on the same parameters over the rectangle the
    /// feature asks for.
    private func refitted(
        _ faceID: FaceID, rebuild: FaceRebuildFeature, deviation: Double?, model: BRepModel, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A face to rebuild is missing.")
        }
        var box = try FaceParameterExtentResolver().bounds(for: faceID, in: model, tolerance: tolerance)
        // Remove Nominal Surface: the face's own spline cut exactly to its extent, on the same
        // parameters, so its trimming curves hold as they are.
        if case .nominal = rebuild.method {
            guard case let .bSpline(spline) = surface else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "Remove Nominal Surface takes spline faces; an analytic face has no nominal surface beyond its edges.")
            }
            return try spline.trimmed(uFrom: box.u.lower, uTo: box.u.upper, vFrom: box.v.lower, vTo: box.v.upper, tolerance: tolerance)
        }
        let point: (Double, Double) throws -> Point3D
        if case let .bSpline(spline) = surface {
            if rebuild.shrinks == false, let u0 = spline.uKnots.first, let u1 = spline.uKnots.last,
               let v0 = spline.vKnots.first, let v1 = spline.vKnots.last {
                box = try SurfaceParameterBox(u: try ScalarInterval(lower: u0, upper: u1), v: try ScalarInterval(lower: v0, upper: v1))
            }
            let continuation = try BSplineSurfaceNaturalContinuation(spline, tolerance: tolerance)
            point = { u, v in continuation.point(u: u, v: v) }
        } else {
            point = { u, v in
                do {
                    return try surface.point(u: u, v: v, tolerance: tolerance)
                } catch {
                    throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                      message: "Rebuild Face extends a face past its surface's parameter domain.")
                }
            }
        }
        let u = try ScalarInterval(lower: box.u.lower - box.u.width * rebuild.extendU, upper: box.u.upper + box.u.width * rebuild.extendU)
        let v = try ScalarInterval(lower: box.v.lower - box.v.width * rebuild.extendV, upper: box.v.upper + box.v.width * rebuild.extendV)
        switch rebuild.method {
        case let .explicit(layout):
            return try MappedBSplineSurfaceFitter.fit(
                layout: MappedBSplineSurfaceFitter.Layout(uDegree: layout.uDegree, vDegree: layout.vDegree, uSpans: layout.uSpans, vSpans: layout.vSpans),
                u: u, v: v, tolerance: tolerance, point: point
            ).surface
        case .nominal:
            throw failure(.invalidInput, featureID, tolerance, "Remove Nominal Surface is cut exactly, not fitted.")
        case .square:
            throw failure(.invalidInput, featureID, tolerance, "Square's Refit spans the face's edges, not its surface.")
        case .tolerance:
            guard let deviation else { throw failure(.invalidInput, featureID, tolerance, "Rebuild Face lost its tolerance.") }
            return try MappedBSplineSurfaceFitter(deviation: deviation).fit(u: u, v: v, tolerance: tolerance, point: point).surface
        }
    }

    /// A face of its own sewn anew on `surface`: its trimming curves kept, each edge the surface
    /// along its trimming curve, fitted within a quarter of the distance tolerance.
    private func resewn(
        _ patch: BRepSewingFacePatch, on surface: BSplineSurface3D, curveFitter: SpatialCurveFitter, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let wrapped = Surface3D.bSpline(surface)
        let loops = try patch.loops.map { loop in
            BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                let pcurve = edge.surfaceParameterCurve
                let along = { (fraction: Double) throws -> Point3D in
                    let parameter = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                    return try wrapped.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                }
                let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance, point: along).curve
                return BRepSewingEdge(
                    stableID: edge.stableID, curve: .bSpline(curve), startParameter: 0, endParameter: 1,
                    startPoint: try along(0), endPoint: try along(1), surfaceParameterCurve: pcurve,
                    parentSubshapeIDs: edge.parentSubshapeIDs,
                    startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs, endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
                )
            })
        }
        return BRepSewingFacePatch(stableID: patch.stableID, surface: wrapped, orientation: patch.orientation, loops: loops, parentSubshapeIDs: patch.parentSubshapeIDs)
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
