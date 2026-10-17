//
//  WaymarkPrior.swift
//  CaneKitLogic
//
//  Waymark L1: the offline "sidewalk memory" bundle, `waymark.priors.v1` (WAYMARK_PLAN v1.1 §5.2).
//  Each label is one Project Sidewalk label cluster (UW Makeability Lab, CC0), normalized by the
//  Windows pipeline (P2), shipped in the app as `Resources/waymark_priors.json`.
//
//  Decoding is strict on purpose. Any rule broken anywhere rejects the whole bundle, and the app's
//  `WaymarkEngine` then stays inert and logs `waymark_load {error}`. A half-trusted map is worse
//  than none for a walker who cannot see it, and a strict decoder makes pipeline drift show up on
//  the first launch instead of as a wrong warning on a walk.
//  The one deliberate leniency: an unknown label type decodes to `.other`, so a new Project
//  Sidewalk type never bricks the feature (plan 5.2, D-15).
//
//  Portability (plan 1.4): Foundation only; the only base-repo type used is `Coordinate`.
//  Pure: no clock, no I/O. `Sendable` value types.
//  Tests: `WaymarkPriorTests.swift` (plan §5.2 example decoded exactly, each rejection, defaults).
//

import Foundation

/// The label type, an open enum over the plan's seven values. Raw values are the bundle's
/// `type` strings. `init(from:)` maps any other string to `.other`.
public enum WaymarkLabelType: String, Sendable, Codable, CaseIterable, Hashable {
    /// A curb ramp is present (informational; spoken only at the Detailed cue level).
    case curbRamp = "curb_ramp"
    /// A crossing point that should have a curb ramp has none.
    case missingCurbRamp = "missing_curb_ramp"
    /// Something in the path: pole, sign, bin, vegetation, parked scooter.
    case obstacle
    /// Cracks, uneven or broken pavement.
    case surfaceProblem = "surface_problem"
    /// The street has no sidewalk here.
    case noSidewalk = "no_sidewalk"
    /// A marked crosswalk (D-15: kept for route ranking and the map, never spoken).
    case crosswalk
    /// Anything else, including Project Sidewalk's `Signal`, `Other` and types not seen yet.
    case other

    /// Decodes a known raw value, or `.other` for any other string. Throws only when the value is
    /// not a string at all.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WaymarkLabelType(rawValue: raw) ?? .other
    }
}

/// One prior label: a Project Sidewalk cluster as the pipeline normalized it (plan 5.2 field rules).
public struct WaymarkPrior: Sendable, Equatable, Codable, Identifiable {
    /// `"ps:" + source_cluster_id`; the id evidence lines refer to.
    public let id: String
    /// What the label says is there.
    public let type: WaymarkLabelType
    /// WGS84 latitude, degrees.
    public let lat: Double
    /// WGS84 longitude, degrees (the bundle says `lng`; base-repo route files say `lon`).
    public let lng: Double
    /// Project Sidewalk's median severity, a number in [1, 3] (D-19: no rounding), or nil.
    public let severity: Double?
    /// Sorted tag keys (`tag_counts` keys); empty when none.
    public let tags: [String]
    /// Validations agreeing / disagreeing / unsure. Only agree and disagree feed the belief.
    public let nAgree: Int, nDisagree: Int, nUnsure: Int
    /// Raw labels merged into this cluster.
    public let clusterSize: Int
    /// Project Sidewalk street edge, intersection and OpenStreetMap way, when known.
    public let streetEdgeID: Int?, intersectionID: Int?, osmWayID: Int?
    /// `"YYYY-MM"` of the street imagery and of the labelling, when known.
    public let imageryDate: String?, labelDate: String?
    /// The cluster id; equals the number in `id`.
    public let sourceClusterID: Int

