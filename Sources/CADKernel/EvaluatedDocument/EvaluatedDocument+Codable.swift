#if !hasFeature(Embedded)
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

extension EvaluatedDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case document
        case parameters
        case brep
        case meshes
        case curves
        case caches
        case subshapes
        case lineage
        case configuration
        case assembly
        case evaluationMetrics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .document,
                .parameters,
                .brep,
                .meshes,
                .curves,
                .caches,
                .subshapes,
                .lineage,
                .configuration,
                .assembly,
                .evaluationMetrics,
            ],
            in: decoder
        )
        let decoded = EvaluatedDocument(
            document: try container.decode(CADDocument.self, forKey: .document),
            parameters: try container.decode(ResolvedParameterTable.self, forKey: .parameters),
            brep: try container.decode(BRepModel.self, forKey: .brep),
            meshes: try container.decode(PersistentMap<BodyID, Mesh>.self, forKey: .meshes),
            curves: try container.decode([FeatureID: [EvaluatedCurve]].self, forKey: .curves),
            caches: try container.decode(DocumentCaches.self, forKey: .caches),
            subshapes: try container.decode(SubshapeIndex.self, forKey: .subshapes),
            lineage: try container.decode([SubshapeID: TopologyLineage].self, forKey: .lineage),
            configuration: try container.decode(
                DocumentEvaluationConfiguration.self,
                forKey: .configuration
            ),
            assembly: try container.decodeIfPresent(AssemblyEvaluationArtifact.self, forKey: .assembly),
            evaluationMetrics: try container.decode(
                DocumentEvaluationMetrics.self,
                forKey: .evaluationMetrics
            )
        )
        try decoded.validate()
        self = decoded
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document, forKey: .document)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(brep, forKey: .brep)
        try container.encode(meshes, forKey: .meshes)
        try container.encode(curves, forKey: .curves)
        try container.encode(caches, forKey: .caches)
        try container.encode(subshapes, forKey: .subshapes)
        try container.encode(lineage, forKey: .lineage)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(assembly, forKey: .assembly)
        try container.encode(evaluationMetrics, forKey: .evaluationMetrics)
    }
}
#endif
