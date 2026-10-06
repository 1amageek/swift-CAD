import CADCore
import CADGeometry
import CADKernel

/// A paper point proposal retaining an isolated/contact/station/collapsed original source.
public struct OriginalSilhouetteDrawingPoint: Sendable {
    public enum Selector: Sendable {
        case contact(Int), algebraicContact(Int), atlasStation(Int), singularStation(Int), collapsedCurve(Int)
    }
    public let original: BRepDrawingSilhouettes
    public let selector: Selector
    public let bodyID: BodyID
    public let faceID: FaceID
    public let pointsPerMeter: Double
    public let translation: Point2D
    public let maximumDeviation: Double
    public let point: Point2D
    let accountingOwner: DrawingExchangeUsage
    let silhouetteOwner: SurfaceSilhouetteUsage
    let admission: DrawingSilhouetteAdmission

    public static func project(_ original: BRepDrawingSilhouettes, selector: Selector,
        pointsPerMeter: Double, translation: Point2D, maximumDeviation: Double,
        admission: DrawingSilhouetteAdmission, usage: inout DrawingExchangeUsage,
        silhouetteUsage: inout SurfaceSilhouetteUsage) throws -> Self {
        guard admission.belongsToSameInvocation(as: usage, silhouetteUsage: silhouetteUsage),
            pointsPerMeter.isFinite, pointsPerMeter > 0, translation.x.isFinite, translation.y.isFinite,
            maximumDeviation.isFinite, maximumDeviation > 0 else {
            throw ExportError.invalidMesh("Original silhouette point paper map or invocation is invalid.")
        }
        let body: BodyID, face: FaceID, bounds: CoordinateEnclosure2D
        try usage.charge(entities: 1, work: 1)
        switch selector {
        case .contact(let index):
            guard original.contacts.indices.contains(index) else { throw ExportError.invalidMesh("Missing original contact selector.") }
            let value = original.contacts[index]; body = value.bodyID; face = value.faceID; bounds = value.projectedEnclosure
        case .algebraicContact(let index):
            guard original.algebraicContacts.indices.contains(index) else { throw ExportError.invalidMesh("Missing original algebraic contact selector.") }
            let value = original.algebraicContacts[index]; body = value.bodyID; face = value.faceID; bounds = value.projectedEnclosure
        case .atlasStation(let index):
            guard original.atlasStations.indices.contains(index) else { throw ExportError.invalidMesh("Missing original atlas station selector.") }
            let value = original.atlasStations[index]; body = value.bodyID; face = value.faceID; bounds = value.projectedEnclosure
        case .singularStation(let index):
            guard original.singularStations.indices.contains(index) else { throw ExportError.invalidMesh("Missing original singular station selector.") }
            let value = original.singularStations[index]; body = value.bodyID; face = value.faceID; bounds = value.projectedEnclosure
        case .collapsedCurve(let index):
            guard original.collapsedCurves.indices.contains(index) else { throw ExportError.invalidMesh("Missing original collapsed curve selector.") }
            let value = original.collapsedCurves[index]; body = value.bodyID; face = value.faceID; bounds = value.projectedEnclosure
        }
        let x = OutwardScalarInterval(lower: bounds.x.lower, upper: bounds.x.upper) * .exact(pointsPerMeter) + .exact(translation.x)
        let y = OutwardScalarInterval(lower: bounds.y.lower, upper: bounds.y.upper) * .exact(pointsPerMeter) + .exact(translation.y)
        guard x.isFinite, y.isFinite else { throw ExportError.invalidMesh("Original silhouette point enclosure is nonfinite.") }
        let point = Point2D(x: x.midpoint, y: y.midpoint)
        let uncertainty = IntervalVector3DBounds(x: x - .exact(point.x), y: y - .exact(point.y), z: .exact(0)).lengthUpperBound
        guard uncertainty.isFinite, uncertainty <= maximumDeviation else {
            throw ExportError.invalidMesh("Original silhouette point requires finer retained source precision for the caller paper deviation.")
        }
        try usage.charge(bytes: MemoryLayout<Self>.stride)
        return .init(original: original, selector: selector, bodyID: body, faceID: face, pointsPerMeter: pointsPerMeter,
            translation: translation, maximumDeviation: maximumDeviation, point: point, accountingOwner: usage,
            silhouetteOwner: silhouetteUsage, admission: admission)
    }
    func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        usage: inout SurfaceSilhouetteUsage) throws {
        switch selector {
        case .contact(let index): try original.contacts[index].source.writeOriginalProvenance(to: sink, usage: &usage)
        case .algebraicContact(let index): try original.algebraicContacts[index].source.writeOriginalProvenance(to: sink, usage: &usage)
        case .atlasStation(let index):
            let station = original.atlasStations[index]
            try station.source.writeOriginalProvenance(admittedContact: station.admittedContact, to: sink, usage: &usage)
        case .singularStation(let index): try original.singularStations[index].source.writeOriginalProvenance(to: sink, usage: &usage)
        case .collapsedCurve(let index): try original.collapsedCurves[index].curve.writeOriginalProvenance(to: sink, usage: &usage)
        }
    }
}
