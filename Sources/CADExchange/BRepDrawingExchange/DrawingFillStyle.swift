import CADCore

public struct DrawingFillStyle: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double = 0.92, green: Double = 0.92, blue: Double = 0.92) {
        self.red = red; self.green = green; self.blue = blue
    }
    public func validate() throws {
        guard red.isFinite, green.isFinite, blue.isFinite,
              (0...1).contains(red), (0...1).contains(green), (0...1).contains(blue) else {
            throw ExportError.invalidMesh("Invalid drawing material fill color.")
        }
    }
    var trueColor: Int { (Int((red * 255).rounded()) << 16) | (Int((green * 255).rounded()) << 8) | Int((blue * 255).rounded()) }
}
