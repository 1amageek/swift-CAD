import CADCore
import CADIR

public struct DocumentBuilder {
    private var units: UnitSystem
    private var parameters: ParameterTable
    private var designGraph: DesignGraph
    private var selectionDimensions: [SelectionDimension]

    public init(units: UnitSystem) {
        self.units = units
        self.parameters = ParameterTable()
        self.designGraph = DesignGraph()
        self.selectionDimensions = []
    }

    @discardableResult
    public mutating func lengthParameter(
        named name: String,
        _ value: Double,
        _ unit: LengthUnit? = nil
    ) -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.length(value, unit: unit ?? units.length)),
            kind: .length
        )
        parameters.parameters[id] = parameter
        parameters.revision = parameters.revision.advanced()
        return id
    }

    @discardableResult
    public mutating func angleParameter(
        named name: String,
        _ value: Double,
        _ unit: AngleUnit? = nil
    ) -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.angle(value, unit: unit ?? units.angle)),
            kind: .angle
        )
        parameters.parameters[id] = parameter
        parameters.revision = parameters.revision.advanced()
        return id
    }

    @discardableResult
    public mutating func scalarParameter(named name: String, _ value: Double) -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.scalar(value)),
            kind: .scalar
        )
        parameters.parameters[id] = parameter
        parameters.revision = parameters.revision.advanced()
        return id
    }

    @discardableResult
    public mutating func sketch(
        on plane: SketchPlane,
        named name: String? = nil,
        _ build: (inout SketchBuilder) throws -> Void
    ) throws -> ProfileReference {
        var builder = SketchBuilder(on: plane)
        try build(&builder)
        let sketch = builder.build()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .sketch(sketch),
            outputs: [
                FeatureOutput(role: .profile),
                FeatureOutput(role: .curve),
            ]
        )
        append(feature)
        return ProfileReference(featureID: featureID, profileIndex: 0)
    }

    @discardableResult
    public mutating func extrude(
        _ profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection = .normal,
        named name: String? = nil
    ) -> FeatureID {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .extrude(
                ExtrudeFeature(
                    profile: profile,
                    distance: distance,
                    direction: direction,
                    operation: .newBody
                )
            ),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: profile.featureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func extrude(
        _ profile: ProfileReference,
        distance parameterID: ParameterID,
        direction: ExtrudeDirection = .normal,
        named name: String? = nil
    ) -> FeatureID {
        extrude(profile, distance: .reference(parameterID), direction: direction, named: name)
    }

    @discardableResult
    public mutating func polySpline(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        named name: String? = nil
    ) throws -> FeatureID {
        let polySpline = PolySplineFeature(sourceMesh: sourceMesh, options: options)
        try polySpline.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .polySpline(polySpline),
            outputs: [FeatureOutput(role: .sheet)]
        )
        append(feature)
        return featureID
    }

    @discardableResult
    public mutating func bSplineSurface(
        _ surface: BSplineSurface3D,
        material: MaterialID? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let surfaceFeature = BSplineSurfaceFeature(surface: surface, material: material)
        try surfaceFeature.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .bSplineSurface(surfaceFeature),
            outputs: [FeatureOutput(role: .sheet)]
        )
        append(feature)
        return featureID
    }

    @discardableResult
    public mutating func faceLoopOffset(
        target targetFeatureID: FeatureID,
        facePersistentName: PersistentName,
        distance: CADExpression,
        gapFill: FaceLoopOffsetGapFill = .round,
        named name: String? = nil
    ) throws -> FeatureID {
        let faceLoopOffset = FaceLoopOffsetFeature(
            target: FaceLoopOffsetTargetReference(featureID: targetFeatureID),
            facePersistentName: facePersistentName,
            distance: distance,
            gapFill: gapFill
        )
        try faceLoopOffset.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .faceLoopOffset(faceLoopOffset),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: targetFeatureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func faceLoopOffset(
        target targetFeatureID: FeatureID,
        facePersistentName: PersistentName,
        distance parameterID: ParameterID,
        gapFill: FaceLoopOffsetGapFill = .round,
        named name: String? = nil
    ) throws -> FeatureID {
        try faceLoopOffset(
            target: targetFeatureID,
            facePersistentName: facePersistentName,
            distance: .reference(parameterID),
            gapFill: gapFill,
            named: name
        )
    }

    @discardableResult
    public mutating func faceKnife(
        target targetFeatureID: FeatureID,
        facePersistentName: PersistentName,
        loop: [Point3D],
        named name: String? = nil
    ) throws -> FeatureID {
        let faceKnife = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: targetFeatureID),
            facePersistentName: facePersistentName,
            loop: loop
        )
        try faceKnife.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .faceKnife(faceKnife),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: targetFeatureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func faceDelete(
        target targetFeatureID: FeatureID,
        facePersistentNames: [PersistentName],
        named name: String? = nil
    ) throws -> FeatureID {
        let faceDelete = FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: targetFeatureID),
            facePersistentNames: facePersistentNames
        )
        try faceDelete.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .faceDelete(faceDelete),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: targetFeatureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func faceDraft(
        target targetFeatureID: FeatureID,
        facePersistentNames: [PersistentName],
        neutralFacePersistentName: PersistentName,
        angle: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let faceDraft = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: targetFeatureID),
            facePersistentNames: facePersistentNames,
            neutralFacePersistentName: neutralFacePersistentName,
            angle: angle
        )
        try faceDraft.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .faceDraft(faceDraft),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: targetFeatureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func faceDraft(
        target targetFeatureID: FeatureID,
        facePersistentNames: [PersistentName],
        neutralFacePersistentName: PersistentName,
        angle parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try faceDraft(
            target: targetFeatureID,
            facePersistentNames: facePersistentNames,
            neutralFacePersistentName: neutralFacePersistentName,
            angle: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func bridgeCurve(
        from start: BridgeCurveEndpointTarget,
        to end: BridgeCurveEndpointTarget,
        sampleCount: Int = 33,
        continuityTolerances: CurveContinuityTolerances = .standard(),
        named name: String? = nil
    ) throws -> FeatureID {
        let bridgeCurve = BridgeCurveFeature(
            start: start,
            end: end,
            sampleCount: sampleCount,
            continuityTolerances: continuityTolerances
        )
        try bridgeCurve.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .bridgeCurve(bridgeCurve),
            outputs: [FeatureOutput(role: .curve)]
        )
        append(feature)
        return featureID
    }

    @discardableResult
    public mutating func editCurve(
        _ source: CurveOutputReference,
        edits: [CurveEdit],
        sampleCount: Int = 33,
        named name: String? = nil
    ) throws -> FeatureID {
        let curveEdit = CurveEditFeature(
            source: source,
            edits: edits,
            sampleCount: sampleCount
        )
        try curveEdit.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .curveEdit(curveEdit),
            inputs: [FeatureInput(featureID: source.featureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: source.featureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func offsetCurve(
        _ source: CurveOutputReference,
        distance: CADExpression,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left,
        sampleCount: Int = 33,
        named name: String? = nil
    ) throws -> FeatureID {
        let curveOffset = CurveOffsetFeature(
            source: source,
            distance: distance,
            planeNormal: planeNormal,
            side: side,
            sampleCount: sampleCount
        )
        try curveOffset.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .curveOffset(curveOffset),
            inputs: [FeatureInput(featureID: source.featureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: source.featureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func offsetCurve(
        _ source: CurveOutputReference,
        distance parameterID: ParameterID,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left,
        sampleCount: Int = 33,
        named name: String? = nil
    ) throws -> FeatureID {
        try offsetCurve(
            source,
            distance: .reference(parameterID),
            planeNormal: planeNormal,
            side: side,
            sampleCount: sampleCount,
            named: name
        )
    }

    @discardableResult
    public mutating func trimCurve(
        _ source: CurveOutputReference,
        domain: ParameterDomain,
        sampleCount: Int = 33,
        named name: String? = nil
    ) throws -> FeatureID {
        let curveTrim = CurveTrimFeature(
            source: source,
            domain: domain,
            sampleCount: sampleCount
        )
        try curveTrim.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .curveTrim(curveTrim),
            inputs: [FeatureInput(featureID: source.featureID, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: source.featureID, target: featureID))
        return featureID
    }

    @discardableResult
    public mutating func distanceDimension(
        from first: SelectionReference,
        to second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        try selectionDimension(
            kind: .distance,
            from: first,
            to: second,
            target: target,
            named: name
        )
    }

    @discardableResult
    public mutating func angleDimension(
        between first: SelectionReference,
        and second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        try selectionDimension(
            kind: .angle,
            from: first,
            to: second,
            target: target,
            named: name
        )
    }

    @discardableResult
    public mutating func selectionDimension(
        kind: SelectionDimensionKind,
        from first: SelectionReference,
        to second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        let dimension = SelectionDimension(
            name: name,
            kind: kind,
            first: first,
            second: second,
            target: target
        )
        var document = CADDocument(
            units: units,
            parameters: parameters,
            designGraph: designGraph,
            selectionDimensions: selectionDimensions
        )
        let dimensionID = try document.addSelectionDimension(dimension)
        selectionDimensions = document.selectionDimensions
        return dimensionID
    }

    @discardableResult
    public mutating func sweep(
        _ profile: ProfileReference,
        along pathFeatureID: FeatureID,
        guides guideFeatureIDs: [FeatureID] = [],
        targets targetFeatureIDs: [FeatureID] = [],
        options: SweepOptions = SweepOptions(),
        named name: String? = nil
    ) -> FeatureID {
        let guides = guideFeatureIDs.map(SweepGuideReference.init)
        let targets = targetFeatureIDs.map(SweepTargetReference.init)
        let sweep = SweepFeature(
            sections: [.profile(profile)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: guides,
            targets: targets,
            options: options
        )
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .sweep(sweep),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)]
                + [FeatureInput(featureID: pathFeatureID, role: .path)]
                + guideFeatureIDs.map { FeatureInput(featureID: $0, role: .guide) }
                + targetFeatureIDs.map { FeatureInput(featureID: $0, role: .target) },
            outputs: [FeatureOutput(role: sweepOutputRole(for: options.resultKind))]
        )
        append(feature)
        designGraph.dependencies.append(DependencyEdge(source: profile.featureID, target: featureID))
        designGraph.dependencies.append(DependencyEdge(source: pathFeatureID, target: featureID))
        for guideFeatureID in guideFeatureIDs {
            designGraph.dependencies.append(DependencyEdge(source: guideFeatureID, target: featureID))
        }
        for targetFeatureID in targetFeatureIDs {
            designGraph.dependencies.append(DependencyEdge(source: targetFeatureID, target: featureID))
        }
        return featureID
    }

    @discardableResult
    public mutating func loft(
        sections: [LoftSectionReference],
        options: LoftOptions = LoftOptions(),
        named name: String? = nil
    ) throws -> FeatureID {
        let loft = LoftFeature(sections: sections, options: options)
        try loft.validate()
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .loft(loft),
            inputs: sections.map { section in
                FeatureInput(featureID: section.featureID, role: .profile)
            },
            outputs: [FeatureOutput(role: loftOutputRole(for: options.resultKind))]
        )
        append(feature)
        designGraph.dependencies.append(contentsOf: sections.map { section in
            DependencyEdge(source: section.featureID, target: featureID)
        })
        return featureID
    }

    public func build(name: String? = nil) throws -> CADDocument {
        let document = CADDocument(
            units: units,
            parameters: parameters,
            designGraph: designGraph,
            selectionDimensions: selectionDimensions,
            metadata: DocumentMetadata(name: name)
        )
        try document.validate()
        return document
    }

    private mutating func append(_ feature: FeatureNode) {
        designGraph.nodes[feature.id] = feature
        designGraph.order.append(feature.id)
        designGraph.revision = designGraph.revision.advanced()
    }

    private func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
        switch resultKind {
        case .solid:
            return .body
        case .sheet:
            return .sheet
        }
    }

    private func loftOutputRole(for resultKind: LoftResultKind) -> FeaturePort {
        switch resultKind {
        case .solid:
            return .body
        case .sheet:
            return .sheet
        }
    }
}
