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
/// (`MappedBSplineSurfaceFitter`). Admitted polynomial continuation through bicubic
/// source degrees instead retains original native knots in a certified coefficient construction.
/// Native tolerance publication is certified for non-periodic charts within the original source
/// support and for finite exact-clamped common-weight piecewise-polynomial continuation laws.
/// Periodic, varying-weight and foreign-chart continued-law cases retain an explicit typed refusal
/// until their whole-domain original position proof is implemented.
///
/// A face whose new surface keeps within a quarter of the distance tolerance of its edges along
/// their trimming curves takes it in place, its edges, vertices and trimming curves kept. One that
/// strays further is sewn anew on its new surface: a sheet of its own (every edge open) with each
/// edge a B-spline fitted along its trimming curve within that quarter, faces sharing edges with
/// them re-solved together where their new surfaces cross their neighbours' and each other's
/// (`RebuiltFaceEdgeResolver`).
struct FaceRebuildFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let nativeSurfacePositionCertificationLimits: NativeSurfacePositionCertificationLimits
    private let polynomialContinuationConstructor: any GeometryPolynomialSurfaceContinuationConstructing

    init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        nativeSurfacePositionCertificationLimits: NativeSurfacePositionCertificationLimits = .standard,
        polynomialContinuationConstructor: any GeometryPolynomialSurfaceContinuationConstructing = NativeKnotPolynomialSurfaceContinuationConstructor()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        self.nativeSurfacePositionCertificationLimits = nativeSurfacePositionCertificationLimits
        self.polynomialContinuationConstructor = polynomialContinuationConstructor
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
        if case let .given(surface) = rebuild.method {
            return try give(surface, to: faceIDs[0], bodyID: bodyID, scope: scope, feature: feature, context: context)
        }
        // Square's Refit: each face an untrimmed sheet on its own edges, which it keeps, its
        // coedges along the sheet's boundary.
        if case let .square(refit) = rebuild.method {
            var result = model
            var ids = FeatureTopologyIDAllocator(featureID: feature.id)
            var refits: [FaceID: SquareFaceRefitter.Refit] = [:]
            for faceID in faceIDs {
                let refitted = try SquareFaceRefitter(tolerance: tolerance).refit(
                    faceID, refit: refit, source: rebuild.target.featureID, context: context, featureID: feature.id
                )
                refits[faceID] = refitted
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
            // The net is exactly the one asked for, so a side may stray from the face's edge (a
            // side joined from edges meeting at a corner, a net too coarse for its curve). Sides
            // within the distance tolerance keep their edges; a sheet's straying sides leave their
            // neighbours' edges and run along the new surface's boundary instead.
            if let detached = try detachedSides(model, refits: refits, bodyID: bodyID, feature: feature, context: context) {
                result = detached.model
                try result.validate(level: .exact, tolerance: tolerance)
                return EvaluationResult(brep: result, subshapes: detached.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes),
                                        lineage: detached.lineage)
            }
            try result.validate(level: model.bodies[bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
            let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: result, context: context)
            return EvaluationResult(brep: result, subshapes: identity.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes),
                                    lineage: identity.lineage)
        }
        var surfaces: [FaceID: BSplineSurface3D] = [:]
        for faceID in faceIDs {
            let nativeSourceAndRequest: (source: BSplineSurface3D, requestedBox: SurfaceParameterBox)?
            if case .tolerance = rebuild.method,
               let face = model.faces[faceID],
               let sourceSurface = model.geometry.surfaces[face.surfaceID],
               case let .bSpline(source) = sourceSurface {
                nativeSourceAndRequest = (
                    source,
                    try nativePositionRequestBox(
                        faceID: faceID, rebuild: rebuild, source: source, model: model,
                        tolerance: tolerance, featureID: feature.id
                    )
                )
            } else {
                nativeSourceAndRequest = nil
            }
            let preparedContinuationRequest: PreparedPolynomialSurfaceContinuationPositionRequest?
            if let nativeSourceAndRequest,
               (rebuild.extendU != 0 || rebuild.extendV != 0),
               requestsContinuationOutsideSource(
                    nativeSourceAndRequest.requestedBox, source: nativeSourceAndRequest.source
               ) {
                do {
                    preparedContinuationRequest = try CertifiedPolynomialSurfaceContinuationPositionCertifier()
                        .prepareContinuationRequest(
                            source: nativeSourceAndRequest.source,
                            over: nativeSourceAndRequest.requestedBox,
                            maximumPositionError: deviation ?? .infinity,
                            limits: nativeSurfacePositionCertificationLimits,
                            tolerance: tolerance
                        )
                } catch let error as KernelError {
                    throw featureScopedKernelError(error, featureID: feature.id, tolerance: tolerance)
                } catch let error as GeometryConversionError {
                    throw continuationGeometryError(error, featureID: feature.id, tolerance: tolerance)
                }
            } else {
                preparedContinuationRequest = nil
            }
            let candidate: BSplineSurface3D
            if let preparedContinuationRequest,
               preparedContinuationRequest.source.uDegree <= 3,
               preparedContinuationRequest.source.vDegree <= 3 {
                do {
                    let constructed = try polynomialContinuationConstructor.constructContinuationCandidate(
                        preparedRequest: preparedContinuationRequest,
                        uDegree: 3, vDegree: 3,
                        maximumSpanCount: 128, maximumControlPointCountPerAxis: 131
                    )
                    guard constructed.certificate.coveredParameters == preparedContinuationRequest.parameters,
                          constructed.certificate.positionErrorUpperBound.isFinite,
                          constructed.certificate.positionErrorUpperBound >= 0,
                          constructed.certificate.positionErrorUpperBound <= preparedContinuationRequest.maximumPositionError else {
                        throw failure(.approximationToleranceRejected, feature.id, tolerance,
                                      "The continuation producer did not certify the complete requested distance bound.")
                    }
                    candidate = constructed.surface
                } catch let error as KernelError {
                    throw featureScopedKernelError(error, featureID: feature.id, tolerance: tolerance)
                } catch let error as GeometryConversionError {
                    throw continuationGeometryError(error, featureID: feature.id, tolerance: tolerance)
                }
            } else {
                candidate = try refitted(
                    faceID, rebuild: rebuild, deviation: deviation, model: model, featureID: feature.id,
                    tolerance: tolerance, requestedBox: nativeSourceAndRequest?.requestedBox
                )
            }
            if let nativeSourceAndRequest,
               preparedContinuationRequest == nil
                    || nativeSourceAndRequest.source.uDegree > 3
                    || nativeSourceAndRequest.source.vDegree > 3 {
                try certifyNativePosition(
                    source: nativeSourceAndRequest.source, candidate: candidate,
                    requestedBox: nativeSourceAndRequest.requestedBox,
                    preferWholeOriginal: rebuild.extendU == 0 && rebuild.extendV == 0,
                    maximumPositionError: deviation ?? .infinity,
                    preparedContinuationRequest: preparedContinuationRequest,
                    featureID: feature.id, tolerance: tolerance
                )
            } else if nativeSourceAndRequest == nil, case .tolerance = rebuild.method {
                // FIXME(INCOMPLETE_IMPLEMENTATION): analytic and other non-native tolerance
                // rebuilds still publish through the historical edge checks without a complete
                // native-source position certificate. The production completion condition is a
                // typed whole-domain position proof for each such source family.
            }
            surfaces[faceID] = candidate
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
        // Coarse faces sharing edges have them re-solved onto their new surfaces where their
        // neighbours cross them (`RebuiltFaceEdgeResolver`), all together: an edge two of them
        // share is their new surfaces' crossing, a corner where its three faces' surfaces meet.
        var bordered: Set<FaceID> = []
        for faceID in coarse {
            let edges = (model.faces[faceID]?.loops ?? []).flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] }
            guard edges.allSatisfy({ facesOfEdge[$0] == 1 }) == false else { continue }
            guard edges.allSatisfy({ facesOfEdge[$0] == 2 }) else {
                throw failure(.unsupportedCapability, feature.id, tolerance, "A face rebuilt coarsely has all its edges open or all shared.")
            }
            bordered.insert(faceID)
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
                    guard sewnAnew.contains(faceID), bordered.contains(faceID) == false, let fitted = surfaces[faceID] else { return patch }
                    return try resewn(patch, on: fitted, curveFitter: curveFitter, featureID: feature.id, tolerance: tolerance)
                }
                let shellBordered = sourceShell.faceIDs.filter { bordered.contains($0) }
                if shellBordered.isEmpty == false {
                    var resolving: [FaceID: BSplineSurface3D] = [:]
                    for faceID in shellBordered {
                        guard let fitted = surfaces[faceID] else { throw TopologyError.missingReference("A rebuilt face lost its surface.") }
                        resolving[faceID] = fitted
                    }
                    patches = try RebuiltFaceEdgeResolver(tolerance: tolerance).resolve(
                        surfaces: resolving, patches: Array(zip(sourceShell.faceIDs, patches)).map { ($0.0, $0.1) },
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
    // FIXME(INCOMPLETE_IMPLEMENTATION): The production DefaultFeatureEvaluator faceRebuild
    // tolerance path still refuses periodic, varying-weight and foreign-chart continuation requests with a
    // typed unsupported error. Completion requires a whole-domain position proof for each such
    // original source law before those requests may publish.
    private func nativePositionRequestBox(
        faceID: FaceID,
        rebuild: FaceRebuildFeature,
        source: BSplineSurface3D,
        model: BRepModel,
        tolerance: ModelingTolerance,
        featureID: FeatureID
    ) throws -> SurfaceParameterBox {
        guard source.isUPeriodic == false, source.isVPeriodic == false,
              case let .closed(sourceULower, sourceUUpper) = source.uDomain,
              case let .closed(sourceVLower, sourceVUpper) = source.vDomain else {
            throw failure(.unsupportedCapability, featureID, tolerance,
                          "Native Rebuild position certification does not support periodic or non-closed source charts.")
        }
        var box = try FaceParameterExtentResolver().bounds(for: faceID, in: model, tolerance: tolerance)
        if rebuild.shrinks == false {
            box = try SurfaceParameterBox(
                u: try ScalarInterval(lower: sourceULower, upper: sourceUUpper),
                v: try ScalarInterval(lower: sourceVLower, upper: sourceVUpper)
            )
        }
        let requested = try SurfaceParameterBox(
            u: try ScalarInterval(
                lower: box.u.lower - box.u.width * rebuild.extendU,
                upper: box.u.upper + box.u.width * rebuild.extendU
            ),
            v: try ScalarInterval(
                lower: box.v.lower - box.v.width * rebuild.extendV,
                upper: box.v.upper + box.v.width * rebuild.extendV
            )
        )
        return requested
    }

    private func requestsContinuationOutsideSource(
        _ requestedBox: SurfaceParameterBox,
        source: BSplineSurface3D
    ) -> Bool {
        guard case let .closed(sourceULower, sourceUUpper) = source.uDomain,
              case let .closed(sourceVLower, sourceVUpper) = source.vDomain else {
            return false
        }
        return requestedBox.u.lower < sourceULower
            || requestedBox.u.upper > sourceUUpper
            || requestedBox.v.lower < sourceVLower
            || requestedBox.v.upper > sourceVUpper
    }

    private func certifyNativePosition(
        source: BSplineSurface3D,
        candidate: BSplineSurface3D,
        requestedBox: SurfaceParameterBox,
        preferWholeOriginal: Bool,
        maximumPositionError: Double,
        preparedContinuationRequest: PreparedPolynomialSurfaceContinuationPositionRequest?,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        guard candidate.isUPeriodic == false, candidate.isVPeriodic == false,
              case let .closed(sourceULower, sourceUUpper) = source.uDomain,
              case let .closed(sourceVLower, sourceVUpper) = source.vDomain,
              case let .closed(candidateULower, candidateUUpper) = candidate.uDomain,
              case let .closed(candidateVLower, candidateVUpper) = candidate.vDomain else {
            throw failure(.unsupportedCapability, featureID, tolerance,
                          "Native Rebuild position certification requires closed non-periodic source and candidate charts.")
        }
        let coversOriginal = preferWholeOriginal
            && candidateULower <= sourceULower && candidateUUpper >= sourceUUpper
            && candidateVLower <= sourceVLower && candidateVUpper >= sourceVUpper
        let requestsContinuation = requestedBox.u.lower < sourceULower
            || requestedBox.u.upper > sourceUUpper
            || requestedBox.v.lower < sourceVLower
            || requestedBox.v.upper > sourceVUpper
        if requestsContinuation && !coversOriginal {
            guard let preparedContinuationRequest else {
                throw failure(.unsupportedCapability, featureID, tolerance,
                              "Native Rebuild continuation requires a prepared original source request.")
            }
            guard candidateULower <= requestedBox.u.lower, candidateUUpper >= requestedBox.u.upper,
                  candidateVLower <= requestedBox.v.lower, candidateVUpper >= requestedBox.v.upper else {
                throw failure(.unsupportedCapability, featureID, tolerance,
                              "Native Rebuild candidate does not contain the complete requested continuation box.")
            }
            do {
                _ = try CertifiedPolynomialSurfaceContinuationPositionCertifier().certifyContinuationPosition(
                    preparedRequest: preparedContinuationRequest, candidate: candidate
                )
            } catch let error as KernelError {
                throw featureScopedKernelError(error, featureID: featureID, tolerance: tolerance)
            } catch let error as GeometryConversionError {
                throw continuationGeometryError(error, featureID: featureID, tolerance: tolerance)
            }
            return
        }
        let certificationBox: SurfaceParameterBox
        if coversOriginal {
            certificationBox = try SurfaceParameterBox(
                u: try ScalarInterval(lower: sourceULower, upper: sourceUUpper),
                v: try ScalarInterval(lower: sourceVLower, upper: sourceVUpper)
            )
        } else {
            guard candidateULower <= requestedBox.u.lower, candidateUUpper >= requestedBox.u.upper,
                  candidateVLower <= requestedBox.v.lower, candidateVUpper >= requestedBox.v.upper,
                  requestedBox.u.lower > sourceULower, requestedBox.u.upper < sourceUUpper,
                  requestedBox.v.lower > sourceVLower, requestedBox.v.upper < sourceVUpper,
                  candidateULower < requestedBox.u.lower, candidateUUpper > requestedBox.u.upper,
                  candidateVLower < requestedBox.v.lower, candidateVUpper > requestedBox.v.upper else {
                throw failure(.unsupportedCapability, featureID, tolerance,
                              "Native Rebuild candidate has no strictly contained, provable source certification box.")
            }
            certificationBox = requestedBox
        }
        do {
            _ = try CertifiedNativeSurfacePositionCertifier().certifyPosition(
                source: source, candidate: candidate, over: certificationBox,
                maximumPositionError: maximumPositionError,
                limits: nativeSurfacePositionCertificationLimits, tolerance: tolerance
            )
        } catch let error as KernelError {
            throw error
        } catch let error as GeometryConversionError {
            switch error {
            case let .invalidInput(message):
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID,
                                  tolerance: tolerance, message: message)
            case let .resourceLimitExceeded(message):
                throw KernelError(phase: .evaluation, code: .resourceLimitExceeded, featureID: featureID,
                                  tolerance: tolerance, message: message)
            case .toleranceRejected:
                throw KernelError(phase: .evaluation, code: .approximationToleranceRejected, featureID: featureID,
                                  tolerance: tolerance,
                                  message: "Native Rebuild candidate exceeded its requested position tolerance.")
            }
        }
    }

    private func refitted(
        _ faceID: FaceID, rebuild: FaceRebuildFeature, deviation: Double?, model: BRepModel,
        featureID: FeatureID, tolerance: ModelingTolerance, requestedBox: SurfaceParameterBox? = nil
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
        let fitBox: SurfaceParameterBox
        if let requestedBox {
            fitBox = requestedBox
        } else {
            fitBox = try SurfaceParameterBox(
                u: try ScalarInterval(
                    lower: box.u.lower - box.u.width * rebuild.extendU,
                    upper: box.u.upper + box.u.width * rebuild.extendU
                ),
                v: try ScalarInterval(
                    lower: box.v.lower - box.v.width * rebuild.extendV,
                    upper: box.v.upper + box.v.width * rebuild.extendV
                )
            )
        }
        let u = fitBox.u
        let v = fitBox.v
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
        case .given:
            throw failure(.invalidInput, featureID, tolerance, "A given face surface is taken as it is, not fitted.")
        case .tolerance:
            guard let deviation else { throw failure(.invalidInput, featureID, tolerance, "Rebuild Face lost its tolerance.") }
            return try MappedBSplineSurfaceFitter(deviation: deviation).fit(u: u, v: v, tolerance: tolerance, point: point).surface
        }
    }

    /// One face given `surface` on its own parameters, facing out as it did. Where each of its edges
    /// still lies on it along its trimming curve (within a quarter of the distance tolerance) the
    /// face keeps them; otherwise the edges and vertices around it are re-solved where it meets the
    /// faces beside it (`FaceSurfaceReplacementRebuilder`), their trimming curves rebuilt.
    private func give(_ surface: BSplineSurface3D, to faceID: FaceID, bodyID: BodyID, scope: BodyTopologyScope,
                      feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        var result = context.brep
        guard let face = result.faces[faceID], let old = result.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("The face given a surface is missing.")
        }
        try surface.validate(tolerance: tolerance)
        let new = Surface3D.bSpline(surface)
        let sample = try BRepFaceInteriorPointSampler().sample(on: faceID, in: result, tolerance: tolerance)
        let outward = try old.normal(u: sample.parameter.u, v: sample.parameter.v, tolerance: tolerance) * (face.orientation == .forward ? 1 : -1)
        guard case let .closed(u0, u1) = new.uDomain, case let .closed(v0, v1) = new.vDomain else {
            throw failure(.invalidInput, feature.id, tolerance, "A given face surface has an unbounded domain.")
        }
        // The given surface's normal where the face's interior point was — at its parameters when the
        // surface shares them, else where that point lies on it (a surface on parameters of its
        // own) — against the side the face faced.
        let (su, sv) = (min(max(sample.parameter.u, u0), u1), min(max(sample.parameter.v, v0), v1))
        var normalParameter = (u: su, v: sv)
        if (try new.point(u: su, v: sv, tolerance: tolerance) - sample.point).length > tolerance.distance,
           case let .projected(projection) = try new.parameterProjectionResult(of: sample.point, tolerance: tolerance) {
            normalParameter = (projection.u, projection.v)
        }
        let orientation: Orientation = try new.normal(u: normalParameter.u, v: normalParameter.v, tolerance: tolerance)
            .dot(outward) >= 0 ? .forward : .reversed
        var stray = 0.0
        for loopID in face.loops {
            for coedge in result.loops[loopID]?.coedges ?? [] {
                guard let pcurve = coedge.surfaceParameterCurve else {
                    throw failure(.missingReference, feature.id, tolerance, "An edge of the face given a surface has no trimming curve.")
                }
                for index in 0...16 {
                    let parameter = try pcurve.parameter(atNormalizedFraction: Double(index) / 16, tolerance: tolerance)
                    let slack = tolerance.distance
                    guard parameter.u >= u0 - slack, parameter.u <= u1 + slack, parameter.v >= v0 - slack, parameter.v <= v1 + slack else {
                        stray = .infinity
                        break
                    }
                    let u = min(max(parameter.u, u0), u1), v = min(max(parameter.v, v0), v1)
                    stray = max(stray, (try new.point(u: u, v: v, tolerance: tolerance)
                        - (try old.point(u: parameter.u, v: parameter.v, tolerance: tolerance))).length)
                }
            }
        }
        // On parameters of its own (a cylinder made rational), the surface may still hold every edge
        // where it lies: the face keeps them, their trimming curves rebuilt on it.
        var holdsEdges = stray <= tolerance.distance / 4
        var reparameterized = false
        var faceSurface = new
        // Where the surface no longer reaches the face's edges (its control points drawn in), the
        // surface continued past every side as its own polynomial, as far again as it spans, may
        // still hold them: the face keeps its edges on that continuation — Plasticity's hidden
        // spans of the nominal surface, made visible by Remove Nominal Surface.
        func holds(_ candidate: Surface3D) throws -> Bool {
            let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
            let poles = try collapsedSides(of: candidate, tolerance: tolerance)
            var gap = 0.0
            for loopID in face.loops {
                for coedge in result.loops[loopID]?.coedges ?? [] {
                    guard let edge = result.edges[coedge.edgeID], let curve = result.geometry.curves[edge.curveID], let trim = edge.trim else {
                        throw TopologyError.missingReference("An edge of the face given a surface is missing.")
                    }
                    for index in 0...16 {
                        let point = try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double(index) / 16,
                                                    tolerance: tolerance)
                        // A pole of the new surface lies on it; its foot has no normal to find it by.
                        if poles.contains(where: { ($0.point - point).length <= tolerance.distance }) { continue }
                        gap = max(gap, (try solver.foot(of: point, on: candidate).point - point).length)
                        if gap > tolerance.distance / 4 { return false }
                    }
                }
            }
            return true
        }
        if holdsEdges == false {
            if try holds(new) {
                holdsEdges = true
            } else {
                let continued = Surface3D.bSpline(try BSplineSurfaceBoundaryExtender().continued(surface, by: (u1 - u0, v1 - v0), tolerance: tolerance))
                if try holds(continued) {
                    holdsEdges = true
                    faceSurface = continued
                }
            }
            reparameterized = holdsEdges
        }
        // Kept edges whose trimming curves cannot be built on the new surface (a straight edge on a
        // spline it is no isoline of) are re-solved where the face meets the faces beside it, which
        // gives each its parameter curves.
        // FIXME(INCOMPLETE_IMPLEMENTATION): a boundary control point moved within the face's own
        // plane leaves its straight edges on a spline whose parameters run unevenly along them: no
        // exact trimming curve exists there, and the certified intersection with the plane beside it
        // does not resolve, so the evaluation fails with that error. Production path: Rupa's control
        // point moves on a face of a solid given control points. Complete when such a face keeps its
        // edges, verified by a box face's corner control point drawn in alone.
        var resolvesEdges = holdsEdges == false
        let unchanged = result
        if holdsEdges {
          do {
            var ids = FeatureTopologyIDAllocator(featureID: feature.id)
            var surfaceID = ids.nextSurfaceID()
            while result.geometry.surfaces[surfaceID] != nil { surfaceID = ids.nextSurfaceID() }
            result.geometry.surfaces[surfaceID] = faceSurface
            result.faces[faceID]?.surfaceID = surfaceID
            result.faces[faceID]?.orientation = orientation
            if reparameterized {
                // Each edge along an isoline of the new surface (a round's sides and ends) takes that
                // isoline; any other edge its trimming curve built on it.
                // A seam's two coedges (a face closing round an axis) lie on the new surface's two
                // ends; the one that lay at the lower old parameter takes the lower end.
                var uses: [EdgeID: [SurfaceParameter]] = [:]
                for loopID in face.loops {
                    for coedge in result.loops[loopID]?.coedges ?? [] {
                        guard let old = coedge.surfaceParameterCurve else { continue }
                        uses[coedge.edgeID, default: []].append(try old.parameter(atNormalizedFraction: 0.5, tolerance: tolerance))
                    }
                }
                for loopID in face.loops {
                    guard var loop = result.loops[loopID] else { continue }
                    for index in loop.coedges.indices {
                        let coedge = loop.coedges[index]
                        var seamLowerSide: (u: Bool, v: Bool)?
                        if let pair = uses[coedge.edgeID], pair.count == 2, let mine = try coedge.surfaceParameterCurve?.parameter(atNormalizedFraction: 0.5, tolerance: tolerance) {
                            let other = pair.first { $0 != mine } ?? pair[0]
                            seamLowerSide = (mine.u <= other.u, mine.v <= other.v)
                        }
                        loop.coedges[index].surfaceParameterCurve = try isoline(of: coedge, on: faceSurface, seamLowerSide: seamLowerSide,
                                                                                model: result, tolerance: tolerance)
                    }
                    result.loops[loopID] = loop
                }
                try ExactFacePcurveBuilder().populateMissingPcurves(in: &result, tolerance: tolerance)
            }
          } catch let unsupported as KernelError where unsupported.code == .unsupportedCapability && reparameterized {
            result = unchanged
            resolvesEdges = true
          }
        }
        if resolvesEdges {
            try FaceSurfaceReplacementRebuilder().replace(
                [faceID: FaceSurfaceReplacementRebuilder.Replacement(surface: faceSurface, orientation: orientation)],
                bodyID: bodyID, featureID: feature.id, model: &result, tolerance: tolerance
            )
            try ExactFacePcurveBuilder().populateMissingPcurves(in: &result, tolerance: tolerance)
        }
        let referencedSurfaces = Set(result.faces.values.map(\.surfaceID))
        result.geometry.surfaces = result.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
        try result.validate(level: result.bodies[bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: result, context: context)
        return EvaluationResult(brep: result, subshapes: identity.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes),
                                lineage: identity.lineage)
    }

    /// The isoline of `surface` a coedge runs along, from its start to its end: constant u or
    /// constant v at nine points of its edge projected onto the surface; nil when it runs along
    /// none.
    /// The sides of a surface collapsed to one point (a pole), with the parameter each holds.
    private func collapsedSides(of surface: Surface3D, tolerance: ModelingTolerance) throws -> [(point: Point3D, u: Double?, v: Double?)] {
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(v0, v1) = surface.vDomain else { return [] }
        var collapsed: [(point: Point3D, u: Double?, v: Double?)] = []
        for (u, v) in [(Double?.none, Optional(v0)), (nil, v1), (u0, nil), (u1, nil)] {
            let ends = try [0.0, 0.5, 1.0].map { fraction in
                try surface.point(u: u ?? u0 + (u1 - u0) * fraction, v: v ?? v0 + (v1 - v0) * fraction, tolerance: tolerance)
            }
            if ends.allSatisfy({ ($0 - ends[0]).length <= tolerance.distance }) { collapsed.append((ends[0], u, v)) }
        }
        return collapsed
    }

    private func isoline(of coedge: Coedge, on surface: Surface3D, seamLowerSide: (u: Bool, v: Bool)?, model: BRepModel,
                         tolerance: ModelingTolerance) throws -> SurfaceParameterCurve? {
        guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("An edge of the face given a surface is missing.")
        }
        let (start, end) = coedge.orientation == .forward ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(v0, v1) = surface.vDomain else { return nil }
        // A sample on a side collapsed to one point (a pole) takes the side's parameter, the other
        // coordinate from the samples beside it, rather than a projection its undefined normal
        // would refuse.
        let collapsed = try collapsedSides(of: surface, tolerance: tolerance)
        var samples: [(u: Double?, v: Double?)] = []
        var points: [Point3D] = []
        var known: [Bool] = []
        for index in 0...8 {
            let point = try curve.point(at: start + (end - start) * Double(index) / 8, tolerance: tolerance)
            points.append(point)
            if let pole = collapsed.first(where: { ($0.point - point).length <= tolerance.distance }) {
                samples.append((pole.u, pole.v))
                known.append(true)
                continue
            }
            do {
                guard case let .projected(projection) = try surface.parameterProjectionResult(of: point, tolerance: tolerance) else { return nil }
                samples.append((projection.u, projection.v))
                known.append(true)
            } catch let ambiguity as KernelError where ambiguity.code == .ambiguousSelection {
                // Beside a pole the surface's parameters crowd together; the sample is read from
                // the samples beside it and not checked.
                samples.append((nil, nil))
                known.append(false)
            }
        }
        // A pole's or crowded sample's free coordinates: its nearest known neighbour's.
        for _ in 0..<8 {
            for index in samples.indices {
                let neighbours = [index - 1, index + 1].filter(samples.indices.contains).map { samples[$0] }
                if samples[index].u == nil { samples[index].u = neighbours.compactMap(\.u).first }
                if samples[index].v == nil { samples[index].v = neighbours.compactMap(\.v).first }
            }
        }
        let us = samples.compactMap(\.u), vs = samples.compactMap(\.v)
        guard us.count == 9, vs.count == 9 else { return nil }
        func atEnd(_ value: Double, _ low: Double, _ high: Double) -> Bool {
            let slack = 1e-7 * max(1, high - low)
            return abs(value - low) <= slack || abs(value - high) <= slack
        }
        // The other parameter from its first to its last value the way the edge runs — from end to
        // end of the domain where the edge closes round a seam.
        func run(_ values: [Double], _ low: Double, _ high: Double) -> (start: Double, end: Double) {
            let increasing = values[5] > values[3]
            var start = values[0], end = values[8]
            if atEnd(start, low, high) { start = increasing ? low : high }
            if atEnd(end, low, high) { end = increasing ? high : low }
            return (start, end)
        }
        // A parameter held along the edge: the middle of its values (an end of the domain when it
        // is one, the coedge's side of a seam deciding which), kept when the surface along it runs
        // through every point of the edge.
        func held(_ values: [Double], _ low: Double, _ high: Double, lower: Bool?) -> Double {
            let middle = values.sorted()[values.count / 2]
            guard atEnd(middle, low, high) || values.allSatisfy({ atEnd($0, low, high) }) else { return middle }
            if let lower { return lower ? low : high }
            return abs(middle - low) <= abs(middle - high) ? low : high
        }
        let checked = points.indices.filter { known[$0] }
        guard checked.count >= 3 else { return nil }
        let u = held(checked.map { us[$0] }, u0, u1, lower: seamLowerSide?.u)
        if try checked.allSatisfy({ (try surface.point(u: u, v: min(max(vs[$0], v0), v1), tolerance: tolerance) - points[$0]).length <= tolerance.distance }) {
            let (start, end) = run(vs, v0, v1)
            return .constantU(u: u, vStart: start, vEnd: end)
        }
        let v = held(checked.map { vs[$0] }, v0, v1, lower: seamLowerSide?.v)
        if try checked.allSatisfy({ (try surface.point(u: min(max(us[$0], u0), u1), v: v, tolerance: tolerance) - points[$0]).length <= tolerance.distance }) {
            let (start, end) = run(us, u0, u1)
            return .constantV(v: v, uStart: start, uEnd: end)
        }
        return nil
    }

    /// A face of its own sewn anew on `surface`: its trimming curves kept, each edge the surface
    /// along its trimming curve, fitted within a quarter of the distance tolerance.
    /// The body with its refitted faces' straying sides detached: nil when every side of every
    /// refitted face keeps within the distance tolerance of its edges. Each straying edge of a
    /// refitted face becomes an edge of its own along the new surface (fitted along its trimming
    /// curve there), the neighbour keeping the old one as an open edge, and the body is sewn anew.
    private func detachedSides(_ model: BRepModel, refits: [FaceID: SquareFaceRefitter.Refit], bodyID: BodyID, feature: FeatureNode,
                               context: EvaluationContext)
        throws -> (model: BRepModel, subshapes: [SubshapeID: TopologyReference], lineage: [SubshapeID: TopologyLineage])? {
        let tolerance = context.tolerance
        let correspondenceOptions = CurveSurfaceCorrespondenceValidationOptions(
            maximumSubdivisionDepth: 32, maximumCellCount: 1_048_576, maximumDeviation: tolerance.distance
        )
        /// Keep an edge only after a continuous proof over its complete oriented curve.
        func canKeep(_ edge: BRepSewingEdge, pcurve: SurfaceParameterCurve, on surface: Surface3D) throws -> Bool {
            do {
                try DefaultCurveSurfaceCorrespondenceValidator().validate(
                    curve: edge.curve, from: edge.startParameter, to: edge.endParameter,
                    surface: surface, parameterCurve: pcurve, options: correspondenceOptions, tolerance: tolerance
                )
                return true
            } catch let error as KernelError where error.code == .topologyFailure {
                return false
            }
        }
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: bodyID, featureID: feature.id, from: model, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
        )
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("A refitted body is missing.") }
        let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 4)
        var strayingCount = 0
        var shells: [BRepSewingShell] = []
        for (shellIndex, shell) in extraction.request.shells.enumerated() {
            guard shellIndex < body.shellIDs.count, let sourceShell = model.shells[body.shellIDs[shellIndex]],
                  sourceShell.faceIDs.count == shell.patches.count else {
                throw failure(.missingReference, feature.id, tolerance, "Refit lost the order of the body's faces.")
            }
            let patches = try zip(sourceShell.faceIDs, shell.patches).map { faceID, patch -> BRepSewingFacePatch in
                guard let refitted = refits[faceID] else { return patch }
                guard patch.loops.count == 1, patch.loops[0].edges.count == refitted.pcurves.count else {
                    throw failure(.topologyFailure, feature.id, tolerance, "A refitted face's loop does not match its trimming curves.")
                }
                let surface = Surface3D.bSpline(refitted.surface)
                let loop = patch.loops[0]
                let edges = try zip(loop.edges, refitted.pcurves).map { edge, pcurve -> BRepSewingEdge in
                    if try canKeep(edge, pcurve: pcurve, on: surface) {
                        return BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter,
                                              endParameter: edge.endParameter, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                              surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                                              startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                              endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                    }
                    strayingCount += 1
                    let along = { (fraction: Double) throws -> Point3D in
                        let parameter = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                        return try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                    }
                    let curve = try curveFitter.fitBSpline(breakpoints: [0, 1], tolerance: tolerance, point: along).curve
                    return BRepSewingEdge(stableID: "\(edge.stableID):refit", curve: .bSpline(curve), startParameter: 0, endParameter: 1,
                                          startPoint: try along(0), endPoint: try along(1), surfaceParameterCurve: pcurve,
                                          parentSubshapeIDs: edge.parentSubshapeIDs,
                                          startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                          endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                }
                return BRepSewingFacePatch(stableID: patch.stableID, surface: surface, orientation: refitted.orientation,
                                           loops: [BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)],
                                           parentSubshapeIDs: patch.parentSubshapeIDs)
            }
            shells.append(BRepSewingShell(stableID: shell.stableID, patches: patches, orientation: shell.orientation))
        }
        guard strayingCount > 0 else { return nil }
        guard body.kind != .solid else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a solid's face refit on a net that cannot hold its
            // sides on its edges would leave the solid open where they stray (Plasticity keeps it
            // closed with tolerant edges, which this kernel does not represent), so it is refused.
            // Production path: Rebuild Face's square method (Refit Face) on a solid. Complete only
            // when a solid's refit face may stray from its neighbours' edges and stay closed,
            // verified by a pentagonal prism's top refit on a 3 × 3 net.
            throw failure(.unsupportedCapability, feature.id, tolerance,
                          "A solid's refit face cannot certify every retained edge within the distance tolerance; ask for a net that holds its sides.")
        }
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(featureID: feature.id, bodyTopology: extraction.request.bodyTopology, shells: shells), tolerance: tolerance
        )
        let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: model)
        return (replaced, sewn.subshapes, sewn.lineage)
    }

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

    private func featureScopedKernelError(
        _ error: KernelError,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: error.code,
            featureID: featureID,
            subshapeID: error.subshapeID,
            residual: error.residual,
            tolerance: error.tolerance ?? tolerance,
            message: error.message
        )
    }

    private func continuationGeometryError(
        _ error: GeometryConversionError,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) -> KernelError {
        switch error {
        case let .invalidInput(message):
            KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: message
            )
        case let .resourceLimitExceeded(message):
            KernelError(
                phase: .evaluation,
                code: .resourceLimitExceeded,
                featureID: featureID,
                tolerance: tolerance,
                message: message
            )
        case .toleranceRejected:
            KernelError(
                phase: .evaluation,
                code: .approximationToleranceRejected,
                featureID: featureID,
                tolerance: tolerance,
                message: "Native Rebuild continuation exceeded its requested position tolerance."
            )
        }
    }
}
