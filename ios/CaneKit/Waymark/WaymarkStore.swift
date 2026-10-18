//
//  WaymarkStore.swift
//  CaneKit
//
//  Waymark E1 (M_NOTES §8.1): the phone-side files of sidewalk memory, in the app's Documents
//  folder (visible in the Files app, like the trip logs):
//    · `waymark/evidence.jsonl` — one `waymark.evidence.v1` line per outcome, appended. This is what
//      `ios/scripts/waymark_export.py` (E2) copies off the phone; it holds label ids and distances,
//      never coordinates.
//    · `waymark/beliefs.json` — the per-label beliefs (`[String: WaymarkBelief]`), written
//      atomically after every outcome and read back on load, so evidence survives a relaunch.
//  Never throws to the caller: a write failure is returned as a message for the trip log and the
//  engine carries on (evidence is a measurement, not a safety function).
//  Owner: `WaymarkEngine`. Tests: the line format is `WaymarkRecordTests` / `WaymarkGoldenTests`.
//

import Foundation
import CaneKitLogic

/// Reads and writes the Waymark files. Main actor; each call is one small file operation.
struct WaymarkStore {
    /// `Documents/waymark/`, created on first use. Nil if Documents cannot be found.
    let folder: URL?

    /// The app's store. Tests or previews could pass another folder.
    init(folder: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("waymark", isDirectory: true)) {
        self.folder = folder
    }

    /// `evidence.jsonl`.
    var evidenceURL: URL? { folder?.appendingPathComponent("evidence.jsonl") }
    /// `beliefs.json`.
    var beliefsURL: URL? { folder?.appendingPathComponent("beliefs.json") }

    /// Appends one JSON line (a newline is added).
    /// - Returns: nil on success, else what went wrong.
    func appendEvidence(_ line: String) -> String? {
        guard let url = evidenceURL, let data = (line + "\n").data(using: .utf8) else { return "no documents folder" }
        do {
            try ensureFolder()
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
            return nil
        } catch {
            return Self.brief(error)
        }
    }

    /// An error as "domain code" only: `String(describing:)` includes the app container path (the
    /// install UUID), which must not reach the trip log or the E2 export (E1 review).
    static func brief(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain) \(e.code)"
    }

    /// Writes the beliefs atomically.
    /// - Returns: nil on success, else what went wrong.
    func saveBeliefs(_ beliefs: [String: WaymarkBelief]) -> String? {
        guard let url = beliefsURL else { return "no documents folder" }
        do {
            try ensureFolder()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(beliefs).write(to: url, options: .atomic)
            return nil
        } catch {
            return Self.brief(error)
        }
    }

    /// The saved beliefs, or empty when there are none or the file is unreadable.
    func loadBeliefs() -> [String: WaymarkBelief] {
        guard let url = beliefsURL, let data = try? Data(contentsOf: url),
              let beliefs = try? JSONDecoder().decode([String: WaymarkBelief].self, from: data) else { return [:] }
        return beliefs
    }

    /// Creates `Documents/waymark/` if needed.
    private func ensureFolder() throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
