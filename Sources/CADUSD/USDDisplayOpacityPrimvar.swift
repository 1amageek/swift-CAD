public struct USDDisplayOpacityPrimvar: Sendable, Hashable {
    public var values: [Double]
    public var indices: [Int]?
    public var interpolation: String?

    public init(
        values: [Double] = [],
        indices: [Int]? = nil,
        interpolation: String? = nil
    ) {
        self.values = values
        self.indices = indices
        self.interpolation = interpolation
    }

    public func validate(pointCount: Int, faceVertexCounts: [Int]) throws {
        guard !values.isEmpty else {
            throw USDImportError.invalidData("USD primvars:displayOpacity contains no opacity values.")
        }
        for value in values {
            guard value.isFinite else {
                throw USDImportError.invalidData("USD primvars:displayOpacity contains a non-finite opacity value.")
            }
        }
        try validateUSDPrimvarIndices(indices, valueCount: values.count, name: "primvars:displayOpacity")
        try validateUSDPrimvarElementCount(
            indices?.count ?? values.count,
            interpolation: interpolation,
            pointCount: pointCount,
            faceVertexCounts: faceVertexCounts,
            name: "primvars:displayOpacity"
        )
    }
}
