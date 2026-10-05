import CADCore

/// Physical stroke appearance; width and dash lengths are measured in paper points.
public struct DrawingStrokeStyle: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let width: Double
    public let dashPattern: [Double]
    public init(red: Double = 0, green: Double = 0, blue: Double = 0,
                width: Double = 0.35, dashPattern: [Double] = []) {
        self.red = red; self.green = green; self.blue = blue
        self.width = width; self.dashPattern = dashPattern
    }
    public func validate() throws {
        guard red.isFinite, green.isFinite, blue.isFinite,
              (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue),
              width.isFinite, width > 0 else { throw ExportError.invalidMesh("Invalid drawing stroke color or physical width.") }
        for length in dashPattern {
            try Task.checkCancellation()
            guard length.isFinite, length > 0 else { throw ExportError.invalidMesh("Invalid physical drawing dash length.") }
        }
    }
    var trueColor: Int { (Int((red * 255).rounded()) << 16) | (Int((green * 255).rounded()) << 8) | Int((blue * 255).rounded()) }
}