    /// Memberwise initializer (tests, synthetic fixtures).
    public init(id: String, type: WaymarkLabelType, lat: Double, lng: Double, severity: Double?,
                tags: [String], nAgree: Int, nDisagree: Int, nUnsure: Int, clusterSize: Int,
                streetEdgeID: Int?, intersectionID: Int?, osmWayID: Int?,
                imageryDate: String?, labelDate: String?, sourceClusterID: Int) {
        self.id = id; self.type = type; self.lat = lat; self.lng = lng; self.severity = severity
        self.tags = tags; self.nAgree = nAgree; self.nDisagree = nDisagree; self.nUnsure = nUnsure
        self.clusterSize = clusterSize; self.streetEdgeID = streetEdgeID
        self.intersectionID = intersectionID; self.osmWayID = osmWayID
        self.imageryDate = imageryDate; self.labelDate = labelDate; self.sourceClusterID = sourceClusterID
    }

    /// `lat` / `lng` as a base-repo `Coordinate` for `GeoMath`.
    public var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lng) }

    /// The bundle's snake_case keys (the contract).
    enum CodingKeys: String, CodingKey {
        case id, type, lat, lng, severity, tags
        case nAgree = "n_agree", nDisagree = "n_disagree", nUnsure = "n_unsure"
        case clusterSize = "cluster_size"
        case streetEdgeID = "street_edge_id", intersectionID = "intersection_id", osmWayID = "osm_way_id"
        case imageryDate = "imagery_date", labelDate = "label_date"
        case sourceClusterID = "source_cluster_id"
    }

    /// Decodes one label. Every key of the bundle schema (`waymark/contracts/priors_v1.schema.json`)
    /// must be present; `severity`, the three ids and the two dates may be `null`. A missing key is
    /// a malformed bundle (golden case `missing_required_field`). Range and format rules are
    /// checked by `WaymarkPriorSet.decode`, which knows the label's id for the error.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(WaymarkLabelType.self, forKey: .type)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        severity = try c.decode(Double?.self, forKey: .severity)
        tags = try c.decode([String].self, forKey: .tags)
        nAgree = try c.decode(Int.self, forKey: .nAgree)
        nDisagree = try c.decode(Int.self, forKey: .nDisagree)
        nUnsure = try c.decode(Int.self, forKey: .nUnsure)
        clusterSize = try c.decode(Int.self, forKey: .clusterSize)
        streetEdgeID = try c.decode(Int?.self, forKey: .streetEdgeID)
        intersectionID = try c.decode(Int?.self, forKey: .intersectionID)
        osmWayID = try c.decode(Int?.self, forKey: .osmWayID)
        imageryDate = try c.decode(String?.self, forKey: .imageryDate)
        labelDate = try c.decode(String?.self, forKey: .labelDate)
        sourceClusterID = try c.decode(Int.self, forKey: .sourceClusterID)
    }
}

/// Why a bundle was refused. Each case names the first label that broke a rule.
public enum WaymarkPriorError: Error, Equatable, Sendable {
    /// More than `WaymarkPriorSet.maxBytes`.
    case tooLarge(bytes: Int)
    /// `schema` is not `waymark.priors.v1`.
    case wrongSchema(String)
    /// Not JSON, or a required key missing or mistyped (the decoder's message).
    case malformed(String)
    /// More than `WaymarkPriorSet.maxLabels`.
    case tooManyLabels(Int)
    /// `lat` outside [-90, 90] or `lng` outside [-180, 180], or not finite.
    case badCoordinate(id: String)
    /// `severity` outside [1, 3].
    case badSeverity(id: String)
    /// A negative count, or `cluster_size` below 1.
    case badCount(id: String)
    /// `imagery_date` / `label_date` not `"YYYY-MM"`.
    case badDate(id: String)
    /// `bbox_lnglat` not four in-range numbers with minimum before maximum.
    case badBBox
    /// `id` is not `"ps:" + source_cluster_id`.
    case idMismatch(id: String)
    /// Two labels share an id.
    case duplicateID(String)
}

/// A decoded, validated `waymark.priors.v1` bundle.
public struct WaymarkPriorSet: Sendable, Equatable {
    /// The only schema id this decoder accepts.
    public static let schemaID = "waymark.priors.v1"
    /// Size budget (plan D-06).
    public static let maxLabels = 20_000
    /// Size budget in bytes (plan D-06: 3 MB).
    public static let maxBytes = 3 * 1024 * 1024

