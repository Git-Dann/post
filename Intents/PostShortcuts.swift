import AppIntents

/// Surfaces Post's intents to Shortcuts, Spotlight, and the Action button with spoken phrases.
struct PostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyStyleIntent(),
            phrases: [
                "Apply a look with \(.applicationName)",
                "Edit a photo with \(.applicationName)",
                "\(.applicationName) a photo"
            ],
            shortTitle: "Apply a Look",
            systemImageName: "wand.and.stars"
        )
    }
}
