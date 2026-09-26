import AppIntents

/// The widget's "Brought in" button. As a `LiveActivityIntent`, iOS runs `perform()` in the app's
/// process (launching it in the background if needed), where the notifications and state live.
/// Both targets compile this same declaration; only the body differs.
struct MarkBroughtInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Groceries Brought In"
    static var description = IntentDescription("Stops the unload reminder.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppState.shared?.markUnloadComplete(source: "widget")
        #endif
        return .result()
    }
}
