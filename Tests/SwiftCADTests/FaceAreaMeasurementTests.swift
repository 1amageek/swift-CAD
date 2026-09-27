import Foundation
import Testing
@testable import SwiftCAD

/// Face area and area centroid of planar, cylindrical, conical, spherical and toroidal faces,
/// integrated over their pcurves.
@Suite("Face area measurement")
struct FaceAreaMeasurementTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: millimeters(x), y: millimeters(y))
    }

    private func evaluate(_ builder: DocumentBuilder) throws -> BRepModel {
        try CADPipeline(tolerance: .standard).evaluate(builder.build()).brep
    }

    /// The mean of the face's boundary vertices.
    private func vertexMean(_ faceID: FaceID, in model: BRepModel) throws -> Point3D {
        let face = try #require(model.faces[faceID])
        var ids: Set<VertexID> = []
        for loopID in face.loops {
            for coedge in model.loops[loopID]?.coedges ?? [] {
                guard let edge = model.edges[coedge.edgeID] else { continue }
                ids.formUnion([edge.startVertexID, edge.endVertexID])
            }
        }
        let points = ids.compactMap { model.vertices[$0]?.point }
        let sum = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) }
        return .origin + sum * (1 / Double(points.count))
    }

    @Test(.timeLimit(.minutes(1)))
    func boxFacesMeasureTheirRectangles() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.box(width: millimeters(40), depth: millimeters(20), height: millimeters(10))
        let model = try evaluate(builder)
        var areas: [Double] = []
        for faceID in model.faces.keys {
            let measurement = try model.faceAreaMeasurement(of: faceID, tolerance: .standard)
            areas.append(measurement.area)
            #expect((measurement.centroid - (try vertexMean(faceID, in: model))).length < 1e-12)
        }
        let expected = [0.0008, 0.0008, 0.0004, 0.0004, 0.0002, 0.0002]
        #expect(zip(areas.sorted(), expected.sorted()).allSatisfy { abs($0 - $1) < 1e-15 })
    }

    @Test(.timeLimit(.minutes(1)))
    func anLShapedFaceCentersOnItsAreaNotItsCorners() throws {
        // An L: a 30 × 10 bar along x with a 10 × 20 leg rising from its left end.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let corners = [(0.0, 0.0), (30.0, 0.0), (30.0, 10.0), (10.0, 10.0), (10.0, 30.0), (0.0, 30.0)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for index in corners.indices {
                let next = corners[(index + 1) % corners.count]
                _ = sketch.line(from: point(corners[index].0, corners[index].1), to: point(next.0, next.1))
            }
        }
        _ = try builder.extrude(profile, distance: millimeters(5))
        let model = try evaluate(builder)
        let bottom = try #require(model.faces.keys.first { faceID in
            guard let points = try? vertexMean(faceID, in: model) else { return false }
            return abs(points.z) < 1e-12
        })
        let measurement = try model.faceAreaMeasurement(of: bottom, tolerance: .standard)
        // Bar 300 mm² at (15, 5), leg 200 mm² at (5, 20): centroid (11, 11) mm.
        #expect(abs(measurement.area - 0.0005) < 1e-15)
        #expect(abs(measurement.centroid.x - 0.011) < 1e-12)
        #expect(abs(measurement.centroid.y - 0.011) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderMeasuresItsSideOnTheAxisAndItsCapsAtTheirCenters() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.cylinder(radius: millimeters(10), height: millimeters(20))
        let model = try evaluate(builder)
        var sideArea = 0.0
        var sideMoment = Vector3D.zero
        var caps: [FaceAreaMeasurement] = []
        for (faceID, face) in model.faces {
            let measurement = try model.faceAreaMeasurement(of: faceID, tolerance: .standard)
            if case .cylinder = model.geometry.surfaces[face.surfaceID] {
                sideArea += measurement.area
                sideMoment = sideMoment + (measurement.centroid - .origin) * measurement.area
            } else {
                caps.append(measurement)
            }
        }
        #expect(abs(sideArea - 2 * .pi * 0.010 * 0.020) < 1e-14)
        let sideCentroid = .origin + sideMoment * (1 / sideArea)
        #expect(caps.count == 2)
        for cap in caps {
            #expect(abs(cap.area - .pi * 0.010 * 0.010) < 1e-14)
        }
        // The side's centroid lies on the axis halfway between the caps.
        let axisMiddle = Point3D(
            x: (caps[0].centroid.x + caps[1].centroid.x) / 2,
            y: (caps[0].centroid.y + caps[1].centroid.y) / 2,
            z: (caps[0].centroid.z + caps[1].centroid.z) / 2
        )
        #expect((sideCentroid - axisMiddle).length < 1e-12)
        #expect(abs((caps[0].centroid - caps[1].centroid).length - 0.020) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHalfCylinderCentersOffItsAxis() throws {
        // A half disk of radius 10 mm over y ≥ 0, extruded 20 mm: its curved face is half a
        // cylinder, whose area centroid lies 2r/π from the axis.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            _ = sketch.arc(
                center: point(0, 0), radius: millimeters(10),
                startAngle: .constant(.angle(0, unit: .radian)), endAngle: .constant(.angle(.pi, unit: .radian))
            )
            _ = sketch.line(from: point(-10, 0), to: point(10, 0))
        }
        _ = try builder.extrude(profile, distance: millimeters(20))
        let model = try evaluate(builder)
        // The kernel may split the curved side into several cylindrical faces; each is measured
        // on its own (a quarter centers at 2r/π along both of its bounding radii) and together
        // they are the half cylinder.
        var area = 0.0
        var moment = Vector3D.zero
        for (faceID, face) in model.faces {
            guard case .cylinder = model.geometry.surfaces[face.surfaceID] else { continue }
            let measurement = try model.faceAreaMeasurement(of: faceID, tolerance: .standard)
            area += measurement.area
            moment = moment + (measurement.centroid - .origin) * measurement.area
        }
        let centroid = Point3D.origin + moment * (1 / area)
        #expect(abs(area - .pi * 0.010 * 0.020) < 1e-14)
        #expect(abs(centroid.x) < 1e-12)
        #expect(abs(centroid.y - 2 * 0.010 / .pi) < 1e-12)
        #expect(abs(centroid.z - 0.010) < 1e-12)
    }

    /// Area-weighted centroid and total area of the faces `include` accepts.
    private func combined(
        _ model: BRepModel,
        where include: (Surface3D) -> Bool
    ) throws -> (area: Double, centroid: Point3D, faces: [FaceAreaMeasurement]) {
        var area = 0.0
        var moment = Vector3D.zero
        var faces: [FaceAreaMeasurement] = []
        for (faceID, face) in model.faces {
            guard let surface = model.geometry.surfaces[face.surfaceID], include(surface) else { continue }
            let measurement = try model.faceAreaMeasurement(of: faceID, tolerance: .standard)
            faces.append(measurement)
            area += measurement.area
            moment = moment + (measurement.centroid - .origin) * measurement.area
        }
        return (area, .origin + moment * (1 / area), faces)
    }

    @Test(.timeLimit(.minutes(1)))
    func eachSphereOctantMeasuresAnEighthCenteredHalfARadiusAlongEachAxis() throws {
        // An octant bounded by three great-circle quarters: area πR²/2, and its area centroid lies
        // R/2 from the center along each of the three axes it spans.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.sphere(radius: millimeters(10))
        let model = try evaluate(builder)
        let radius = 0.010
        let sphere = try combined(model) { if case .analytic(.sphere) = $0 { return true }; return false }
        #expect(sphere.faces.count == 8)
        for face in sphere.faces {
            #expect(abs(face.area - .pi * radius * radius / 2) < 1e-16)
            for component in [face.centroid.x, face.centroid.y, face.centroid.z] {
                #expect(abs(abs(component) - radius / 2) < 1e-15)
            }
        }
        #expect(abs(sphere.area - 4 * .pi * radius * radius) < 1e-15)
        #expect((sphere.centroid - .origin).length < 1e-15)
    }

    @Test(.timeLimit(.minutes(1)))
    func aConesSideCentersAThirdOfItsHeightAboveItsBase() throws {
        // A right cone's lateral surface has area πrl and its area centroid on the axis a third of
        // the height above the base.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.cone(baseRadius: millimeters(10), height: millimeters(20))
        let model = try evaluate(builder)
        let (radius, height) = (0.010, 0.020)
        let side = try combined(model) { if case .analytic(.cone) = $0 { return true }; return false }
        let base = try combined(model) { if case .analytic(.cone) = $0 { return false }; return true }
        #expect(abs(side.area - .pi * radius * (radius * radius + height * height).squareRoot()) < 1e-15)
        #expect(abs(base.area - .pi * radius * radius) < 1e-15)
        #expect(abs((side.centroid - base.centroid).length - height / 3) < 1e-14)
        let apex = try #require(model.vertices.values.map(\.point).max {
            ($0 - base.centroid).length < ($1 - base.centroid).length
        })
        #expect(abs((apex - side.centroid).length - 2 * height / 3) < 1e-14)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTorusMeasuresFourPiSquaredRrCenteredOnItsCenter() throws {
        // Sixteen quarter-by-quarter faces: those on the outer half measure r·π/2·(Rπ/2 + r), those
        // on the inner half r·π/2·(Rπ/2 − r); together 4π²Rr, centered on the torus center.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        _ = try builder.torus(majorRadius: millimeters(20), minorRadius: millimeters(5))
        let model = try evaluate(builder)
        let (major, minor) = (0.020, 0.005)
        let torus = try combined(model) { if case .analytic(.torus) = $0 { return true }; return false }
        #expect(torus.faces.count == 16)
        let outer = minor * .pi / 2 * (major * .pi / 2 + minor)
        let inner = minor * .pi / 2 * (major * .pi / 2 - minor)
        #expect(torus.faces.filter { abs($0.area - outer) < 1e-16 }.count == 8)
        #expect(torus.faces.filter { abs($0.area - inner) < 1e-16 }.count == 8)
        #expect(abs(torus.area - 4 * .pi * .pi * major * minor) < 1e-15)
        #expect((torus.centroid - .origin).length < 1e-15)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRoundedBoxMeasuresItsFlatsQuarterCylindersAndSphericalCorners() throws {
        // Every edge of a 40 × 20 × 10 mm box rounded at 2 mm: six inset flats, twelve quarter
        // cylinders and eight sphere octants, whose areas sum to
        // 2 Σ aᵢaⱼ + 2πr Σ aᵢ + 4πr² over the inset sides aᵢ, centered on the box center.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let box = try builder.box(width: millimeters(40), depth: millimeters(20), height: millimeters(10))
        try builder.append(id: FeatureID(), name: nil, operation: .fillet(FilletFeature(
            target: FilletTargetReference(featureID: box), edges: [], radius: millimeters(2), allEdges: true
        )))
        let model = try evaluate(builder)
        let radius = 0.002
        let sides = [0.040, 0.020, 0.010].map { $0 - 2 * radius }
        let all = try combined(model) { _ in true }
        #expect(all.faces.count == 26)
        let expected = 2 * (sides[0] * sides[1] + sides[1] * sides[2] + sides[2] * sides[0])
            + 2 * .pi * radius * sides.reduce(0, +) + 4 * .pi * radius * radius
        #expect(abs(all.area - expected) < 1e-15)
        let corners = try combined(model) { if case .analytic(.sphere) = $0 { return true }; return false }
        #expect(corners.faces.count == 8)
        #expect(abs(corners.area - 4 * .pi * radius * radius) < 1e-16)
        let points = model.vertices.values.map(\.point)
        let center = Point3D(
            x: (points.map(\.x).max()! + points.map(\.x).min()!) / 2,
            y: (points.map(\.y).max()! + points.map(\.y).min()!) / 2,
            z: (points.map(\.z).max()! + points.map(\.z).min()!) / 2
        )
        #expect((all.centroid - center).length < 1e-14)
    }

    @Test(.timeLimit(.minutes(1)))
    func aBSplineFaceIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 0.02].map { y in [0.0, 0.04].map { Point3D(x: $0, y: y, z: 0) } }
        ))
        let model = try evaluate(builder)
        let faceID = try #require(model.faces.keys.first)
        #expect(throws: KernelError.self) {
            _ = try model.faceAreaMeasurement(of: faceID, tolerance: .standard)
        }
    }
}
