import CADCore

struct BRepDrawingOutputRegion {
    let identity: String
    let loops: [[Point2D]]
    let outer: [Bool]
}
