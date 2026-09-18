import AppKit
import SwiftUI
import DiskGCCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel!
    private var notifier: UserNotificationsNotifier!
    private var timer: Timer?
    private var observer: Any?

    static let tickInterval: TimeInterval = 30 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier = UserNotificationsNotifier(
            fallback: OSAScriptNotifier(shell: ProcessShell()),
            onOpen: { [weak self] in self?.showPopover() }
        )
        notifier.requestAuthorization()

        let runtime = try? Runtime()
        model = AppModel(
            engine: Engine(notifier: notifier),
            configPath: runtime?.configPath ?? "",
            journalPath: runtime?.journalPath ?? ""
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "diskgc")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        observer = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.renderTitle() }
        }

        renderTitle()
        model.tick()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickUnlessBusy() }
        }
    }

    private func renderTitle() {
        guard let button = statusItem.button else { return }
        let colour: NSColor = model.isLow ? .systemRed : .labelColor
        button.attributedTitle = NSAttributedString(
            string: " \(model.menuBarTitle)",
            attributes: [.foregroundColor: colour, .font: NSFont.menuBarFont(ofSize: 0)]
        )
    }

    // The timer defers while the popover is open so rows never vanish under the pointer.
    private func tickUnlessBusy() {
        guard !popover.isShown else { return }
        model.tick()
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        model.refresh()
    }
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
