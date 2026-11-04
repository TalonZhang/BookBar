import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct BookBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = StatusController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class StatusController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private let store: ReaderStore
    private var item: NSStatusItem?
    private var sizeObserver: AnyCancellable?
    private var keyboard: Any?
    private var openPanel: NSOpenPanel?

    override init() {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["BOOKBAR_LIBRARY_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let current = support.appendingPathComponent("BookBar", isDirectory: true)
            let previous = support.appendingPathComponent("PageBetween", isDirectory: true)
            let files = FileManager.default
            directory = !files.fileExists(atPath: current.path) && files.fileExists(atPath: previous.path) ? previous : current
        }
        store = ReaderStore(directory: directory)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "BookBar")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "BookBar · 随手读一会儿"
        item.button?.setAccessibilityLabel("BookBar")
        self.item = item

        let hosting = NSHostingController(rootView: ReaderPanel(store: store, importBooks: { [weak self] in
            self?.selectFiles()
        }, quit: { NSApp.terminate(nil) }))
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true

        sizeObserver = store.$state.map(\.preferences.panelSize).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in self?.resize(to: size) }
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !popover.isShown, openPanel == nil { showPopover() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboard { NSEvent.removeMonitor(keyboard) }
        store.flush()
    }

    func popoverDidClose(_ notification: Notification) {
        store.flush()
    }

    @objc private func togglePopover() {
        if let openPanel {
            openPanel.makeKeyAndOrderFront(nil)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover(resumeReading: Bool = true) {
        guard let button = item?.button, button.window != nil else { return }
        if resumeReading { store.showHome() }
        resize(to: store.state.preferences.panelSize)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func resize(to preset: PanelSize) {
        let available = (item?.button?.window?.screen ?? NSScreen.main)?.visibleFrame.size
        let size = preset.size
        popover.contentSize = NSSize(width: min(size.width, (available?.width ?? size.width + 20) - 20),
                                     height: min(size.height, (available?.height ?? size.height + 24) - 24))
    }

    private func selectFiles() {
        guard openPanel == nil, !store.importing else { return }
        let panel = NSOpenPanel()
        panel.title = "导入电子书"
        panel.prompt = "导入"
        panel.message = "选择 EPUB、TXT 或 PDF 文件，可同时导入多本。"
        panel.allowedContentTypes = [UTType(filenameExtension: "epub"), .plainText, .pdf].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        openPanel = panel
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self, weak panel] response in
            guard let self, let panel else { return }
            let urls = panel.urls
            self.openPanel = nil
            DispatchQueue.main.async {
                self.showPopover(resumeReading: false)
                if response == .OK { self.store.importFiles(urls) }
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown, openPanel == nil, store.removalCandidate == nil else { return event }
        if event.keyCode == 53 {
            if !store.dismissLayer() { popover.performClose(nil) }
            return nil
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return event }
        if store.screen == .reader, !store.showsSettings, !modifiers.contains(.shift) {
            switch event.keyCode {
            case 123: store.step(-1); return nil
            case 124: store.step(1); return nil
            default: break
            }
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "o": selectFiles()
        case "b": store.toggleShelf()
        case ",": store.showsSettings.toggle()
        case "q": NSApp.terminate(nil)
        case "+", "=": store.adjustFont(1)
        case "-", "−": store.adjustFont(-1)
        case "a": return edit("selectAll:", event: event)
        case "c": return edit("copy:", event: event)
        case "v": return edit("paste:", event: event)
        case "x": return edit("cut:", event: event)
        default: return event
        }
        return nil
    }

    private func edit(_ action: String, event: NSEvent) -> NSEvent? {
        NSApp.sendAction(Selector(action), to: nil, from: nil) ? nil : event
    }
}
