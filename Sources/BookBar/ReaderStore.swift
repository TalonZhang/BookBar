import AppKit
import Combine

@MainActor
final class ReaderStore: ObservableObject {
    enum Screen { case reader, shelf, contents }
    struct Notice: Identifiable {
        let id = UUID()
        let message: String
        var isError = false
    }

    @Published private(set) var state = LibraryState()
    @Published private(set) var screen = Screen.reader
    @Published var showsSettings = false
    @Published private(set) var request: ReaderRequest?
    @Published private(set) var importing = false
    @Published var notice: Notice?
    @Published var removalCandidate: Book?

    let directory: URL
    private var pendingSave: DispatchWorkItem?
    private var canSave = true
    private var booksDirectory: URL { directory.appendingPathComponent("Books", isDirectory: true) }
    private var index: URL { directory.appendingPathComponent("library.json") }

    var current: Book? { state.books.first { $0.id == state.selectedID } }
    var books: [Book] {
        state.books.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
    }

    init(directory: URL) {
        self.directory = directory
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                state = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: index))
            } catch {
                canSave = false
                notice = Notice(message: "无法读取书架记录。原记录已保留。", isError: true)
            }
        }
        if let current { request = makeRequest(for: current) }
        else { screen = .shelf }
    }

    func location(for book: Book) -> URL {
        booksDirectory.appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    func open(_ book: Book) {
        guard let index = state.books.firstIndex(where: { $0.id == book.id }) else { return }
        if state.selectedID != book.id || request == nil {
            request = makeRequest(for: state.books[index])
        }
        state.books[index].lastOpened = Date()
        state.selectedID = book.id
        show(.reader)
        flush()
    }

    func show(_ next: Screen) {
        if showsSettings { showsSettings = false }
        if screen != next { screen = next }
    }

    func showHome() {
        show(current == nil ? .shelf : .reader)
    }

    func toggleShelf() {
        if screen == .shelf { showHome() }
        else { show(.shelf) }
    }

    @discardableResult
    func dismissLayer() -> Bool {
        if showsSettings {
            showsSettings = false
        } else if screen != .reader, current != nil {
            show(.reader)
        } else {
            return false
        }
        return true
    }

    func updatePreferences(_ change: (inout ReaderPreferences) -> Void) {
        var preferences = state.preferences
        change(&preferences)
        guard preferences != state.preferences else { return }
        state.preferences = preferences
        scheduleSave()
    }

    func adjustFont(_ increment: Int) {
        guard current?.format != .pdf else { return }
        updatePreferences { $0.fontSize = min(32, max(12, $0.fontSize + increment)) }
    }

    func jump(to chapter: Int, fragment: String? = nil) {
        guard let book = current, book.sectionCount > 0 else { return }
        let chapter = min(book.sectionCount - 1, max(0, chapter))
        if let index = state.books.firstIndex(where: { $0.id == book.id }) {
            state.books[index].position = ReadingPosition(chapter: chapter, fraction: 0)
        }
        request = ReaderRequest(bookID: book.id, chapter: chapter, fraction: 0, fragment: fragment)
        show(.reader)
        flush()
    }

    func step(_ delta: Int) {
        guard let book = current else { return }
        let target = book.position.chapter + delta
        guard (0..<book.sectionCount).contains(target) else { return }
        jump(to: target)
    }

    func record(_ position: ReadingPosition, token: UUID) {
        guard let request, request.token == token, request.bookID == state.selectedID,
              let index = state.books.firstIndex(where: { $0.id == request.bookID }),
              (0..<state.books[index].sectionCount).contains(position.chapter), position.fraction.isFinite else { return }
        let old = state.books[index].position
        guard old.chapter != position.chapter || abs(old.fraction - position.fraction) >= 0.0001 else { return }
        state.books[index].position = position
        scheduleSave()
    }

    func importFiles(_ urls: [URL]) {
        guard canSave, !urls.isEmpty, !importing else { return }
        importing = true
        notice = nil
        Task {
            var failures: [String] = []
            var duplicates = 0
            var firstImported: Book?
            for source in urls {
                let directory = booksDirectory
                let fingerprints = Set(state.books.map(\.fingerprint))
                do {
                    if let book = try await Task.detached(priority: .userInitiated, operation: {
                        try BookImporter.importBook(source, into: directory, excluding: fingerprints)
                    }).value {
                        try add(book)
                        if firstImported == nil { firstImported = book }
                    } else {
                        duplicates += 1
                    }
                } catch {
                    failures.append("\(source.lastPathComponent) · \(error.localizedDescription)")
                }
            }
            if let firstImported { open(firstImported) }
            importing = false
            if !failures.isEmpty {
                let extra = failures.count > 1 ? "（另有 \(failures.count - 1) 个文件导入失败）" : ""
                notice = Notice(message: failures[0] + extra, isError: true)
            } else if duplicates > 0 {
                notice = Notice(message: "已跳过 \(duplicates) 本书架中已有的书。")
            }
        }
    }

    func openDemo() {
        guard canSave, !importing else { return }
        if let book = state.books.first(where: { $0.fingerprint == "sample" }) {
            open(book)
            return
        }
        do {
            let book = try BookImporter.demo(in: booksDirectory)
            try add(book)
            open(book)
        } catch {
            notice = Notice(message: error.localizedDescription, isError: true)
        }
    }

    func remove(_ book: Book) {
        guard canSave else { return }
        let previous = state
        state.books.removeAll { $0.id == book.id }
        if state.selectedID == book.id {
            state.selectedID = nil
        }
        do {
            try write()
        } catch {
            state = previous
            notice = Notice(message: "暂时无法移除这本书。\(error.localizedDescription)", isError: true)
            return
        }
        if state.selectedID == nil {
            request = nil
            show(.shelf)
        }
        let folder = location(for: book)
        if FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                notice = Notice(message: "已从书架移除，但暂时无法删除本机副本。\(error.localizedDescription)", isError: true)
            }
        }
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canSave else { return }
        do {
            try write()
        } catch {
            notice = Notice(message: "无法保存阅读记录。\(error.localizedDescription)", isError: true)
        }
    }

    private func add(_ book: Book) throws {
        state.books.append(book)
        do {
            try write()
        } catch {
            state.books.removeAll { $0.id == book.id }
            try? FileManager.default.removeItem(at: location(for: book))
            throw error
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func write() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: index, options: .atomic)
    }

    private func makeRequest(for book: Book) -> ReaderRequest {
        ReaderRequest(bookID: book.id, chapter: book.position.chapter, fraction: book.position.fraction, fragment: nil)
    }
}
