import CADCore

/// Atomic spatial publication of an exhaustive original station/strip atlas.
struct SurfaceSilhouettePlaneAtlasPublication {
    let curves: [OriginalSurfaceSilhouetteCurve]
    let isolatedContacts: [SurfaceSilhouetteAlgebraicContact]
    let provenance: SurfaceSilhouettePlaneAtlas

    init(field originalField: OriginalSurfaceSilhouetteField, atlas: OriginalRationalPlaneCurveAtlas,
        firstCurveIndex: Int, usage: inout OriginalQueryExecution) throws {
        guard firstCurveIndex >= 0, atlas.projection.verticalComponents.isEmpty,
            atlas.projection.horizontalComponents.isEmpty else {
            throw rationalAlgebraFailure("Original generic plane publication requires separately retained coordinate components.")
        }
        let field = try originalField.selectingOriginalFactor(atlas.projection.primitive, usage: &usage)
        var curves: [OriginalSurfaceSilhouetteCurve] = []
        var stationCurves: [[Int]] = [], stationEnds: [[Bool]] = []
        try RationalAlgebraStorage.retain(atlas.stations.count, of: [Int].self, usage: &usage)
        try RationalAlgebraStorage.retain(atlas.stations.count, of: [Bool].self, usage: &usage)
        stationCurves.reserveCapacity(atlas.stations.count); stationEnds.reserveCapacity(atlas.stations.count)
        for _ in atlas.stations { stationCurves.append([]); stationEnds.append([]) }
        for incidence in atlas.incidences {
            let station = atlas.stations[incidence.stationIndex]
            let attachment = incidence.attachment
            var count = 0
            for candidate in atlas.incidences {
                try usage.consumeWork(1)
                if candidate.stationIndex == incidence.stationIndex { count = try rationalAlgebraCount(count, 1) }
            }
            let image = try SurfaceSilhouetteRamifiedParameterImage(resolution: station.resolution,
                attachment: attachment, chart: station.charts[attachment.chartIndex],
                sourceDomain: atlas.projection.domain, usage: &usage)
            guard let upper = image.originAtUpperEnd else { throw rationalAlgebraFailure("Original half-branch lost its origin endpoint.") }
            let origin = SurfaceSilhouetteAtlasEndpoint(original: atlas.projection.primitive,
                location: .station(station.originalRoot, completeHalfBranchCount: count))
            let anchor = SurfaceSilhouetteAtlasEndpoint(original: atlas.projection.primitive,
                location: .fiber(attachment.originalFreeWitness, attachment.originalFiber))
            let globalIndex = try rationalAlgebraCount(firstCurveIndex, curves.count)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Bool.self, usage: &usage)
            stationCurves[incidence.stationIndex].append(globalIndex)
            stationEnds[incidence.stationIndex].append(upper)
            try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
            curves.append(OriginalSurfaceSilhouetteCurve(field: field, chart: atlas.projection.domain,
                freeCoordinate: station.charts[attachment.chartIndex].freeAlongU ? .u : .v,
                ramifiedImage: image, atlasStart: upper ? anchor : origin, atlasEnd: upper ? origin : anchor))
        }
        for strip in atlas.strips {
            for piece in strip.originalCover.pieces {
                func endpoint(_ u: ExactRationalCoefficient, usage: inout OriginalQueryExecution)
                    throws -> SurfaceSilhouetteAtlasEndpoint {
                    let source = try atlas.projection.primitive.restricted(alongU: true, station: u, usage: &usage)
                    let roots = try OriginalRationalPlaneCurveProjection.sliceRoots(source,
                        lower: .originalDouble(piece.domain.v.lower, usage: &usage),
                        upper: .originalDouble(piece.domain.v.upper, usage: &usage),
                        parentDepth: piece.sourceDepth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    guard roots.count == 1, case .algebraic(let root) = roots[0] else {
                        throw rationalAlgebraFailure("Original regular tube endpoint lost its unique transverse source root.")
                    }
                    return SurfaceSilhouetteAtlasEndpoint(original: atlas.projection.primitive, location: .fiber(u, root))
                }
                let first = try endpoint(piece.lower, usage: &usage), last = try endpoint(piece.upper, usage: &usage)
                let image = try SurfaceSilhouetteFreeParameterImage(start: .authored(piece.lower), end: .authored(piece.upper))
                try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                curves.append(OriginalSurfaceSilhouetteCurve(field: field, chart: piece.domain,
                    freeCoordinate: .u, freeImage: image, atlasStart: first, atlasEnd: last))
            }
        }
        var contacts: [SurfaceSilhouetteAlgebraicContact] = []
        var stations: [SurfaceSilhouettePlaneAtlas.Station] = []
        for index in atlas.stations.indices {
            let station = atlas.stations[index]
            let contact = try SurfaceSilhouetteAlgebraicContact(field: field, originalRoot: station.originalRoot,
                certifiedDomain: atlas.projection.domain, usage: &usage)
            if stationCurves[index].isEmpty {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                contacts.append(contact)
            }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouettePlaneAtlas.Station.self, usage: &usage)
            stations.append(.init(originalContact: contact, incidentCurveIndices: stationCurves[index],
                incidentAtUpperEnd: stationEnds[index], regularGermCount: station.resolution.germs.count,
                isolatedGermCount: station.resolution.isolatedGerms.count,
                sourceDepth: max(station.originalRoot.projectionRoot.isolation.isolationDepth,
                    station.originalRoot.fiberRoot.isolationDepth)))
        }
        try RationalAlgebraStorage.retain(curves.count, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(curves.count)
        for index in curves.indices { indices.append(try rationalAlgebraCount(firstCurveIndex, index)) }
        self.curves = curves; isolatedContacts = contacts
        provenance = SurfaceSilhouettePlaneAtlas(field: field, original: atlas, curveIndices: indices, stations: stations)
    }

