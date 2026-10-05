import Foundation
import Testing
import CADCore
import CADGeometry
import CADTopology
@testable import CADIR

@Suite("Independent original geometry source")
struct IndependentShapeSourceTests {
    private func itemID(_ n: UInt64) -> IndependentShapeItemID { .init(highBits: 1, lowBits: n) }
    private func groupID(_ n: UInt64) -> IndependentShapeGroupID { .init(highBits: 2, lowBits: n) }
    private func instanceID(_ n: UInt64) -> IndependentShapeInstanceID { .init(highBits: 3, lowBits: n) }
    private func representationID(_ n: UInt64) -> IndependentShapeRepresentationID { .init(highBits: 6, lowBits: n) }
    private func definitionID(_ n: UInt64) -> IndependentShapeDefinitionID { .init(highBits: 7, lowBits: n) }
    private func frameID(_ n: UInt64) -> IndependentShapeFrameID { .init(highBits: 10, lowBits: n) }
    private var contextID: IndependentShapeContextID { .init(highBits: 8, lowBits: 1) }
    private var setID: IndependentShapeSetID { .init(highBits: 9, lowBits: 1) }
    private var curveID: CurveID { .init(highBits: 4, lowBits: 1) }
    private var surfaceID: SurfaceID { .init(highBits: 5, lowBits: 1) }

