func validateUSDPrimvarIndices(_ indices: [Int]?, valueCount: Int, name: String) throws {
    guard let indices else {
        return
    }
    for index in indices {
        guard index >= 0, index < valueCount else {
            throw USDImportError.invalidData("USD \(name) index is outside the value range.")
        }
    }
}

func validateUSDPrimvarElementCount(
    _ valueCount: Int,
    interpolation: String?,
    pointCount: Int,
    faceVertexCounts: [Int],
    name: String
) throws {
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
        throw USDImportError.invalidData("Unsupported USD \(name) interpolation \(interpolation ?? "").")
    }
    guard valueCount == expectedCount else {
        throw USDImportError.invalidData("USD \(name) value count does not match its interpolation.")
    }
}
