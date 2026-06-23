import CADCore
import CADIR

public struct DocumentBuilder {
    private var units: UnitSystem
    private var parameters: ParameterTable
    private var designGraph: DesignGraph

    public init(units: UnitSystem) {
        self.units = units
        self.parameters = ParameterTable()
        self.designGraph = DesignGraph()
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
            profiles: [profile],
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

    public func build(name: String? = nil) throws -> CADDocument {
        let document = CADDocument(
            units: units,
            parameters: parameters,
            designGraph: designGraph,
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
}
