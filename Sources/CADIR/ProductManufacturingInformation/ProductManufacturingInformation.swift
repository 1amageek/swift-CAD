import CADCore

public struct ProductManufacturingInformation: Equatable, Sendable {
    public var datums: [ProductDatum]
    public var dimensions: [ProductDimension]
    public var tolerances: [ProductGeometricTolerance]
    public var annotations: [ProductAnnotation]
    public init(datums: [ProductDatum] = [], dimensions: [ProductDimension] = [],
                tolerances: [ProductGeometricTolerance] = [], annotations: [ProductAnnotation] = []) {
        self.datums = datums; self.dimensions = dimensions; self.tolerances = tolerances; self.annotations = annotations
    }
    public var isEmpty: Bool { datums.isEmpty && dimensions.isEmpty && tolerances.isEmpty && annotations.isEmpty }
    public var canonicalized: Self {
        Self(datums: datums.sorted { $0.id < $1.id }, dimensions: dimensions.sorted { $0.id < $1.id }, tolerances: tolerances.sorted { $0.id < $1.id }, annotations: annotations.sorted { $0.id < $1.id })
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case datums, dimensions, tolerances, annotations }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.datums, .dimensions, .tolerances, .annotations], in: decoder)
        datums = try c.decode([ProductDatum].self, forKey: .datums)
        dimensions = try c.decode([ProductDimension].self, forKey: .dimensions)
        tolerances = try c.decode([ProductGeometricTolerance].self, forKey: .tolerances)
        annotations = try c.decode([ProductAnnotation].self, forKey: .annotations)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductManufacturingInformation: Codable {}
#endif
