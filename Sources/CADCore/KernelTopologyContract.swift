public enum KernelTopologyContract: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case notApplicable
    case sketch
    case curve
    case subshapeGraph
    case anyBRep
    case sheetBody
    case solidBody
    case sheetOrSolidBody
    case curveOrSolidBody
    case sheetToSolidBody
    case document
    case polygonMesh
}
