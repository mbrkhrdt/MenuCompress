import SwiftUI

@main
struct MenuCompressApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // The UI lives in the status item's popover; this keeps SwiftUI from opening a window
        Settings { EmptyView() }
    }
}
