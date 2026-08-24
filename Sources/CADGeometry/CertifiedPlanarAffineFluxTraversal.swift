import CADCore

package struct CertifiedPlanarAffineFluxTraversal: Sendable {
    package struct HomogeneousControl: Sendable {
        package let x: ScalarInterval
        package let y: ScalarInterval
        package let weight: ScalarInterval

        package init(
            x: ScalarInterval,
            y: ScalarInterval,
            weight: ScalarInterval
        ) {
            self.x = x
            self.y = y
            self.weight = weight
        }
    }

    package struct Patch: Sendable {
        package let controls: [HomogeneousControl]

        package init(controls: [HomogeneousControl]) {
            self.controls = controls
        }
    }

    package let patches: [Patch]
    package let fluxScale: ScalarInterval

    package init(patches: [Patch], fluxScale: ScalarInterval) {
        self.patches = patches
        self.fluxScale = fluxScale
    }
}
