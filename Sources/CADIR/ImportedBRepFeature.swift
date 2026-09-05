import CADCore
import CADTopology

/// An exact B-rep retained as a source feature from an exchange import.
///
/// The model remains source authority. CADKernel is responsible for creating
/// feature-scoped topology identities and for deriving Mesh artifacts.
public struct ImportedBRepFeature: Codable, Sendable, Hashable {
    public let model: BRepModel
    /// The unit system declared by the source exchange document.
    ///
    /// Coordinates in `model` are already normalized to the kernel's internal
    /// meter/radian frame. This value preserves the source display semantics
    /// for an adapter that publishes the feature into another document.
    public let sourceUnits: UnitSystem

    public init(model: BRepModel, sourceUnits: UnitSystem = .meters) {
        self.model = model
        self.sourceUnits = sourceUnits
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try sourceUnits.validate()
        guard !model.bodies.isEmpty else {
            throw FeatureEvaluationError.emptyResult(
                "An imported B-rep source must contain at least one body."
            )
        }
        guard model.bodies.count == 1 else {
            throw FeatureEvaluationError.invalidGraph(
                "An imported B-rep source must contain exactly one body."
            )
        }
        try model.validate(level: .exact, tolerance: tolerance)
    }

    public static func == (
        lhs: ImportedBRepFeature,
        rhs: ImportedBRepFeature
    ) -> Bool {
        lhs.model == rhs.model && lhs.sourceUnits == rhs.sourceUnits
    }

    public func hash(into hasher: inout Hasher) {
        // BRepModel deliberately remains Equatable rather than Hashable. The
        // source graph only needs a cheap stable key for hash-based identity
        // containers; equality remains authoritative for the full model.
        hasher.combine(sourceUnits)
        hasher.combine(model.geometry.curves.count)
        hasher.combine(model.geometry.surfaces.count)
        hasher.combine(model.bodies.count)
        hasher.combine(model.shells.count)
        hasher.combine(model.faces.count)
        hasher.combine(model.loops.count)
        hasher.combine(model.edges.count)
        hasher.combine(model.vertices.count)
        for id in model.geometry.curves.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.geometry.surfaces.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.bodies.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.shells.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.faces.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.loops.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.edges.keys.sorted() {
            hasher.combine(id)
        }
        for id in model.vertices.keys.sorted() {
            hasher.combine(id)
        }
    }
}
