//
//  WaymarkMapView.swift
//  CaneKit
//
//  Waymark judge demo, task 2: the map of reports (design doc §8.2 `WaymarkMapView`). Apple MapKit
//  only. Draws the bundled Project Sidewalk labels along the active route (or the demo route before
//  a walk; around the walker when there is no route) (`WaymarkMapSelection`), each pin coloured AND
//  shaped by its confidence band (`WaymarkConfidenceBand`: filled circle = likely (amber), filled
//  diamond = uncertain (lemon), hollow ring = doubtful (sky blue) — three steps of the colour-blind-
//  safe lane ladder, never the rose of STOP), with a type glyph.
//  Types never spoken (crosswalk, other) are drawn dimmed (plan 5.2).
//  Tapping a pin shows its type, confidence, street-imagery date and Project Sidewalk votes.
//  Task 3 (learning made visible): a pin with field evidence stored on this phone
//  (`MapPin.checked`, survives a relaunch) carries a small dot badge (text colour, ringed in the
//  surface colour, so it reads in light and dark mode; a shape cue, not colour alone) and its
//  VoiceOver label ends ", checked on this phone"; its details add this launch's learning line
//  ("Not there · 50 % → 43 % · spotter") or "Checked on this phone before", with an icon by
//  outcome (`WaymarkGlance.learningSymbol`: check seal, xmark seal, question mark, clock).
//
//  These are Waymark reports, not the hazards the cane logged on a walk (that count lives on the
//  Details page's Hazards card as "N logged this walk"); the header says so.
//  The pin and detail words come from `WaymarkGlance` (CaneKitLogic, tested); the panel's two
//  explanatory sentences are literals. Reads `AppModel` only. Pins reload on appear, after each
//  recorded check, when a route starts or ends, and every 5 s (the walker moves). The camera opens
//  on the route and pins (not `.automatic`, which also framed a walker far from Seattle).
//  Owner / caller: `WaymarkCard` ("Map of reports"); `WaymarkAheadCard` reuses `WaymarkPinMark`.
//

import SwiftUI
import MapKit
import CaneKitLogic

/// The map of reports, in a sheet with Done.
struct WaymarkMapView: View {
    /// Reads `waymark`, `nav.route`, `location.fix`.
    @Environment(AppModel.self) private var model
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    /// Camera: fits the route and pins first.
    @State private var position: MapCameraPosition = .automatic
    /// The tapped pin's label id.
    @State private var selectedID: String?
    /// The drawn pins (see the header for when they reload).
    @State private var pins: [WaymarkEngine.MapPin] = []
    /// The camera is placed once, on the first reload.
    @State private var framed = false
    /// VoiceOver moves to the details when a pin is tapped (review 7).
    @AccessibilityFocusState private var detailsFocused: Bool

    /// Map with the route line, the walker and the pins; legend on top; details or counts below.
    var body: some View {
        NavigationStack {
            Map(position: $position) {
                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates.map(\.clLocation))
                        .stroke(CKColor.textPrimary.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                UserAnnotation()
                ForEach(pins) { pin in
                    Annotation(WaymarkGlance.reported(pin.prior.type), coordinate: pin.prior.coordinate.clLocation,
                               anchor: .center) {
                        Button {
                            selectedID = pin.id
                            detailsFocused = true
                        } label: {
                            WaymarkPinMark(band: WaymarkConfidenceBand(p: pin.p), type: pin.prior.type,
                                           selected: selectedID == pin.id, checked: pin.checked)
                                .frame(width: 44, height: 44)      // review 2: a 44 pt target
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WaymarkGlance.pinSpoken(type: pin.prior.type, p: pin.p, checked: pin.checked))
                        .accessibilityHint("Shows this report's details")
                        .accessibilityIdentifier("waymark-pin-\(pin.id)")
                        .accessibilityAddTraits(selectedID == pin.id ? .isSelected : [])
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .safeAreaInset(edge: .top, spacing: 0) { legend }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            .navigationTitle("Map of reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: model.waymark.evidenceCount) { _, _ in reload() }
            .onChange(of: model.nav.isNavigating) { _, _ in reload() }
            .task {                                       // review 3: the walker moves
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    reload()
                }
            }
        }
    }

    // MARK: - Data

    /// The active route while walking, else the demo route Start route would run.
    private var routeCoordinates: [Coordinate] {
        if model.nav.isNavigating, let r = model.nav.route { return r.waypoints.map(\.coordinate) }
        return AppModel.demoRoute?.waypoints.map(\.coordinate) ?? []
    }

    /// Recomputes the pins (selection is pure and fast: a few hundred index queries at most) and, the
    /// first time, frames the route and pins with a 20 % margin.
    private func reload() {
        let route = routeCoordinates
        pins = model.waymark.mapPins(route: route, walker: model.location.fix?.coordinate)
        guard !framed else { return }
        let points = (route + pins.map(\.prior.coordinate)).map { MKMapPoint($0.clLocation) }
        guard let first = points.first else { return }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for p in points.dropFirst() { rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0))) }
        let pad = max(rect.size.width, rect.size.height, 400) * 0.2
        position = .rect(rect.insetBy(dx: -pad, dy: -pad))
        framed = true
    }