    init(field originalField: OriginalSurfaceSilhouetteField, atlas: OriginalFieldPlaneAtlas,
        firstCurveIndex: Int, usage: inout OriginalQueryExecution) throws {
        guard firstCurveIndex >= 0 else { throw rationalAlgebraFailure("Original atlas curve offset must be nonnegative.") }
        let coordinates = try SurfaceSilhouetteFieldCoordinateComponents(field: originalField,
            projection: atlas.projection, usage: &usage)
        let field = try originalField.selectingOriginalFieldFactor(atlas.projection.primitive, usage: &usage)
        try RationalAlgebraStorage.retain(coordinates.curves.count, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
        var curves = coordinates.curves
        var stationCurves: [[Int]] = [], stationEnds: [[Bool]] = []
        try RationalAlgebraStorage.retain(atlas.stations.count, of: [Int].self, usage: &usage)
        try RationalAlgebraStorage.retain(atlas.stations.count, of: [Bool].self, usage: &usage)
        stationCurves.reserveCapacity(atlas.stations.count); stationEnds.reserveCapacity(atlas.stations.count)
        for _ in atlas.stations { stationCurves.append([]); stationEnds.append([]) }
        if !atlas.incidences.isEmpty {
            try Self.appendFieldIncidences(atlas: atlas, firstCurveIndex: firstCurveIndex, curves: &curves, stationCurves: &stationCurves, stationEnds: &stationEnds, field: field, usage: &usage)
        }
        if !atlas.strips.isEmpty {
            try Self.appendFieldStrips(atlas: atlas, firstCurveIndex: firstCurveIndex, curves: &curves, stationCurves: &stationCurves, stationEnds: &stationEnds, field: field, usage: &usage)
        }
        if !curves.isEmpty {
            try Self.retainCompleteFieldIncidence(atlas: atlas, firstCurveIndex: firstCurveIndex, curves: &curves, stationCurves: &stationCurves, stationEnds: &stationEnds, usage: &usage)
        }
        var contacts: [SurfaceSilhouetteAlgebraicContact] = []
        var stations: [SurfaceSilhouettePlaneAtlas.Station] = []
        if !atlas.stations.isEmpty {
            try Self.appendFieldStations(atlas: atlas, firstCurveIndex: firstCurveIndex, curves: &curves, stationCurves: &stationCurves, stationEnds: &stationEnds, originalField: originalField, coordinates: coordinates, contacts: &contacts, stations: &stations, usage: &usage)
        }
        if !coordinates.endpoints.isEmpty {
            try Self.appendCoordinateStations(atlas: atlas, firstCurveIndex: firstCurveIndex, curves: &curves, stationCurves: &stationCurves, stationEnds: &stationEnds, originalField: originalField, coordinates: coordinates, stations: &stations, usage: &usage)
        }
        try RationalAlgebraStorage.retain(curves.count, of: Int.self, usage: &usage)
        var indices: [Int] = []; indices.reserveCapacity(curves.count)
        for index in curves.indices { indices.append(try rationalAlgebraCount(firstCurveIndex, index)) }
        self.curves = curves; isolatedContacts = contacts
        provenance = SurfaceSilhouettePlaneAtlas(field: field, original: atlas, curveIndices: indices, stations: stations)
    }

    @inline(never)
    private static func appendFieldIncidences(
        atlas: OriginalFieldPlaneAtlas, firstCurveIndex: Int,
        curves: inout [OriginalSurfaceSilhouetteCurve],
        stationCurves: inout [[Int]], stationEnds: inout [[Bool]],
        field: OriginalSurfaceSilhouetteField,
        usage: inout OriginalQueryExecution
    ) throws {
        for incidence in atlas.incidences {
            let station = atlas.stations[incidence.stationIndex]
            let attachment = incidence.attachment
            var count = 0
            for candidate in atlas.incidences {
                try usage.consumeWork(1)
                if candidate.stationIndex == incidence.stationIndex { count = try rationalAlgebraCount(count, 1) }
            }
            let image = try SurfaceSilhouetteRamifiedParameterImage(resolution: station.resolution,
                attachment: attachment, chart: station.charts[attachment.chartIndex],
                sourceDomain: atlas.projection.domain, usage: &usage)
            guard let upper = image.originAtUpperEnd else { throw rationalAlgebraFailure("Original half-branch lost its origin endpoint.") }
            let origin = SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree,
                location: .station(station.originalRoot, completeHalfBranchCount: count))
            let anchor = SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree,
                location: .fiber(attachment.originalFreeWitness, attachment.originalFiber))
            let globalIndex = try rationalAlgebraCount(firstCurveIndex, curves.count)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: Bool.self, usage: &usage)
            stationCurves[incidence.stationIndex].append(globalIndex)
            stationEnds[incidence.stationIndex].append(upper)
            try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
            curves.append(OriginalSurfaceSilhouetteCurve(field: field, chart: atlas.projection.domain,
                freeCoordinate: station.charts[attachment.chartIndex].freeAlongU ? .u : .v,
                ramifiedImage: image, fieldAtlasStart: upper ? anchor : origin, fieldAtlasEnd: upper ? origin : anchor))
        }
    }

    @inline(never)
    private static func appendFieldStrips(
        atlas: OriginalFieldPlaneAtlas, firstCurveIndex: Int,
        curves: inout [OriginalSurfaceSilhouetteCurve],
        stationCurves: inout [[Int]], stationEnds: inout [[Bool]],
        field: OriginalSurfaceSilhouetteField,
        usage: inout OriginalQueryExecution
    ) throws {
        for strip in atlas.strips {
            for piece in strip.originalInteriorCover.pieces {
                func endpoint(_ u: ExactRationalCoefficient, usage: inout OriginalQueryExecution)
                    throws -> SurfaceSilhouetteFieldAtlasEndpoint {
                    let source = try OriginalSingularFieldPlaneProjection.restricted(atlas.projection.primitive,
                        alongU: true, station: u, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(source,
                        lower: .originalDouble(piece.domain.v.lower, usage: &usage),
                        upper: .originalDouble(piece.domain.v.upper, usage: &usage),
                        inheritedDepth: piece.sourceDepth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    guard roots.count == 1, let root = roots.first else {
                        throw rationalAlgebraFailure("Original regular tube endpoint lost its unique transverse source root.")
                    }
                    return SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree, location: .fiber(u, root))
                }
                let first = try endpoint(piece.lower, usage: &usage), last = try endpoint(piece.upper, usage: &usage)
                let image = try SurfaceSilhouetteFreeParameterImage(start: .authored(piece.lower), end: .authored(piece.upper))
                try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                curves.append(OriginalSurfaceSilhouetteCurve(field: field, chart: piece.domain,
                    freeCoordinate: .u, freeImage: image, fieldAtlasStart: first, fieldAtlasEnd: last))
            }
        }
    }

    @inline(never)
    private static func retainCompleteFieldIncidence(
        atlas: OriginalFieldPlaneAtlas, firstCurveIndex: Int,
        curves: inout [OriginalSurfaceSilhouetteCurve],
        stationCurves: inout [[Int]], stationEnds: inout [[Bool]],
        usage: inout OriginalQueryExecution
    ) throws {
        // Complete counts include coordinate and primitive original half-branches.
        // Endpoints are compared by exact retained UV authority, never by bounds.
        for index in curves.indices {
            guard let endpoints = curves[index].originalFieldAtlasEndpoints else {
                throw rationalAlgebraFailure("Original field atlas curve lost complete endpoint provenance.")
            }
            func count(_ endpoint: SurfaceSilhouetteFieldAtlasEndpoint, usage: inout OriginalQueryExecution) throws -> Int {
                var count = 0
                for curve in curves {
                    try usage.consumeWork(1)
                    guard let pair = curve.originalFieldAtlasEndpoints else {
                        throw rationalAlgebraFailure("Original field atlas incidence lost another source endpoint.")
                    }
                    if try endpoint.hasSameValue(as: pair.first, usage: &usage) { count = try rationalAlgebraCount(count, 1) }
                    if try endpoint.hasSameValue(as: pair.last, usage: &usage) { count = try rationalAlgebraCount(count, 1) }
                }
                return count
            }
            let a = try count(endpoints.first, usage: &usage), b = try count(endpoints.last, usage: &usage)
            curves[index] = curves[index].retainingFieldIncidence(
                first: endpoints.first.retainingCompleteIncidence(a), last: endpoints.last.retainingCompleteIncidence(b))
        }
    }

    @inline(never)
    private static func appendFieldStations(
        atlas: OriginalFieldPlaneAtlas, firstCurveIndex: Int,
        curves: inout [OriginalSurfaceSilhouetteCurve],
        stationCurves: inout [[Int]], stationEnds: inout [[Bool]],
        originalField: OriginalSurfaceSilhouetteField,
        coordinates: SurfaceSilhouetteFieldCoordinateComponents,
        contacts: inout [SurfaceSilhouetteAlgebraicContact],
        stations: inout [SurfaceSilhouettePlaneAtlas.Station],
        usage: inout OriginalQueryExecution
    ) throws {
        for index in atlas.stations.indices {
            let station = atlas.stations[index]
            stationCurves[index].removeAll(keepingCapacity: true); stationEnds[index].removeAll(keepingCapacity: true)
            let endpoint = SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree,
                location: .station(station.originalRoot, completeHalfBranchCount: 0))
            var coordinateAlongU = false, coordinateAlongV = false
            for ordinal in curves.indices {
                guard let pair = curves[ordinal].originalFieldAtlasEndpoints else {
                    throw rationalAlgebraFailure("Original station lost its source curve endpoints.")
                }
                for side in 0..<2 {
                    if try endpoint.hasSameValue(as: side == 0 ? pair.first : pair.last, usage: &usage) {
                        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                        try RationalAlgebraStorage.retain(1, of: Bool.self, usage: &usage)
                        stationCurves[index].append(try rationalAlgebraCount(firstCurveIndex, ordinal))
                        stationEnds[index].append(side == 1)
                        if ordinal < coordinates.curves.count {
                            if curves[ordinal].freeCoordinate == .u { coordinateAlongU = true }
                            else { coordinateAlongV = true }
                        }
                    }
                }
            }
            let contact = try SurfaceSilhouetteAlgebraicContact(field: originalField, originalRoot: station.originalRoot,
                certifiedDomain: atlas.projection.domain, usage: &usage)
            if stationCurves[index].isEmpty {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                contacts.append(contact)
            }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouettePlaneAtlas.Station.self, usage: &usage)
            stations.append(.init(originalContact: contact, incidentCurveIndices: stationCurves[index],
                incidentAtUpperEnd: stationEnds[index], regularGermCount: try rationalAlgebraCount(
                    station.resolution.germs.count, (coordinateAlongU ? 1 : 0) + (coordinateAlongV ? 1 : 0)),
                isolatedGermCount: station.resolution.isolatedGerms.count,
                sourceDepth: max(station.originalRoot.projectionRoot.isolation.depth,
                    station.originalRoot.fiberRoot.isolation.depth)))
        }
    }

    @inline(never)
    private static func appendCoordinateStations(
        atlas: OriginalFieldPlaneAtlas, firstCurveIndex: Int,
        curves: inout [OriginalSurfaceSilhouetteCurve],
        stationCurves: inout [[Int]], stationEnds: inout [[Bool]],
        originalField: OriginalSurfaceSilhouetteField,
        coordinates: SurfaceSilhouetteFieldCoordinateComponents,
        stations: inout [SurfaceSilhouettePlaneAtlas.Station],
        usage: inout OriginalQueryExecution
    ) throws {
        var coordinateStations: [SurfaceSilhouetteFieldAtlasEndpoint] = []
        for root in coordinates.endpoints {
            let endpoint = SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree,
                location: .station(root, completeHalfBranchCount: 0))
            var existing = false
            for station in atlas.stations {
                let other = SurfaceSilhouetteFieldAtlasEndpoint(original: atlas.projection.squareFree,
                    location: .station(station.originalRoot, completeHalfBranchCount: 0))
                if try endpoint.hasSameValue(as: other, usage: &usage) { existing = true; break }
            }
            if !existing {
                for other in coordinateStations {
                    if try endpoint.hasSameValue(as: other, usage: &usage) { existing = true; break }
                }
            }
            if existing { continue }
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteFieldAtlasEndpoint.self, usage: &usage)
            coordinateStations.append(endpoint)
            var indices: [Int] = [], upperEnds: [Bool] = []
            var alongU = false, alongV = false
            for ordinal in curves.indices {
                guard let pair = curves[ordinal].originalFieldAtlasEndpoints else {
                    throw rationalAlgebraFailure("Original coordinate station lost complete curve endpoints.")
                }
                for side in 0..<2 {
                    if try endpoint.hasSameValue(as: side == 0 ? pair.first : pair.last, usage: &usage) {
                        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                        try RationalAlgebraStorage.retain(1, of: Bool.self, usage: &usage)
                        indices.append(try rationalAlgebraCount(firstCurveIndex, ordinal)); upperEnds.append(side == 1)
                        if curves[ordinal].freeCoordinate == .u { alongU = true } else { alongV = true }
                    }
                }
            }
            guard !indices.isEmpty else { throw rationalAlgebraFailure("Original coordinate station has no retained half-branch incidence.") }
            let contact = try SurfaceSilhouetteAlgebraicContact(field: originalField, originalRoot: root,
                certifiedDomain: atlas.projection.domain, usage: &usage)
            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouettePlaneAtlas.Station.self, usage: &usage)
            stations.append(.init(originalContact: contact, incidentCurveIndices: indices,
                incidentAtUpperEnd: upperEnds, regularGermCount: (alongU ? 1 : 0) + (alongV ? 1 : 0), isolatedGermCount: 0,
                sourceDepth: max(root.projectionRoot.isolation.depth, root.fiberRoot.isolation.depth)))
        }
    }

}
