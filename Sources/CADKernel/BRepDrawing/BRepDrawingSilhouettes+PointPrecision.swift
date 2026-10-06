import CADCore
import CADGeometry

extension BRepDrawingSilhouettes {
    /// Retains source-root localization when requesting finer paper point proposals.
    public func refiningAlgebraicPoints(maximumParameterWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes {
        guard maximumParameterWidth.isPositive else {
            throw GeometryConversionError.invalidInput("Silhouette point native precision must be positive.")
        }
        let width = try maximumParameterWidth.outwardInterval(usage: &usage).lower
        guard width.isFinite, width > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Silhouette point native precision has no positive binary query bound.")
        }
        func retain<T>(_ count: Int, _ type: T.Type) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Silhouette point receipt storage overflowed.") }
            try usage.preparationStorageCallback(bytes.partialValue)
        }
        func project(_ point: CoordinateEnclosure3D) throws -> CoordinateEnclosure2D {
            let x = OutwardScalarInterval(lower: point.x.lower, upper: point.x.upper) - .exact(frame.origin.x)
            let y = OutwardScalarInterval(lower: point.y.lower, upper: point.y.upper) - .exact(frame.origin.y)
            let z = OutwardScalarInterval(lower: point.z.lower, upper: point.z.upper) - .exact(frame.origin.z)
            func component(_ axis: Vector3D) throws -> ScalarInterval {
                let value = x * .exact(axis.x) + y * .exact(axis.y) + z * .exact(axis.z)
                guard value.isFinite else { throw GeometryConversionError.invalidInput("Refined original silhouette point projection is nonfinite.") }
                return try .init(lower: value.lower, upper: value.upper)
            }
            return try .init(x: component(frame.horizontal), y: component(frame.vertical))
        }
        try retain(algebraicContacts.count, BRepDrawingSilhouetteAlgebraicContact.self)
        try retain(atlasStations.count, BRepDrawingSilhouetteAtlasStation.self)
        var refined: [BRepDrawingSilhouetteAlgebraicContact] = []; refined.reserveCapacity(algebraicContacts.count)
        var stations: [BRepDrawingSilhouetteAtlasStation] = []; stations.reserveCapacity(atlasStations.count)
        for contact in algebraicContacts {
            try usage.consumeWork()
            let source = try contact.source.refined(maximumUWidth: width, maximumVWidth: width, usage: &usage)
            refined.append(.init(bodyID: contact.bodyID, faceID: contact.faceID, source: source,
                projectedEnclosure: try project(source.spatialEnclosure)))
        }
        for station in atlasStations {
            try usage.consumeWork()
            let source = try station.admittedContact.refined(maximumUWidth: width, maximumVWidth: width, usage: &usage)
            stations.append(.init(bodyID: station.bodyID, faceID: station.faceID,
                atlasOrdinal: station.atlasOrdinal, stationOrdinal: station.stationOrdinal,
                source: station.source, admittedContact: source, projectedEnclosure: try project(source.spatialEnclosure)))
        }
        try retain(1, BRepDrawingSilhouettes.self)
        return .init(sourceDocument: sourceDocument, configuration: configuration, frame: frame,
            contacts: contacts, algebraicContacts: refined, atlasStations: stations,
            collapsedCurves: collapsedCurves, singularStations: singularStations,
            originalFaces: originalFaces, sourceSnapshot: sourceSnapshot, spans: spans,
            exactTrimmedSpans: exactTrimmedSpans, trimPartitions: trimPartitions,
            coincidentFaceIDs: coincidentFaceIDs, placement: placement)
    }
}