    /// The selected pin, if it is still drawn.
    private var selected: WaymarkEngine.MapPin? {
        guard let id = selectedID else { return nil }
        return pins.first { $0.id == id }
    }

    // MARK: - Panels

    /// The three bands as shape + word + range; colour is never the only cue.
    private var legend: some View {
        HStack(spacing: CKSpacing.md) {
            ForEach(WaymarkConfidenceBand.allCases, id: \.self) { band in
                HStack(spacing: CKSpacing.xs) {
                    WaymarkPinMark(band: band, type: nil, size: 18)
                    Text(band.word).font(.footnote.weight(.semibold))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(band.word): \(Self.range(band))")
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(CKColor.textPrimary)
        .padding(.horizontal, CKSpacing.gutter)
        .padding(.vertical, CKSpacing.sm)
        .background(.regularMaterial)
    }

    /// "70 % or more" / "40 to 69 %" / "under 40 %" for VoiceOver.
    private static func range(_ band: WaymarkConfidenceBand) -> String {
        let hi = Int(WaymarkConfidenceBand.likelyMin * 100), lo = Int(WaymarkConfidenceBand.uncertainMin * 100)
        switch band {
        case .likely: return "\(hi) percent or more"
        case .uncertain: return "\(lo) to \(hi - 1) percent"
        case .doubtful: return "under \(lo) percent"
        }
    }

    /// Details of the tapped pin, else what the map shows.
    @ViewBuilder private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: CKSpacing.sm) {
            if let pin = selected {
                HStack(alignment: .center, spacing: CKSpacing.md) {
                    WaymarkPinMark(band: WaymarkConfidenceBand(p: pin.p), type: pin.prior.type, size: 34,
                                   checked: pin.checked)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WaymarkGlance.reported(pin.prior.type))
                            .font(CKFont.cardTitle)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($detailsFocused)
                        Text(WaymarkGlance.confidence(pin.p))
                            .font(CKFont.body.weight(.semibold))
                            .monospacedDigit()
                            .accessibilityLabel(WaymarkGlance.confidenceSpoken(pin.p))
                    }
                    Spacer(minLength: 0)
                    Button { selectedID = nil } label: {
                        Image(systemName: "xmark").font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(CKColor.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close details")
                }
                // Task 3: what this phone learned about the report (this launch, else earlier).
                if let learned = WaymarkGlance.pinLearningDetail(learning: pin.learning, checked: pin.checked) {
                    // Review: the icon follows the outcome (a check seal beside "Not there" misled).
                    Label(learned, systemImage: WaymarkGlance.learningSymbol(pin.learning))
                        .font(CKFont.body.weight(.semibold))
                        .foregroundStyle(CKColor.textPrimary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(WaymarkGlance.learningDetailSpoken(learning: pin.learning,
                                                                               checked: pin.checked) ?? learned)
                        .accessibilityIdentifier("waymark-pin-learning")
                }
                detailLine(WaymarkGlance.imagery(pin.prior.imageryDate), "camera")
                detailLine(WaymarkGlance.votes(agree: pin.prior.nAgree, disagree: pin.prior.nDisagree), "person.2")
                if !pin.prior.tags.isEmpty {
                    detailLine("Tagged: " + pin.prior.tags.joined(separator: ", "), "tag")
                }
                Text("Project Sidewalk report \(pin.id) · a report, not something this phone detected")
                    .font(.caption).foregroundStyle(CKColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(WaymarkGlance.grouped(pins.count)) Project Sidewalk \(pins.count == 1 ? "report" : "reports") on this map")
                    .font(CKFont.label)
                Text("Tap a pin for its details. Faded pins are never spoken. These are other people's reports, separate from the hazards the cane logs on the Details page.")
                    .font(CKFont.secondary).foregroundStyle(CKColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(CKColor.textPrimary)
        .padding(CKSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    /// One icon + words row.
    private func detailLine(_ words: String, _ symbol: String) -> some View {
        Label(words, systemImage: symbol)
            .font(CKFont.secondary)
            .foregroundStyle(CKColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One pin: the band's shape in the band's colour, a type glyph inside, a dark hairline so it reads
/// on any map tile; dimmed for types never spoken; larger when selected.
struct WaymarkPinMark: View {
    /// Confidence band (colour and shape).
    let band: WaymarkConfidenceBand
    /// Label type for the glyph and dimming; nil in the legend.
    let type: WaymarkLabelType?
    /// Side length in points (the map wraps it in a 44 pt target).
    var size: CGFloat = 24
    /// The pin is the selected one.
    var selected = false
    /// Task 3: field evidence is stored on this phone — a small dot badge (text colour, ringed in
    /// the surface colour), top right.
    var checked = false

    /// Shape and glyph (and the checked badge).
    var body: some View {
        let s = selected ? size * 1.3 : size
        let dot = max(8, s * 0.34)
        ZStack {
            switch band.shape {
            case .filledCircle:
                Circle().fill(Self.fill(band)).overlay(Circle().strokeBorder(CKColor.ink.opacity(0.7), lineWidth: 1.5))
            case .filledDiamond:
                RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                    .fill(Self.fill(band))
                    .overlay(RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                                .strokeBorder(CKColor.ink.opacity(0.7), lineWidth: 1.5))
                    .rotationEffect(.degrees(45))
                    .scaleEffect(0.78)
            case .hollowRing:
                Circle().fill(CKColor.surface)
                    .overlay(Circle().strokeBorder(Self.fill(band), lineWidth: max(3, s * 0.16)))
                    .overlay(Circle().strokeBorder(CKColor.ink.opacity(0.7), lineWidth: 1))
            }
            if let type {
                Image(systemName: Self.glyph(type))
                    .font(.system(size: s * 0.42, weight: .heavy))
                    .foregroundStyle(band.shape == .hollowRing ? CKColor.textPrimary : CKColor.ink)
            }
        }
        .frame(width: s, height: s)
        .overlay(alignment: .topTrailing) {
            if checked {
                Circle().fill(CKColor.textPrimary)
                    .overlay(Circle().strokeBorder(CKColor.surface, lineWidth: max(1.5, dot * 0.2)))
                    .frame(width: dot, height: dot)
                    .offset(x: dot * 0.2, y: -dot * 0.2)
            }
        }
        .opacity(type.map(WaymarkGlance.isSpoken) == false ? 0.45 : 1)
        .accessibilityHidden(type == nil)
    }

    /// Band colour: three steps of the lane ladder (amber / lemon / sky blue), each ≥ 10:1 against
    /// `ink` and ≥ 0.116 OKLab apart for normal, protan, deutan and tritan vision (Theme.swift). Not the
    /// rose of STOP / Stop route: a likely curb ramp is not a danger (review 9).
    static func fill(_ band: WaymarkConfidenceBand) -> Color {
        switch band {
        case .likely: CKColor.laneNear
        case .uncertain: CKColor.laneFar
        case .doubtful: CKColor.laneClear
        }
    }

    /// A type glyph (decoration; the words carry the type).
    static func glyph(_ type: WaymarkLabelType) -> String {
        switch type {
        case .obstacle: "exclamationmark"
        case .missingCurbRamp: "xmark"
        case .curbRamp: "figure.roll"
        case .surfaceProblem: "water.waves"
        case .noSidewalk: "nosign"
        case .crosswalk: "figure.walk"
        case .other: "questionmark"
        }
    }
}

private extension Coordinate {
    /// MapKit's coordinate type.
    var clLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
