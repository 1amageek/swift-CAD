public struct USDDisplayColorPrimvar: Sendable, Hashable {
    public var values: [USDColorRGB]
    public var indices: [Int]?
    public var interpolation: String?

    public init(
        values: [USDColorRGB] = [],
        indices: [Int]? = nil,
        interpolation: String? = nil
    ) {
        self.values = values
        self.indices = indices
        self.interpolation = interpolation
    }

    public func validate(pointCount: Int, faceVertexCounts: [Int]) throws {
        guard !values.isEmpty else {
            throw USDImportError.invalidData("USD primvars:displayColor contains no color values.")
        }
        for value in values {
            guard value.r.isFinite, value.g.isFinite, value.b.isFinite else {
                throw USDImportError.invalidData("USD primvars:displayColor contains a non-finite color component.")
            }
        }
        try validateUSDPrimvarIndices(indices, valueCount: values.count, name: "primvars:displayColor")
        try validateUSDPrimvarElementCount(
            indices?.count ?? values.count,
            interpolation: interpolation,
            pointCount: pointCount,
            faceVertexCounts: faceVertexCounts,
            name: "primvars:displayColor"
        )
    }
}
