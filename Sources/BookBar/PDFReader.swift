import PDFKit
import SwiftUI

struct PDFReader: NSViewRepresentable {
    let file: URL
    let request: ReaderRequest
    let background: NSColor
    let visible: Bool
    let onPosition: (ReadingPosition, UUID) -> Void
    let onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.autoScales = true
        view.document = PDFDocument(url: file)
        let coordinator = context.coordinator
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        if view.document == nil {
            DispatchQueue.main.async { coordinator.parent.onError("无法读取这本 PDF。") }
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.isHidden == visible { view.isHidden = !visible }
        let coordinator = context.coordinator
        coordinator.parent = self
        view.backgroundColor = background
        if coordinator.lastToken != request.token,
           let page = view.document?.page(at: request.chapter) {
            coordinator.lastToken = request.token
            view.go(to: page)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PDFReader
        var lastToken: UUID?

        init(_ parent: PDFReader) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let page = view.currentPage,
                  let index = view.document?.index(for: page), let token = lastToken else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.onPosition(ReadingPosition(chapter: index, fraction: 0), token)
            }
        }
    }
}
