import SwiftUI

/// Source access and included notices are distinct from public distribution readiness.
enum BoundSourceNotices {
    static let availability = "Bound 2 source, build instructions, and modification notices are available in its source repository."
    static let sourceRepository = URL(string: "https://github.com/evanvonessen/Bound-2")!
    static func version(in bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
    enum Document: String, CaseIterable, Identifiable {
        case agpl, modifications, dependencies
        var id: String { rawValue }
        var title: String {
            switch self {
            case .agpl: return "GNU AGPL version 3"
            case .modifications: return "Bound 2 modifications"
            case .dependencies: return "Dependency inventory"
            }
        }
        var resource: String {
            switch self {
            case .agpl: return "COPYING"
            case .modifications: return "BOUND2-MODIFICATIONS"
            case .dependencies: return "DEPENDENCY-INVENTORY"
            }
        }
        var fileExtension: String? { self == .agpl ? nil : "md" }
        func data(in bundle: Bundle = .main) -> Data? {
            guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else { return nil }
            return try? Data(contentsOf: url)
        }
        func text(in bundle: Bundle = .main) -> String? {
            data(in: bundle).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

struct BoundSourceAndLicenses: View {
    var body: some View {
        Form {
            Section("This build") {
                LabeledContent("Version", value: BoundSourceNotices.version())
                    .accessibilityIdentifier("bound.source-version")
                Text(BoundSourceNotices.availability)
                    .accessibilityIdentifier("bound.source-availability")
                Link("Bound 2 source repository", destination: BoundSourceNotices.sourceRepository)
                    .accessibilityIdentifier("bound.source-repository")
                Text("These notices describe included software and remaining release questions. They do not certify public distribution readiness.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Upstream") {
                Text("Built on Delta. Delta and its emulator dependencies retain their original copyright and license notices.")
                Link("Delta upstream source", destination: URL(string: "https://github.com/rileytestut/Delta")!)
            }
            Section("Bundled notices") {
                ForEach(BoundSourceNotices.Document.allCases) { document in
                    NavigationLink(document.title) { BoundLicenseDocumentView(document: document) }
                        .accessibilityIdentifier("bound.license-" + document.rawValue)
                }
            }
        }
        .navigationTitle("Source and licenses")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("bound.source-and-licenses")
    }
}

private struct BoundLicenseDocumentView: View {
    let document: BoundSourceNotices.Document
    var body: some View {
        ScrollView {
            Text(document.text() ?? "This document could not be loaded from this build.")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("bound.license-content")
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("bound.license-document")
    }
}
