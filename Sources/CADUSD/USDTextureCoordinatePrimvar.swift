public struct USDTextureCoordinatePrimvar: Sendable, Hashable {
    public var values: [USDPoint2D]
    public var indices: [Int]?
    public var interpolation: String?

    public init(
        values: [USDPoint2D] = [],
        indices: [Int]? = nil,
        interpolation: String? = nil
    ) {
        self.values = values
        self.indices = indices
        self.interpolation = interpolation
    }

    public func validate(pointCount: Int, faceVertexCounts: [Int]) throws {
        guard !values.isEmpty else {
            throw USDImportError.invalidData("USD primvars:st contains no texture coordinate values.")
        }
        if let indices {
            for index in indices {
                guard index >= 0, index < values.count else {
                    throw USDImportError.invalidData("USD primvars:st index is outside the texture coordinate value range.")
                }
            }
        }

        let valueCount = indices?.count ?? values.count
        let expectedCount: Int
        switch interpolation ?? "constant" {
        case "constant":
            expectedCount = 1
        case "uniform":
            expectedCount = faceVertexCounts.count
        case "vertex", "varying":
            expectedCount = pointCount
        case "faceVarying":
            expectedCount = faceVertexCounts.reduce(0, +)
        default:
            throw USDImportError.invalidData("Unsupported USD primvars:st interpolation \(interpolation ?? "").")
        }
        guard valueCount == expectedCount else {
            throw USDImportError.invalidData("USD primvars:st value count does not match its interpolation.")
        }
    }
}
