public protocol BRepDrawingRegionProducing: Sendable {
    func regions(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                 maximumBoundaryEdges: Int, maximumRegions: Int) throws -> [BRepDrawingMaterialRegion]
}
