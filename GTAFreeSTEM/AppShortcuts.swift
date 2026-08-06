import AppIntents

enum GTAFreeSTEMShortcutDestination: String, AppEnum {
    case opportunities
    case highSchool

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "GTA FREE STEM area")

    static let caseDisplayRepresentations: [GTAFreeSTEMShortcutDestination: DisplayRepresentation] = [
        .opportunities: DisplayRepresentation(title: "Opportunities"),
        .highSchool: DisplayRepresentation(title: "High school pathways")
    ]

    var deepLink: URL {
        URL(string: "gtafreestem://\(self == .opportunities ? "opportunities" : "high-school")")!
    }
}

@available(iOS 18.0, *)
struct OpenGTAFreeSTEMIntent: AppIntent {
    static let title: LocalizedStringResource = "Explore GTA FREE STEM"
    static let description = IntentDescription("Open free STEM opportunities or high school pathways in GTA FREE STEM.")
    static let openAppWhenRun = true

    @Parameter(title: "Open") var destination: GTAFreeSTEMShortcutDestination

    init() {
        destination = .opportunities
    }

    init(destination: GTAFreeSTEMShortcutDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(destination.deepLink))
    }
}

@available(iOS 18.0, *)
struct GTAFreeSTEMShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGTAFreeSTEMIntent(destination: .opportunities),
            phrases: [
                "Find free STEM opportunities in \(.applicationName)",
                "Open opportunities in \(.applicationName)"
            ],
            shortTitle: "Find opportunities",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenGTAFreeSTEMIntent(destination: .highSchool),
            phrases: [
                "Show high school pathways in \(.applicationName)",
                "Open high school pathways in \(.applicationName)"
            ],
            shortTitle: "High school pathways",
            systemImageName: "graduationcap.fill"
        )
    }
}
