import AppKit
import Sparkle
import SwiftUI

/// Owns the status item and popover. MenuBarExtra can't accept file drops on its icon,
/// so this is plain AppKit with the SwiftUI content hosted inside.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let session = CompressSession()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.badge.arrow.down", accessibilityDescription: "MenuCompress")
            button.target = self
            button.action = #selector(togglePopover)

            // The status bar window forwards drag events to its delegate
            button.window?.registerForDraggedTypes([.fileURL])
            button.window?.delegate = self
        }

        let hostingController = NSHostingController(rootView: ContentView(session: session, checkForUpdates: { [weak self] in self?.checkForUpdates() }))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true

        session.presentPopover = { [weak self] in self?.showPopover() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.discardResult()
    }

    private func checkForUpdates() {
        popover.performClose(nil)
        NSApp.activate()
        updaterController.checkForUpdates(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first(where: ImageCompressor.isImage)
    }
}

extension AppDelegate: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageURL(from: sender) != nil else { return [] }
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        guard let url = imageURL(from: sender) else { return false }
        session.load(url)
        return true
    }
}

extension AppDelegate: SPUStandardUserDriverDelegate {
    // Apps without a Dock icon have to opt in, or Sparkle warns that scheduled update alerts may go unseen
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // A background check's alert would otherwise open behind whatever app is in front
        if handleShowingUpdate {
            NSApp.activate()
        }
    }
}