    private func fixture() throws -> IndependentShapeSource {
        let curve = Curve3D.line(Line3D(origin: Point3D(x: 1, y: 2, z: 3), direction: Vector3D(x: 1, y: 0, z: 0)))
        // Independently authored polynomial S(u,v)=(u,2v,u), not an exchange-writer output.
        let surface = Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.origin, Point3D(x: 1, y: 0, z: 1)],
                [Point3D(x: 0, y: 2, z: 0), Point3D(x: 1, y: 2, z: 1)]]))
        let group = IndependentShapeGroup(id: groupID(1), name: "original set", description: "",
            members: [.item(itemID(1)), .item(itemID(2)), .item(itemID(3)), .instance(instanceID(2))])
        let first = IndependentShapeInstance(id: instanceID(1), name: "shear and scale", target: definitionID(1),
            placement: try AffineTransform3D(basisX: Vector3D(x: 1, y: 0, z: 0),
                basisY: Vector3D(x: 0.5, y: 1, z: 0), basisZ: Vector3D(x: 0, y: 0, z: 2),
                translation: Vector3D(x: 10, y: 20, z: 30)))
        let second = IndependentShapeInstance(id: instanceID(2), name: "nested rotation", target: definitionID(2),
            placement: try AffineTransform3D(basisX: Vector3D(x: 0, y: 1, z: 0),
                basisY: Vector3D(x: -1, y: 0, z: 0), basisZ: Vector3D(x: 0, y: 0, z: 1),
                translation: Vector3D(x: -1, y: 0, z: 0)))
        return IndependentShapeSource(geometry: GeometryStore(curves: [curveID: curve], surfaces: [surfaceID: surface]),
            items: [IndependentShapeItem(id: itemID(1), name: "forward", geometry: .curve(curveID, trim: .init(startParameter: -2, endParameter: 2))),
                IndependentShapeItem(id: itemID(2), name: "polynomial surface", geometry: .surface(surfaceID)),
                IndependentShapeItem(id: itemID(3), name: "reverse", geometry: .curve(curveID, trim: .init(startParameter: 2, endParameter: -2)))],
            geometricSets: [.init(id: setID, name: "geometric set", members: [itemID(1), itemID(2), itemID(3)])],
            contexts: [.init(id: contextID, identifier: "original units", type: "3D", units: .millimeters)],
            representations: [.init(id: representationID(1), name: "local geometry", contextID: contextID, members: [.geometricSet(setID), .frame(frameID(1))]),
                .init(id: representationID(2), name: "nested geometry", contextID: contextID, members: [.frame(frameID(1)), .instance(first.id)])],
            frames: [.init(id: frameID(1), name: "basis", placement: try identity())],
            definitions: [.init(id: definitionID(1), representationID: representationID(1), originFrameID: frameID(1)),
                .init(id: definitionID(2), representationID: representationID(2), originFrameID: frameID(1))],
            curveNames: [curveID: ""], groups: [group], instances: [first, second], roots: [.group(group.id)])
    }

    private func identity() throws -> AffineTransform3D {
        try .init(basisX: Vector3D(x: 1, y: 0, z: 0), basisY: Vector3D(x: 0, y: 1, z: 0),
                  basisZ: Vector3D(x: 0, y: 0, z: 1), translation: .zero)
    }

    private func copy(_ source: IndependentShapeSource, geometry: GeometryStore? = nil,
                      items: [IndependentShapeItem]? = nil, groups: [IndependentShapeGroup]? = nil,
                      instances: [IndependentShapeInstance]? = nil, roots: [IndependentShapeReference]? = nil) -> IndependentShapeSource {
        .init(geometry: geometry ?? source.geometry, items: items ?? source.items, geometricSets: source.geometricSets,
              contexts: source.contexts, representations: source.representations, frames: source.frames, definitions: source.definitions,
              curveNames: source.curveNames, surfaceNames: source.surfaceNames,
              groups: groups ?? source.groups, instances: instances ?? source.instances, roots: roots ?? source.roots)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalLawsSharedSelectionsAndLocalPlacementDAGAreRetained() throws {
        let source = try fixture()
        let validator: any IndependentShapeSourceValidating = DefaultIndependentShapeSourceValidator()
        let result = try validator.validate(source, tolerance: .standard, limits: .standard, check: {})
        #expect(result.maximumObservedDepth == 9)
        #expect(source.geometry.curves.count == 1 && source.items.count == 3)
        #expect(source.frames.count == 1 && source.definitions[0].originFrameID == source.definitions[1].originFrameID)
        let curve = try #require(source.geometry.curves[curveID])
        #expect(try curve.point(at: 2, tolerance: .standard) == Point3D(x: 3, y: 2, z: 3))
        let surface = try #require(source.geometry.surfaces[surfaceID])
        let local = try surface.point(u: 0.25, v: 0.5, tolerance: .standard)
        #expect(local == Point3D(x: 0.25, y: 1, z: 0.25))
        let world = source.instances[1].placement.applying(to: source.instances[0].placement.applying(to: local))
        #expect(world == Point3D(x: -22, y: 10.75, z: 30.5))
        let jet = try surface.differentialGeometry(u: 0.25, v: 0.5, tolerance: .standard)
        #expect(abs(jet.normal.x + 1 / sqrt(2.0)) < 1e-12)
        #expect(abs(jet.normal.z - 1 / sqrt(2.0)) < 1e-12)
        #expect(try JSONDecoder().decode(IndependentShapeSource.self, from: JSONEncoder().encode(source)) == source)
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionNamesAndNullableGroupDescriptionsUseOriginalUTF8() throws {
        let source = try fixture(), group = source.groups[0]
        let a = IndependentShapeGroup(id: group.id, name: "é", description: nil, members: group.members)
        let b = IndependentShapeGroup(id: group.id, name: "e\u{301}", description: nil, members: group.members)
        #expect(a != b)
        #expect(a != IndependentShapeGroup(id: a.id, name: a.name, description: "", members: a.members))
        let item = source.items[0]
        #expect(IndependentShapeItem(id: item.id, name: "é", geometry: item.geometry)
            != IndependentShapeItem(id: item.id, name: "e\u{301}", geometry: item.geometry))
        #expect(source.curveNames[curveID] == "")
        #expect(source.surfaceNames[surfaceID] == nil)
        let changedNames = IndependentShapeSource(geometry: source.geometry, items: source.items,
            geometricSets: source.geometricSets, contexts: source.contexts, representations: source.representations,
            frames: source.frames, definitions: source.definitions, groups: source.groups, instances: source.instances, roots: source.roots)
        #expect(changedNames != source)
        #expect(IndependentShapeFrame(id: frameID(1), name: "é", placement: try identity())
            != IndependentShapeFrame(id: frameID(1), name: "e\u{301}", placement: try identity()))
        let first = source.instances[0]
        #expect(IndependentShapeInstance(id: first.id, name: first.name, placementName: "é", target: first.target, placement: first.placement)
            != IndependentShapeInstance(id: first.id, name: first.name, placementName: "e\u{301}", target: first.target, placement: first.placement))
        let encoded = try JSONEncoder().encode(source)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unexpected"] = true
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object)) }
        object.removeValue(forKey: "unexpected")
        var groups = try #require(object["groups"] as? [[String: Any]])
        groups[0].removeValue(forKey: "description"); object["groups"] = groups
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func realMissingTargetsCyclesUnusedGeometryAndSetDuplicatesRefuse() throws {
        let source = try fixture(), validator = DefaultIndependentShapeSourceValidator()
        let missing = copy(source, roots: [.instance(instanceID(999))])
        #expect(throws: IndependentShapeSourceError.missingReference("Instance \(instanceID(999)).")) {
            try validator.validate(missing, tolerance: .standard)
        }
        let cyclicGroup = IndependentShapeGroup(id: groupID(1), members: [.item(itemID(1)), .item(itemID(2)), .item(itemID(3)), .group(groupID(1))])
        let cyclic = copy(source, groups: [cyclicGroup], roots: [.group(groupID(1))])
        #expect(throws: IndependentShapeSourceError.cycle(.group(groupID(1)))) { try validator.validate(cyclic, tolerance: .standard) }
        let duplicate = IndependentShapeGroup(id: groupID(1), members: [.item(itemID(1)), .item(itemID(1))])
        let duplicated = copy(source, groups: [duplicate], roots: [.group(groupID(1))])
        #expect(throws: IndependentShapeSourceError.invalidSource("Set references must be unique and canonically sorted.")) { try validator.validate(duplicated, tolerance: .standard) }
        var extraGeometry = source.geometry
        extraGeometry.curves[CurveID(highBits: 4, lowBits: 2)] = .line(Line3D(origin: .origin, direction: Vector3D(x: 0, y: 1, z: 0)))
        let unused = copy(source, geometry: extraGeometry)
        #expect(throws: IndependentShapeSourceError.invalidSource("Every original geometry law must have a real item selection.")) { try validator.validate(unused, tolerance: .standard) }
    }

    @Test(.timeLimit(.minutes(1)))
    func countWorkTextAndLongestSharedPathAreCallerCeilings() throws {
        let source = try fixture(), validator = DefaultIndependentShapeSourceValidator()
        let usage = try validator.validate(source, tolerance: .standard)
        let exact = IndependentShapeSourceLimits(maximumRecords: usage.consumedRecords,
            maximumTextBytes: usage.consumedTextBytes, maximumDepth: 9, maximumWork: usage.consumedWork)
        #expect(try validator.validate(source, tolerance: .standard, limits: exact) == usage)
        for limits in [IndependentShapeSourceLimits(maximumRecords: usage.consumedRecords - 1),
                       IndependentShapeSourceLimits(maximumTextBytes: usage.consumedTextBytes - 1),
                       IndependentShapeSourceLimits(maximumDepth: 8),
                       IndependentShapeSourceLimits(maximumWork: usage.consumedWork - 1)] {
            do { _ = try validator.validate(source, tolerance: .standard, limits: limits); Issue.record("Caller ceiling was reset.") }
            catch IndependentShapeSourceError.resourceLimitExceeded { }
        }
        // A shorter root to the same local representation must not hide the longest nested path.
        let overlapping = copy(source, roots: [.representation(representationID(1)), .group(groupID(1))])
        do { _ = try validator.validate(overlapping, tolerance: .standard, limits: .init(maximumDepth: 8)); Issue.record("Shared path depth was hidden.") }
        catch IndependentShapeSourceError.resourceLimitExceeded { }
    }

    @Test(.timeLimit(.minutes(1)))
    func strictTrimDomainAndZeroColumnPlacementRefuseWithoutRepair() throws {
        let source = try fixture(), validator = DefaultIndependentShapeSourceValidator()
        let badItem = IndependentShapeItem(id: itemID(2), geometry: .curve(curveID, trim: .init(startParameter: 1, endParameter: 1)))
        let invalid = copy(source, items: [source.items[0], badItem, source.items[2]])
        #expect(throws: IndependentShapeSourceError.invalidSource("Curve trim must be a finite nonzero directed interval.")) { try validator.validate(invalid, tolerance: .standard) }
        let singular = IndependentShapeInstance(id: instanceID(1), target: definitionID(1),
            placement: try AffineTransform3D(basisX: .zero, basisY: Vector3D(x: 0, y: 1, z: 0), basisZ: Vector3D(x: 0, y: 0, z: 1), translation: .zero))
        let singularSource = copy(source, instances: [singular, source.instances[1]])
        #expect(throws: IndependentShapeSourceError.invalidSource("Affine placement has a zero column.")) { try validator.validate(singularSource, tolerance: .standard) }
    }


    @Test(.timeLimit(.minutes(1)))
    func realMappingOriginRequiresActualSameContextMembership() throws {
        let source = try fixture(), validator = DefaultIndependentShapeSourceValidator()
        let foreignContext = IndependentShapeContext(id: .init(highBits: 8, lowBits: 2), identifier: "other", type: "3D", units: .millimeters)
        let representations = [IndependentShapeRepresentation(id: representationID(1), name: "local geometry", contextID: contextID, members: [.geometricSet(setID)]),
            IndependentShapeRepresentation(id: representationID(2), name: "nested geometry", contextID: foreignContext.id, members: [.frame(frameID(1)), .instance(instanceID(1))])]
        let invalid = IndependentShapeSource(geometry: source.geometry, items: source.items, geometricSets: source.geometricSets,
            contexts: [source.contexts[0], foreignContext], representations: representations, frames: source.frames,
            definitions: source.definitions, curveNames: source.curveNames, surfaceNames: source.surfaceNames,
            groups: source.groups, instances: source.instances, roots: source.roots)
        #expect(throws: IndependentShapeSourceError.invalidSource("Mapping origin must have actual representation membership in the mapped context.")) {
            try validator.validate(invalid, tolerance: .standard)
        }
    }


    @Test(.timeLimit(.minutes(1)))
    func canonicalOriginalMapsIgnoreInsertionOrderAndRejectDuplicateKeys() throws {
        let a = CurveID(highBits: 4, lowBits: 11), b = CurveID(highBits: 4, lowBits: 12)
        let law = Curve3D.line(Line3D(origin: .origin, direction: Vector3D(x: 1, y: 0, z: 0)))
        let items = [IndependentShapeItem(id: itemID(1), name: "one", geometry: .curve(a, trim: nil)),
                     IndependentShapeItem(id: itemID(2), name: "two", geometry: .curve(b, trim: nil))]
        let roots: [IndependentShapeReference] = [.item(itemID(1)), .item(itemID(2))]
        var leftGeometry = GeometryStore(), rightGeometry = GeometryStore()
        leftGeometry.curves[a] = law; leftGeometry.curves[b] = law
        rightGeometry.curves[b] = law; rightGeometry.curves[a] = law
        var leftLabels: [CurveID: String] = [:], rightLabels: [CurveID: String] = [:]
        leftLabels[a] = "é"; leftLabels[b] = ""
        rightLabels[b] = ""; rightLabels[a] = "é"
        let left = IndependentShapeSource(geometry: leftGeometry, items: items, curveNames: leftLabels, roots: roots)
        let right = IndependentShapeSource(geometry: rightGeometry, items: items, curveNames: rightLabels, roots: roots)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(left)
        #expect(encoded == (try encoder.encode(right)))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let labels = try #require(object["curveNames"] as? [Any])
        object["curveNames"] = labels + [labels[0], labels[1]]
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object["curveNames"] = labels
        var geometry = try #require(object["geometry"] as? [String: Any])
        let curves = try #require(geometry["curves"] as? [Any])
        geometry["curves"] = curves + [curves[0], curves[1]]; object["geometry"] = geometry
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitIdentityOriginIsExplicitNullableAndRequiresNoSyntheticFrame() throws {
        let source = try fixture()
        let representations = source.representations.map { representation in
            IndependentShapeRepresentation(id: representation.id, name: representation.name, contextID: representation.contextID,
                members: representation.members.filter { if case .frame = $0 { return false }; return true })
        }
        let definitions = source.definitions.map { IndependentShapeDefinition(id: $0.id, representationID: $0.representationID, originFrameID: nil) }
        let implicit = IndependentShapeSource(geometry: source.geometry, items: source.items, geometricSets: source.geometricSets,
            contexts: source.contexts, representations: representations, frames: [], definitions: definitions,
            curveNames: source.curveNames, surfaceNames: source.surfaceNames, groups: source.groups, instances: source.instances, roots: source.roots)
        _ = try DefaultIndependentShapeSourceValidator().validate(implicit, tolerance: .standard)
        let encoded = try JSONEncoder().encode(implicit)
        #expect(try JSONDecoder().decode(IndependentShapeSource.self, from: encoded) == implicit)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var records = try #require(object["definitions"] as? [[String: Any]])
        #expect(records[0]["originFrameID"] is NSNull)
        records[0].removeValue(forKey: "originFrameID"); object["definitions"] = records
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }


    @Test(.timeLimit(.minutes(1)))
    func representationMayPlaceAGenuineSharedGroupWithoutFlattening() throws {
        let source = try fixture()
        let child = IndependentShapeGroup(id: groupID(2), name: "placed group", members: [.item(itemID(2))])
        let representations = [IndependentShapeRepresentation(id: representationID(1), name: "local geometry", contextID: contextID,
            members: [.geometricSet(setID), .frame(frameID(1)), .group(child.id)]), source.representations[1]]
        let retained = IndependentShapeSource(geometry: source.geometry, items: source.items, geometricSets: source.geometricSets,
            contexts: source.contexts, representations: representations, frames: source.frames, definitions: source.definitions,
            curveNames: source.curveNames, surfaceNames: source.surfaceNames, groups: [source.groups[0], child], instances: source.instances, roots: source.roots)
        _ = try DefaultIndependentShapeSourceValidator().validate(retained, tolerance: .standard)
        #expect(retained.representations[0].members.contains(.group(child.id)))
        #expect(retained.groups[1].members == [.item(itemID(2))])
        #expect(try JSONDecoder().decode(IndependentShapeSource.self, from: JSONEncoder().encode(retained)) == retained)
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneOriginalFrameNeedsNoDummyGeometryAndRetainsCallerValidationCeilings() throws {
        let placement = try AffineTransform3D(basisX: .unitY, basisY: -.unitX, basisZ: .unitZ,
            translation: Vector3D(x: 3, y: -2, z: 5))
        let source = IndependentShapeSource(geometry: GeometryStore(), items: [],
            frames: [.init(id: frameID(1), name: "only frame", placement: placement)], roots: [.frame(frameID(1))])
        let document = CADDocument(units: .meters, independentShapes: source)
        let paid = try #require(document.validate(tolerance: .standard, independentShapeLimits: .standard, check: {}))
        #expect(source.geometry.curves.isEmpty && source.geometry.surfaces.isEmpty && source.items.isEmpty)
        #expect(source.frames[0].placement.applying(to: Point3D(x: 2, y: 4, z: 6)) == Point3D(x: -1, y: 0, z: 11))
        #expect(try JSONDecoder().decode(IndependentShapeSource.self, from: JSONEncoder().encode(source)) == source)
        #expect(throws: IndependentShapeSourceError.resourceLimitExceeded("Independent source cumulative work ceiling.")) {
            try document.validate(tolerance: .standard,
                independentShapeLimits: .init(maximumWork: paid.consumedWork - 1), check: {})
        }
        #expect(throws: IndependentShapeSourceError.resourceLimitExceeded("Independent source record ceiling.")) {
            try document.validate(tolerance: .standard,
                independentShapeLimits: .init(maximumRecords: 1), check: {})
        }
        enum Deadline: Error, Equatable { case expired }
        #expect(throws: Deadline.expired) {
            try document.validate(tolerance: .standard, independentShapeLimits: .standard, check: { throw Deadline.expired })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalPositionIdentityAndParameterUnitAreSelfContained() throws {
        let position = try AffineTransform3D(basisX: .unitY, basisY: -.unitX, basisZ: .unitZ,
            translation: .init(x: 0.01, y: 0.02, z: 0.03))
        let frame = IndependentShapeFrame(id: frameID(1), name: "original shared position", placement: position)
        let gain = LengthUnit.millimeter.toInternal(1)
        let transform = try AffineTransform3D(basisX: position.basisX * gain, basisY: position.basisY * gain,
            basisZ: position.basisZ * gain, translation: position.translation)
        let local = Curve3D.analytic(.parabola(.init(vertex: .origin, normal: .unitZ, axis: .unitX, focalLength: 2)))
        let curve = Curve3D.affineImage(try .init(source: local, transform: transform, tolerance: .standard))
        func source(unit: LengthUnit?, originalFrame: IndependentShapeFrame = frame) -> IndependentShapeSource {
            .init(geometry: GeometryStore(curves: [curveID: curve]),
                items: [.init(id: itemID(1), name: "original parabola", geometry: .curve(curveID, trim: .init(startParameter: 0.4, endParameter: -0.25)))],
                frames: [originalFrame], curveNames: [curveID: "original parabola"],
                curvePositionFrames: [curveID: .init(frameID: frame.id, parameterLengthUnit: unit)], roots: [.item(itemID(1))])
        }
        let original = source(unit: .millimeter)
        let validator = DefaultIndependentShapeSourceValidator()
        let usage = try validator.validate(original, tolerance: .standard)
        #expect(usage.maximumObservedDepth == 2)
        // This source's local generator unit is independent of the outer document units.
        try CADDocument(units: .meters, independentShapes: original).validate(tolerance: .standard)
        let point = try curve.point(at: 0.4, tolerance: .standard)
        #expect((point - Point3D(x: 0.0096, y: 0.02002, z: 0.03)).length < 1e-14)
        #expect(try JSONDecoder().decode(IndependentShapeSource.self, from: JSONEncoder().encode(original)) == original)
        #expect(throws: IndependentShapeSourceError.invalidSource("Original curve position association disagrees with its stored parameter law.")) {
            _ = try validator.validate(source(unit: .meter), tolerance: .standard)
        }
        #expect(throws: IndependentShapeSourceError.invalidSource("Original parabola parameter length unit is absent.")) {
            _ = try validator.validate(source(unit: nil), tolerance: .standard)
        }
        let changedPlacement = try AffineTransform3D(basisX: .unitY, basisY: -.unitX, basisZ: .unitZ,
            translation: .init(x: 0.011, y: 0.02, z: 0.03))
        #expect(throws: IndependentShapeSourceError.invalidSource("Original curve position association disagrees with its stored parameter law.")) {
            _ = try validator.validate(source(unit: .millimeter, originalFrame: .init(id: frame.id, name: frame.name, placement: changedPlacement)), tolerance: .standard)
        }
        #expect(throws: IndependentShapeSourceError.resourceLimitExceeded("Independent source cumulative work ceiling.")) {
            _ = try validator.validate(original, tolerance: .standard, limits: .init(maximumWork: usage.consumedWork - 1))
        }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "surfacePositionFrames")
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(IndependentShapeSource.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func realCancellationAndCallerDeadlinePropagate() async throws {
        let source = try fixture()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try DefaultIndependentShapeSourceValidator().validate(source, tolerance: .standard)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled source validation succeeded.") }
        catch is CancellationError { }
        enum Deadline: Error, Equatable { case expired }
        #expect(throws: Deadline.expired) {
            try DefaultIndependentShapeSourceValidator().validate(source, tolerance: .standard, limits: .standard, check: { throw Deadline.expired })
        }
    }
}
