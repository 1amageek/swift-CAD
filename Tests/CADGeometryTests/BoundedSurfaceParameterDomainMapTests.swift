import CADCore
import Testing
@testable import CADGeometry

struct BoundedSurfaceParameterDomainMapTests {
    @Test
    func planarSearchContainsTheOffsetControlHullInBothOrders() throws {
        let tolerance = ModelingTolerance.standard
        let patch = BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: -1, y: -2, z: 0),
            bottomRight: Point3D(x: 2, y: -2, z: 0.2),
            topRight: Point3D(x: 2, y: 3, z: 0.4),
            topLeft: Point3D(x: -1, y: 3, z: 0))
        let finite = Surface3D.procedural(.offset(.init(source: .bSpline(patch), distance: -0.1)))
        let plane = Surface3D.procedural(.offset(.init(
            source: .plane(Plane3D(origin: Point3D(x: 7, y: 8, z: 9), normal: .unitZ)),
            distance: 0.2)))
        try finite.validate(tolerance: tolerance)
        try plane.validate(tolerance: tolerance)
        let frame = try plane.parameterDerivatives(atU: 0, v: 0, tolerance: tolerance)
        for reversed in [false, true] {
            let map = try BoundedSurfaceParameterDomainMap(
                first: reversed ? plane : finite, second: reversed ? finite : plane,
                tolerance: tolerance)
            let u = reversed ? map.firstU : map.secondU
            let v = reversed ? map.firstV : map.secondV
            for x in [-1.1, 2.1] {
                for y in [-2.1, 3.1] {
                    for z in [-0.1, 0.5] {
                        let delta = Point3D(x: x, y: y, z: z) - frame.position
                        let pu = delta.dot(frame.tangentU)
                        let pv = delta.dot(frame.tangentV)
                        #expect(pu >= u.lower && pu <= u.upper)
                        #expect(pv >= v.lower && pv <= v.upper)
                    }
                }
            }
            let finiteU = reversed ? map.secondU : map.firstU
            let finiteV = reversed ? map.secondV : map.firstV
            #expect(finiteU.lower == 0 && finiteU.upper == 1)
            #expect(finiteV.lower == 0 && finiteV.upper == 1)
        }
        #expect(throws: KernelError.self) {
            try BoundedSurfaceParameterDomainMap(first: plane, second: plane, tolerance: tolerance)
        }
    }
}
