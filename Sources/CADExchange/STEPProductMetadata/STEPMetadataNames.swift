import CADIR

/// Standard entity family correspondence, independent of authored names.
enum STEPMetadataNames {
    static let namespace = "urn:swiftcad:product-metadata"
    static let tolerances: [ProductGeometricTolerance.Kind: String] = [
        .angularity: "ANGULARITY_TOLERANCE", .circularRunout: "CIRCULAR_RUNOUT_TOLERANCE",
        .coaxiality: "COAXIALITY_TOLERANCE", .concentricity: "CONCENTRICITY_TOLERANCE",
        .cylindricity: "CYLINDRICITY_TOLERANCE", .flatness: "FLATNESS_TOLERANCE",
        .lineProfile: "LINE_PROFILE_TOLERANCE", .parallelism: "PARALLELISM_TOLERANCE",
        .perpendicularity: "PERPENDICULARITY_TOLERANCE", .position: "POSITION_TOLERANCE",
        .roundness: "ROUNDNESS_TOLERANCE", .straightness: "STRAIGHTNESS_TOLERANCE",
        .surfaceProfile: "SURFACE_PROFILE_TOLERANCE", .symmetry: "SYMMETRY_TOLERANCE",
        .totalRunout: "TOTAL_RUNOUT_TOLERANCE"
    ]
    static let modifiers: [ProductGeometricTolerance.Modifier: String] = [
        .maximumMaterialCondition: "MAXIMUM_MATERIAL_REQUIREMENT",
        .leastMaterialCondition: "LEAST_MATERIAL_REQUIREMENT",
        .commonZone: "COMMON_ZONE", .freeState: "FREE_STATE", .tangentPlane: "TANGENT_PLANE"
    ]
    static let simpleNames = ["DATUM", "DATUM_FEATURE", "DATUM_REFERENCE", "SHAPE_ASPECT_RELATIONSHIP",
        "DIMENSIONAL_SIZE", "ANGULAR_SIZE", "DIMENSIONAL_LOCATION", "ANGULAR_LOCATION",
        "DIMENSIONAL_CHARACTERISTIC_REPRESENTATION", "SHAPE_DIMENSION_REPRESENTATION",
        "PLUS_MINUS_TOLERANCE", "TOLERANCE_VALUE", "AREA_MEASURE_WITH_UNIT",
        "CAMERA_MODEL_D3", "CAMERA_MODEL_D3_MULTI_CLIPPING", "CAMERA_MODEL_D3_MULTI_CLIPPING_UNION", "CAMERA_MODEL_D3_MULTI_CLIPPING_INTERSECTION", "VIEW_VOLUME", "PLANAR_BOX",
        "TEXT_LITERAL", "DRAUGHTING_PRE_DEFINED_TEXT_FONT", "ANNOTATION_TEXT_OCCURRENCE",
        "ANNOTATION_CURVE_OCCURRENCE", "DRAUGHTING_CALLOUT", "DRAUGHTING_MODEL_ITEM_ASSOCIATION",
        "POLYLINE", "REPRESENTATION_ITEM_RELATIONSHIP"] + Array(tolerances.values)
}
