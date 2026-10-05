import SwiftCAD

struct TransactionProofFixture: Sendable {
    let document: CADDocument
    let widthID: ParameterID
    let profile: ProfileReference
    let firstExtrude: FeatureID
    let reference: DocumentAttribute

    init() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let widthID = try builder.lengthParameter(named: "width", 1)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(width: .parameter(widthID), height: .length(2, .meter))
        }
        let firstExtrude = try builder.extrude(profile, distance: .length(3, .meter))
        let original = try builder.build(name: "Original transaction source")
        let reference = DocumentAttribute(name: "selected", owner: .init(documentID: original.id),
            value: .reference(.init(documentID: original.id, target: .feature(firstExtrude))))
        var source = try DocumentEditor().apply(.setDocumentAttribute(reference), to: original, tolerance: .standard)
        let curveID = CurveID()
        let item = IndependentShapeItem(name: "Original independent line",
            geometry: .curve(curveID, trim: CurveTrim(startParameter: 0, endParameter: 1)))
        let independent = IndependentShapeSource(geometry: GeometryStore(curves: [curveID:
            .line(Line3D(origin: .origin, direction: Vector3D(x: 1, y: 0, z: 0)))]),
            items: [item], roots: [.item(item.id)])
        _ = try DefaultIndependentShapeSourceValidator().validate(independent, tolerance: .standard)
        source.independentShapes = independent
        try source.validate(tolerance: .standard)
        document = source
        self.widthID = widthID
        self.profile = profile
        self.firstExtrude = firstExtrude
        self.reference = reference
    }
}
