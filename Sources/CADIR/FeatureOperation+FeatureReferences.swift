import CADCore

/// Feature references carried by a feature operation.
///
/// An operation's payload names other features through section, curve, target, path, guide and
/// stable subshape references. This extension is the single place that knows every such field,
/// exhaustively per operation, so callers that clone, validate or trace feature graphs never
/// enumerate payload fields themselves. Every other payload field is carried over unchanged.
extension FeatureOperation {
    /// Every feature this operation references.
    public var referencedFeatureIDs: Set<FeatureID> {
        var featureIDs: Set<FeatureID> = []
        _ = mapFeatureReferences { featureID in
            featureIDs.insert(featureID)
            return featureID
        }
        return featureIDs
    }

    /// The operation with every referenced feature replaced through `featureIDs`.
    ///
    /// A referenced feature without a replacement is a typed failure: a partially remapped
    /// operation would silently keep pointing at the original graph.
    public func remappingFeatureIDs(_ featureIDs: [FeatureID: FeatureID]) throws -> FeatureOperation {
        try mapFeatureReferences { featureID in
            guard let replacement = featureIDs[featureID] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Feature remapping has no replacement for referenced feature \(featureID.description)."
                )
            }
            return replacement
        }
    }

    /// The operation with every referenced feature passed through `transform`.
    public func mapFeatureReferences(
        _ transform: (FeatureID) throws -> FeatureID
    ) rethrows -> FeatureOperation {
        func subshape(_ reference: StableSubshapeReference) throws -> StableSubshapeReference {
            StableSubshapeReference(
                subshapeID: SubshapeID(
                    featureID: try transform(reference.subshapeID.featureID),
                    role: reference.subshapeID.role,
                    ordinal: reference.subshapeID.ordinal
                ),
                geometrySignature: reference.geometrySignature
            )
        }
        func curve(_ reference: CurveOutputReference) throws -> CurveOutputReference {
            var result = reference
            result.featureID = try transform(reference.featureID)
            return result
        }
        func section(_ reference: SectionReference) throws -> SectionReference {
            switch reference {
            case .profile(let profile):
                var result = profile
                result.featureID = try transform(profile.featureID)
                return .profile(result)
            case .curve(let curveReference):
                var result = curveReference
                result.featureID = try transform(curveReference.featureID)
                return .curve(result)
            }
        }
        func surfaceTarget(_ reference: SurfaceOperationTargetReference) throws -> SurfaceOperationTargetReference {
            SurfaceOperationTargetReference(
                featureID: try transform(reference.featureID),
                face: try subshape(reference.face)
            )
        }
        func pattern(_ reference: PatternTargetReference) throws -> PatternTargetReference {
            PatternTargetReference(featureID: try transform(reference.featureID))
        }

        switch self {
        case .involuteGear, .sketch, .spatialPath, .polySpline, .constrainedSurface, .bSplineSurface,
             .importedBRep, .primitive, .patchSurface:
            // These payloads are self-contained source geometry and name no other feature.
            return self
        case .extrude(var feature):
            feature.section = try section(feature.section)
            feature.targets = try feature.targets.map { BooleanTargetReference(featureID: try transform($0.featureID)) }
            return .extrude(feature)
        case .revolve(var feature):
            feature.section = try section(feature.section)
            return .revolve(feature)
        case .sweep(var feature):
            feature.sections = try feature.sections.map(section)
            feature.path = SweepPathReference(featureID: try transform(feature.path.featureID))
            feature.guides = try feature.guides.map { SweepGuideReference(featureID: try transform($0.featureID)) }
            feature.targets = try feature.targets.map { SweepTargetReference(featureID: try transform($0.featureID)) }
            return .sweep(feature)
        case .loft(var feature):
            feature.sections = try feature.sections.map { reference in
                var result = reference
                result.section = try section(reference.section)
                return result
            }
            feature.guides = try feature.guides.map { LoftGuideReference(featureID: try transform($0.featureID)) }
            return .loft(feature)
        case .boolean(var feature):
            feature.targets = try feature.targets.map {
                BooleanTargetReference(featureID: try transform($0.featureID), placement: $0.placement)
            }
            feature.tools = try feature.tools.map {
                BooleanToolReference(featureID: try transform($0.featureID), placement: $0.placement)
            }
            return .boolean(feature)
        case .faceLoopOffset(var feature):
            feature.target = FaceLoopOffsetTargetReference(featureID: try transform(feature.target.featureID))
            feature.face = try subshape(feature.face)
            return .faceLoopOffset(feature)
        case .edgeOffset(var feature):
            feature.target = EdgeOffsetTargetReference(featureID: try transform(feature.target.featureID))
            feature.edge = try subshape(feature.edge)
            feature.supportFace = try subshape(feature.supportFace)
            return .edgeOffset(feature)
        case .faceKnife(var feature):
            feature.target = FaceKnifeTargetReference(featureID: try transform(feature.target.featureID))
            feature.face = try subshape(feature.face)
            return .faceKnife(feature)
        case .faceDelete(var feature):
            feature.target = FaceDeleteTargetReference(featureID: try transform(feature.target.featureID))
            feature.faces = try feature.faces.map(subshape)
            return .faceDelete(feature)
        case .faceDraft(var feature):
            feature.target = FaceDraftTargetReference(featureID: try transform(feature.target.featureID))
            feature.faces = try feature.faces.map(subshape)
            feature.neutralFace = try subshape(feature.neutralFace)
            return .faceDraft(feature)
        case .bridgeCurve(var feature):
            feature.start.curve = try curve(feature.start.curve)
            feature.end.curve = try curve(feature.end.curve)
            return .bridgeCurve(feature)
        case .curveEdit(var feature):
            feature.source = try curve(feature.source)
            feature.edits = try feature.edits.map { edit in
                switch edit {
                case .setControlPoint(var controlPointEdit):
                    controlPointEdit.target.curve = try curve(controlPointEdit.target.curve)
                    return .setControlPoint(controlPointEdit)
                case .setKnot(var knotEdit):
                    knotEdit.target.curve = try curve(knotEdit.target.curve)
                    return .setKnot(knotEdit)
                case .setWeight(var weightEdit):
                    weightEdit.target.curve = try curve(weightEdit.target.curve)
                    return .setWeight(weightEdit)
                }
            }
            return .curveEdit(feature)
        case .curveOffset(var feature):
            feature.source = try curve(feature.source)
            return .curveOffset(feature)
        case .curveTrim(var feature):
            feature.source = try curve(feature.source)
            return .curveTrim(feature)
        case .bridgeSurface(let feature):
            return .bridgeSurface(BridgeSurfaceFeature(
                startBoundary: try subshape(feature.startBoundary),
                endBoundary: try subshape(feature.endBoundary),
                endOrientation: feature.endOrientation,
                startTransform: feature.startTransform,
                endTransform: feature.endTransform
            ))
        case .faceOffset(let feature):
            return .faceOffset(FaceOffsetFeature(
                target: FaceOffsetTargetReference(featureID: try transform(feature.target.featureID)),
                face: try subshape(feature.face),
                distance: feature.distance
            ))
        case .faceMove(let feature):
            return .faceMove(FaceMoveFeature(
                target: FaceMoveTargetReference(featureID: try transform(feature.target.featureID)),
                face: try subshape(feature.face),
                translation: feature.translation
            ))
        case .edgeMove(let feature):
            return .edgeMove(EdgeMoveFeature(
                target: EdgeMoveTargetReference(featureID: try transform(feature.target.featureID)),
                edge: try subshape(feature.edge),
                translation: feature.translation
            ))
        case .vertexMove(let feature):
            return .vertexMove(VertexMoveFeature(
                target: VertexMoveTargetReference(featureID: try transform(feature.target.featureID)),
                vertex: try subshape(feature.vertex),
                translation: feature.translation
            ))
        case .topologyTransform(let feature):
            return .topologyTransform(TopologyTransformFeature(
                target: TopologyTransformTargetReference(featureID: try transform(feature.target.featureID)),
                subshapes: try feature.subshapes.map { try subshape($0) },
                motion: feature.motion
            ))
        case .linearPattern(let feature):
            return .linearPattern(LinearPatternFeature(
                target: try pattern(feature.target),
                direction: feature.direction,
                spacing: feature.spacing,
                count: feature.count
            ))
        case .radialPattern(let feature):
            return .radialPattern(RadialPatternFeature(
                target: try pattern(feature.target),
                axisOrigin: feature.axisOrigin,
                axisDirection: feature.axisDirection,
                angularSpacing: feature.angularSpacing,
                count: feature.count
            ))
        case .gridPattern(let feature):
            return .gridPattern(GridPatternFeature(
                target: try pattern(feature.target),
                firstDirection: feature.firstDirection,
                firstSpacing: feature.firstSpacing,
                firstCount: feature.firstCount,
                secondDirection: feature.secondDirection,
                secondSpacing: feature.secondSpacing,
                secondCount: feature.secondCount
            ))
        case .curveDrivenPattern(let feature):
            return .curveDrivenPattern(CurveDrivenPatternFeature(
                target: try pattern(feature.target),
                path: CurveDrivenPatternPathReference(featureID: try transform(feature.path.featureID)),
                anchor: feature.anchor,
                referenceDirection: feature.referenceDirection,
                count: feature.count
            ))
        case .chamfer(let feature):
            return .chamfer(ChamferFeature(
                target: ChamferTargetReference(featureID: try transform(feature.target.featureID)),
                edges: try feature.edges.map(subshape),
                distance: feature.distance
            ))
        case .fillet(let feature):
            return .fillet(FilletFeature(
                target: FilletTargetReference(featureID: try transform(feature.target.featureID)),
                edges: try feature.edges.map(subshape),
                radius: feature.radius,
                allEdges: feature.allEdges
            ))
        case .g2Blend(let feature):
            return .g2Blend(G2BlendFeature(
                target: G2BlendTargetReference(featureID: try transform(feature.target.featureID)),
                edges: try feature.edges.map(subshape),
                distance: feature.distance
            ))
        case .setbackCorner(let feature):
            return .setbackCorner(SetbackCornerFeature(
                target: SetbackCornerTargetReference(featureID: try transform(feature.target.featureID)),
                vertex: try subshape(feature.vertex),
                radius: feature.radius
            ))
        case .shell(let feature):
            return .shell(ShellFeature(
                target: ShellTargetReference(featureID: try transform(feature.target.featureID)),
                removedFaces: try feature.removedFaces.map(subshape),
                thickness: feature.thickness
            ))
        case .thicken(let feature):
            return .thicken(ThickenFeature(
                target: ThickenTargetReference(featureID: try transform(feature.target.featureID)),
                thickness: feature.thickness,
                side: feature.side
            ))
        case .curveExtend(let feature):
            return .curveExtend(CurveExtendFeature(
                source: try curve(feature.source),
                end: feature.end,
                distance: feature.distance
            ))
        case .curveMatch(let feature):
            return .curveMatch(CurveMatchFeature(
                source: try curve(feature.source),
                sourceEnd: feature.sourceEnd,
                target: try curve(feature.target),
                targetEnd: feature.targetEnd,
                targetOrientation: feature.targetOrientation,
                continuity: feature.continuity
            ))
        case .surfaceOffset(let feature):
            return .surfaceOffset(SurfaceOffsetFeature(
                target: try surfaceTarget(feature.target),
                distance: feature.distance
            ))
        case .surfaceTrim(let feature):
            return .surfaceTrim(SurfaceTrimFeature(
                target: try surfaceTarget(feature.target),
                loops: feature.loops
            ))
        case .surfaceExtend(let feature):
            return .surfaceExtend(SurfaceExtendFeature(
                target: try surfaceTarget(feature.target),
                uDomain: feature.uDomain,
                vDomain: feature.vDomain
            ))
        case .surfaceMatch(let feature):
            return .surfaceMatch(SurfaceMatchFeature(
                source: try surfaceTarget(feature.source),
                target: try surfaceTarget(feature.target),
                sourceParameter: feature.sourceParameter,
                targetParameter: feature.targetParameter,
                normalAlignment: feature.normalAlignment,
                continuity: feature.continuity
            ))
        case .surfaceFill(let feature):
            return .surfaceFill(SurfaceFillFeature(
                targetFeatureID: try transform(feature.targetFeatureID),
                boundarySeed: try subshape(feature.boundarySeed)
            ))
        case .mirror(let feature):
            return .mirror(MirrorFeature(
                target: try pattern(feature.target),
                planeOrigin: feature.planeOrigin,
                planeNormal: feature.planeNormal,
                output: feature.output,
                cutsAtPlane: feature.cutsAtPlane
            ))
        case .joinBodies(let feature):
            return .joinBodies(JoinBodiesFeature(
                targets: try feature.targets.map {
                    JoinBodiesTargetReference(featureID: try transform($0.featureID), placement: $0.placement)
                },
                mode: feature.mode
            ))
        case .unjoinBody(let feature):
            return .unjoinBody(UnjoinBodyFeature(target: try pattern(feature.target)))
        case .unjoinFaces(let feature):
            let selection: UnjoinFacesSelection = switch feature.selection {
            case .everyFace: .everyFace
            case let .faces(faces): .faces(try faces.map(subshape))
            }
            return .unjoinFaces(UnjoinFacesFeature(target: try pattern(feature.target), selection: selection))
        case .extract(let feature):
            let selection: ExtractSelection = switch feature.selection {
            case .component: feature.selection
            case let .faces(faces): .faces(try faces.map(subshape))
            case let .solidFaces(faces): .solidFaces(try faces.map(subshape))
            }
            return .extract(ExtractFeature(target: try pattern(feature.target), selection: selection))
        case .wrap(let feature):
            return .wrap(WrapFeature(
                target: try pattern(feature.target),
                referenceFace: try subshape(feature.referenceFace),
                targetFace: try subshape(feature.targetFace),
                referencePlacement: feature.referencePlacement,
                targetPlacement: feature.targetPlacement,
                options: feature.options,
                keepsTarget: feature.keepsTarget
            ))
        case .projectCurve(let feature):
            return .projectCurve(ProjectCurveFeature(
                source: try curve(feature.source),
                planeOrigin: feature.planeOrigin,
                planeNormal: feature.planeNormal,
                direction: feature.direction
            ))
        }
    }
}

extension FeatureNode {
    /// The node with its inputs and operation references replaced through `featureIDs`.
    ///
    /// The node's own ID, name, outputs and suppression are unchanged; a clone assigns its new ID.
    public func remappingFeatureReferences(_ featureIDs: [FeatureID: FeatureID]) throws -> FeatureNode {
        var node = self
        node.inputs = try inputs.map { input in
            guard let replacement = featureIDs[input.featureID] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Feature remapping has no replacement for input feature \(input.featureID.description)."
                )
            }
            return FeatureInput(featureID: replacement, role: input.role)
        }
        node.operation = try operation.remappingFeatureIDs(featureIDs)
        return node
    }
}
