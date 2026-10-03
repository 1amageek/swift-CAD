public enum ResolvedDocumentObject: Sendable {
    case document(CADDocument)
    case feature(FeatureNode)
    case parameter(Parameter)
    case attribute(DocumentAttribute)
}
