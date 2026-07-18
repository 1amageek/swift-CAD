import CADCore
import CADIR
import CADModeling

struct IncrementalEvaluationState: Sendable {
    let evaluatorIdentity: String
    let documentID: DocumentID
    let schemaVersion: SchemaVersion
    let units: UnitSystem
    let parameterRevision: DocumentRevision
    let tolerance: ModelingTolerance
    let tessellationOptions: TessellationOptions
    let graph: IncrementalEvaluationGraphState
    let featureEntries: PersistentMap<FeatureID, FeatureEvaluationCacheEntry>
    let profiles: [FeatureID: [Profile]]
    let curves: [FeatureID: [EvaluatedCurve]]
}

struct FeatureEvaluationCacheEntry: Sendable {
    let key: FeatureEvaluationKey
    let brepDelta: BRepModelDelta
    let subshapesDelta: DictionaryDelta<SubshapeID, TopologyReference>
    let affectedBodyIDs: Set<BodyID>
    let profiles: [Profile]?
    let curves: [EvaluatedCurve]?
}

struct FeatureEvaluationKey: Sendable, Equatable {
    let feature: FeatureNode
    let resolvedParameters: [ParameterID: Quantity]
    let extractsProfiles: Bool
    let extractsCurves: Bool
}
