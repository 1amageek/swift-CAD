public struct USDMesh: Sendable, Hashable {
    public static let fallbackSubdivisionScheme = "catmullClark"

    public var name: String?
    public var points: [USDPoint3D]
    public var faceVertexCounts: [Int]
    public var faceVertexIndices: [Int]
    public var normals: [USDPoint3D]
    public var normalsInterpolation: String?
    public var orientation: USDOrientation?
    public var subdivisionScheme: String?
    public var textureCoordinates: USDTextureCoordinatePrimvar?
    public var displayColor: USDDisplayColorPrimvar?
    public var displayOpacity: USDDisplayOpacityPrimvar?
    public var extent: [USDPoint3D]?

    public init(
        name: String? = nil,
        points: [USDPoint3D] = [],
        faceVertexCounts: [Int] = [],
        faceVertexIndices: [Int] = [],
        normals: [USDPoint3D] = [],
        normalsInterpolation: String? = nil,
        orientation: USDOrientation? = nil,
        subdivisionScheme: String? = nil,
        textureCoordinates: USDTextureCoordinatePrimvar? = nil,
        displayColor: USDDisplayColorPrimvar? = nil,
        displayOpacity: USDDisplayOpacityPrimvar? = nil,
        extent: [USDPoint3D]? = nil
    ) {
        self.name = name
        self.points = points
        self.faceVertexCounts = faceVertexCounts
        self.faceVertexIndices = faceVertexIndices
        self.normals = normals
        self.normalsInterpolation = normalsInterpolation
        self.orientation = orientation
        self.subdivisionScheme = subdivisionScheme
        self.textureCoordinates = textureCoordinates
        self.displayColor = displayColor
        self.displayOpacity = displayOpacity
        self.extent = extent
    }

    public var effectiveSubdivisionScheme: String {
        subdivisionScheme ?? Self.fallbackSubdivisionScheme
    }
}