    /// `generated_at` as written by the pipeline (ISO 8601, UTC).
    public let generatedAt: String
    /// `source.name` ("Project Sidewalk", or a SYNTHETIC test source).
    public let sourceName: String
    /// `[minLng, minLat, maxLng, maxLat]`.
    public let bboxLngLat: [Double]
    /// Labels in file order (the pipeline sorts them by id).
    public let labels: [WaymarkPrior]

    /// Decodes and validates a bundle.
    /// - Parameters:
    ///   - data: the file contents.
    ///   - byteLimit: the size budget; always `maxBytes` in the app. Tests raise it to reach the
    ///     label-count rule, which a real 20,001-label file would hit only after the byte budget.
    /// - Returns: the bundle.
    /// - Throws: `WaymarkPriorError` naming the first rule broken.
    public static func decode(_ data: Data, byteLimit: Int = maxBytes) throws -> WaymarkPriorSet {
        guard data.count <= byteLimit else { throw WaymarkPriorError.tooLarge(bytes: data.count) }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw WaymarkPriorError.malformed(String(describing: error))
        }
        guard raw.schema == schemaID else { throw WaymarkPriorError.wrongSchema(raw.schema) }
        guard isValidBBox(raw.bboxLngLat) else { throw WaymarkPriorError.badBBox }
        guard raw.labels.count <= maxLabels else { throw WaymarkPriorError.tooManyLabels(raw.labels.count) }
        var seen = Set<String>()
        seen.reserveCapacity(raw.labels.count)
        for p in raw.labels {
            guard p.id == "ps:\(p.sourceClusterID)" else { throw WaymarkPriorError.idMismatch(id: p.id) }
            guard seen.insert(p.id).inserted else { throw WaymarkPriorError.duplicateID(p.id) }
            guard p.lat.isFinite, p.lng.isFinite, (-90...90).contains(p.lat), (-180...180).contains(p.lng)
            else { throw WaymarkPriorError.badCoordinate(id: p.id) }
            if let s = p.severity, !(s.isFinite && (1...3).contains(s)) {
                throw WaymarkPriorError.badSeverity(id: p.id)
            }
            guard p.nAgree >= 0, p.nDisagree >= 0, p.nUnsure >= 0, p.clusterSize >= 1
            else { throw WaymarkPriorError.badCount(id: p.id) }
            for d in [p.imageryDate, p.labelDate] {
                if let d, !isYearMonth(d) { throw WaymarkPriorError.badDate(id: p.id) }
            }
        }
        return WaymarkPriorSet(generatedAt: raw.generatedAt, sourceName: raw.source.name,
                               bboxLngLat: raw.bboxLngLat, labels: raw.labels)
    }

    /// Four finite numbers, longitude then latitude, each in range, minimum ≤ maximum.
    static func isValidBBox(_ b: [Double]) -> Bool {
        guard b.count == 4, b.allSatisfy(\.isFinite) else { return false }
        let (minLng, minLat, maxLng, maxLat) = (b[0], b[1], b[2], b[3])
        let lngOK = (-180...180).contains(minLng) && (-180...180).contains(maxLng)
        let latOK = (-90...90).contains(minLat) && (-90...90).contains(maxLat)
        return lngOK && latOK && minLng <= maxLng && minLat <= maxLat
    }

    /// `"YYYY-MM"` with a month 01 to 12.
    static func isYearMonth(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 7, u[4] == UInt8(ascii: "-") else { return false }
        let digits = u[0..<4] + u[5..<7]
        guard digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else { return false }
        let month = Int(u[5] - UInt8(ascii: "0")) * 10 + Int(u[6] - UInt8(ascii: "0"))
        return (1...12).contains(month)
    }

    /// The file's top level, before validation.
    private struct Raw: Decodable {
        let schema: String
        let generatedAt: String
        let source: Source
        let bboxLngLat: [Double]
        let labels: [WaymarkPrior]
        enum CodingKeys: String, CodingKey {
            case schema, source, labels
            case generatedAt = "generated_at"
            case bboxLngLat = "bbox_lnglat"
        }
    }

    /// `source`; only `name` is required (license, base URL and geometry credit are for humans).
    private struct Source: Decodable { let name: String }
}
