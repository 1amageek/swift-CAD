#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif
import CADCore
import CADGeometry
import CADTopology

public struct SelectionDistanceMeasurement: Sendable, Hashable {
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var vector: Vector3D
    /// The midpoint of the certified minimum interval, when present.
    public var distance: Double
    public var modelLengthUnit: LengthUnit?
    public var minimumBounds: ScalarInterval?
    public var requestedOptions: BRepDistanceOptions?
    public var consumedWork: Int

    public init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint,
        modelLengthUnit: LengthUnit? = nil, minimumBounds: ScalarInterval? = nil,
        requestedOptions: BRepDistanceOptions? = nil, consumedWork: Int = 0) throws {
        try first.point.validate(); try second.point.validate(); try requestedOptions?.validate()
        self.first = first
        self.second = second
        vector = second.point - first.point
        try vector.validate()
        distance = minimumBounds?.midpoint ?? hypot(hypot(vector.x, vector.y), vector.z)
        self.modelLengthUnit = modelLengthUnit
        self.minimumBounds = minimumBounds
        self.requestedOptions = requestedOptions
        self.consumedWork = consumedWork
        guard distance.isFinite, distance >= 0, (0...262_144).contains(consumedWork),
            consumedWork <= (requestedOptions?.maximumWork ?? 262_144),
            minimumBounds.map({ $0.lower.isFinite && $0.lower >= 0 && $0.upper.isFinite && $0.lower <= $0.upper }) ?? true else {
            throw GeometryError.invalidDistance(distance)
        }
    }

    public var absoluteErrorUpperBound: Double? {
        minimumBounds.map { max((distance-$0.lower).nextUp, ($0.upper-distance).nextUp) }
    }

    public func validate() throws {
        let coherent = try Self(first: first, second: second, modelLengthUnit: modelLengthUnit,
            minimumBounds: minimumBounds, requestedOptions: requestedOptions, consumedWork: consumedWork)
        guard vector == coherent.vector, distance == coherent.distance else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                message: "Distance derived values disagree with their original measurement authority.")
        }
    }
}

#if !hasFeature(Embedded)
extension SelectionDistanceMeasurement: Codable {
    private enum CodingKeys: String, CodingKey {
        case first, second, vector, distance, modelLengthUnit, minimumBounds, requestedOptions, consumedWork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.first, .second, .vector, .distance, .modelLengthUnit, .minimumBounds, .requestedOptions, .consumedWork],
            in: decoder)
        try self.init(first: container.decode(SelectionMeasurementPoint.self, forKey: .first),
            second: container.decode(SelectionMeasurementPoint.self, forKey: .second),
            modelLengthUnit: container.decodeIfPresent(LengthUnit.self, forKey: .modelLengthUnit),
            minimumBounds: container.decodeIfPresent(ScalarInterval.self, forKey: .minimumBounds),
            requestedOptions: container.decodeIfPresent(BRepDistanceOptions.self, forKey: .requestedOptions),
            consumedWork: container.decodeIfPresent(Int.self, forKey: .consumedWork) ?? 0)
        guard try container.decode(Vector3D.self, forKey: .vector) == vector,
            try container.decode(Double.self, forKey: .distance) == distance else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Distance derived values disagree with their original measurement authority."))
        }
    }

    public func encode(to encoder: Encoder) throws {
        let coherent = try Self(first: first, second: second, modelLengthUnit: modelLengthUnit,
            minimumBounds: minimumBounds, requestedOptions: requestedOptions, consumedWork: consumedWork)
        guard vector == coherent.vector, distance == coherent.distance else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Distance derived values disagree with their original measurement authority."))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first, forKey: .first)
        try container.encode(second, forKey: .second)
        try container.encode(vector, forKey: .vector)
        try container.encode(distance, forKey: .distance)
        try container.encodeIfPresent(modelLengthUnit, forKey: .modelLengthUnit)
        try container.encodeIfPresent(minimumBounds, forKey: .minimumBounds)
        try container.encodeIfPresent(requestedOptions, forKey: .requestedOptions)
        try container.encode(consumedWork, forKey: .consumedWork)
    }
}
#endif
