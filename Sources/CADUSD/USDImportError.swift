public enum USDImportError: Error, Sendable, Equatable {
    case invalidData(String)
    case missingRequiredField(String)
    case unsupportedFeature(String)
    case notImplemented(String)
}
