import ImageIO
import SwiftUI

struct ReaderPanel: View {
    @ObservedObject var store: ReaderStore
    let importBooks: () -> Void
    let quit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var palette: Palette {
        let theme = store.state.preferences.theme
        return Palette(theme: theme, systemIsDark: theme == .glass && colorScheme == .dark,
                       reduceTransparency: theme == .glass && reduceTransparency)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            if let notice = store.notice { noticeBar(notice) }
            ZStack(alignment: .topTrailing) {
                page
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(store.showsSettings)
                    .allowsHitTesting(!store.showsSettings)
                if store.showsSettings {
                    Rectangle()
                        .fill(.black.opacity(palette.isDark ? 0.20 : 0.07))
                        .onTapGesture { store.showsSettings = false }
                        .accessibilityHidden(true)
                    PreferencesPage(store: store, palette: palette, quit: quit)
                        .frame(maxWidth: 308)
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(palette.ink)
        .background(palette.panelBackground)
        .preferredColorScheme(palette.theme == .glass ? nil : (palette.isDark ? .dark : .light))
        .alert("移除《\(store.removalCandidate?.title ?? "")》？",
               isPresented: Binding(get: { store.removalCandidate != nil }, set: { if !$0 { store.removalCandidate = nil } }),
               presenting: store.removalCandidate) { book in
            Button("从书架移除", role: .destructive) { store.remove(book) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("会删除BookBar保存的副本和阅读进度，原文件会保留。")
        }
    }

    private var rule: some View { Rectangle().fill(palette.line).frame(height: 1) }

    private var page: some View {
        ZStack {
            if let book = store.current, let request = store.request, request.bookID == book.id {
                VStack(spacing: 0) {
                    ReadingSurface(book: book, request: request, store: store, palette: palette)
                        .id(book.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    readerFooter(book)
                }
                .opacity(store.screen == .reader ? 1 : 0)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(store.screen != .reader)
                .allowsHitTesting(store.screen == .reader)
            }
            switch store.screen {
            case .shelf:
                ShelfPage(store: store, palette: palette, importBooks: importBooks)
            case .contents:
                if let book = store.current {
                    ContentsPage(book: book, palette: palette, jump: store.jump)
                        .id(book.id)
                }
            case .reader:
                EmptyView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if store.screen == .reader, let book = store.current {
                Button { store.show(.shelf) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.accent)
                        Text(book.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReaderButtonStyle(palette: palette))
                .help("打开书架 · ⌘B")
                .accessibilityLabel("书架，当前阅读《\(book.title)》")
            } else {
                if store.current != nil {
                    GlyphButton(icon: "chevron.left", label: "返回阅读", palette: palette) {
                        store.show(.reader)
                    }
                }
                Text(store.screen == .contents ? contentsLabel : "书架")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.leading, store.current == nil ? 8 : 0)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 5)
            if store.importing {
                ProgressView().controlSize(.small).frame(width: 26).accessibilityLabel("正在导入")
            }
            if store.screen == .shelf, !store.books.isEmpty {
                ActionButton(title: "导入", icon: "plus", palette: palette, action: importBooks)
                    .disabled(store.importing)
                    .help("导入电子书 · ⌘O")
            }
            GlyphButton(icon: "textformat.size", label: "阅读设置", palette: palette,
                        selected: store.showsSettings) { store.showsSettings.toggle() }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
    }

    private var contentsLabel: String { store.current?.format == .pdf ? "跳转页码" : "目录" }

    private func noticeBar(_ notice: ReaderStore.Notice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.circle" : "info.circle")
            Text(notice.message).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            GlyphButton(icon: "xmark", label: "关闭提示", palette: palette) { store.notice = nil }
        }
        .font(.system(size: 11))
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(palette.fill)
    }

    private func readerFooter(_ book: Book) -> some View {
        let isPDF = book.format == .pdf
        let chapter = book.position.chapter
        let progress = "\(book.percentage)%"
        let location = isPDF ? "第 \(chapter + 1) / \(book.sectionCount) 页"
            : (book.chapters.indices.contains(chapter) ? book.chapters[chapter].title : book.format.label)

        return VStack(spacing: 0) {
            ProgressTrack(percentage: book.percentage, palette: palette)
            HStack(spacing: 4) {
                GlyphButton(icon: "chevron.left", label: isPDF ? "上一页" : "上一节",
                            palette: palette) { store.step(-1) }
                    .disabled(chapter == 0)
                Button { store.show(.contents) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .medium))
                        Text(location).lineLimit(1)
                        if !isPDF {
                            Text(progress).monospacedDigit().layoutPriority(1)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReaderButtonStyle(palette: palette))
                .help(contentsLabel)
                .accessibilityLabel("\(contentsLabel)，\(location)，阅读进度 \(progress)")
                GlyphButton(icon: "chevron.right", label: isPDF ? "下一页" : "下一节",
                            palette: palette) { store.step(1) }
                    .disabled(chapter + 1 >= book.sectionCount)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
        }
    }
}

private struct ReadingSurface: View {
    let book: Book
    let request: ReaderRequest
    @ObservedObject var store: ReaderStore
    let palette: Palette
    @State private var error: String?

    var body: some View {
        ZStack {
            switch book.format {
            case .pdf:
                PDFReader(file: store.location(for: book).appendingPathComponent("book.pdf"), request: request,
                          background: palette.pageBackground, visible: store.screen == .reader, onPosition: store.record, onError: { error = $0 })
            case .epub, .txt:
                WebReader(book: book, folder: store.location(for: book), request: request,
                          preferences: store.state.preferences, palette: palette, visible: store.screen == .reader, onPosition: store.record,
                          onLink: store.jump, onError: { error = $0 })
            }
            if let error {
                VStack(spacing: 11) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 25))
                    Text(error).font(.system(size: 13))
                    Button("重试") { store.jump(to: book.position.chapter) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.paper)
            }
        }
    }
}

private struct ShelfPage: View {
    @ObservedObject var store: ReaderStore
    let palette: Palette
    let importBooks: () -> Void

    var body: some View {
        if store.books.isEmpty {
            emptyShelf
        } else {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.books) { book in bookRow(book) }
                }
                .padding(10)
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(palette.accent)
                .frame(width: 56, height: 56)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            Text("书架还是空的")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("支持 EPUB、TXT 和 PDF")
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
            ActionButton(title: "导入电子书", icon: "plus", palette: palette, action: importBooks)
                .disabled(store.importing)
                .padding(.top, 6)
            Button("先读一篇试试") { store.openDemo() }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .font(.system(size: 12, weight: .medium))
                .disabled(store.importing)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookRow(_ book: Book) -> some View {
        let selected = store.current?.id == book.id
        let progress = book.lastOpened == nil ? "未开始" : "\(book.percentage)%"
        return Button { store.open(book) } label: {
            HStack(spacing: 10) {
                BookCover(book: book, folder: store.location(for: book), palette: palette)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(book.author ?? book.format.label)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(progress)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(selected ? palette.accent : palette.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ReaderButtonStyle(palette: palette, selected: selected))
        .accessibilityLabel(book.title)
        .accessibilityValue(progress)
        .accessibilityAction(named: Text("从书架移除")) { store.removalCandidate = book }
        .contextMenu {
            Button("从书架移除", role: .destructive) { store.removalCandidate = book }
        }
    }
}

private struct BookCover: View {
    let book: Book
    let folder: URL
    let palette: Palette
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack(alignment: .leading) {
                    palette.accent.opacity(0.20)
                    Rectangle().fill(palette.accent.opacity(0.23)).frame(width: 4)
                    Image(systemName: "book.closed")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 28, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
        .task(id: book.id) {
            guard let path = book.cover, ZipArchive.isSafe(path) else { return }
            let url = folder.appendingPathComponent(path)
            let thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            }.value
            if let thumbnail { image = NSImage(cgImage: thumbnail, size: .zero) }
        }
    }
}

private struct ContentsPage: View {
    let book: Book
    let palette: Palette
    let jump: (Int, String?) -> Void
    @State private var page = ""
    @FocusState private var pageFocused: Bool

    var body: some View {
        if book.format == .pdf {
            VStack(alignment: .leading, spacing: 16) {
                Text("当前第 \(book.position.chapter + 1) 页 · 共 \(book.sectionCount) 页")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                HStack(spacing: 10) {
                    TextField("输入页码", text: $page)
                        .textFieldStyle(.roundedBorder)
                        .focused($pageFocused)
                        .onSubmit(jumpToPage)
                    ActionButton(title: "跳转", icon: "arrow.turn.down.right", palette: palette, action: jumpToPage)
                        .disabled(validPage == nil)
                }
                Spacer()
            }
            .padding(16)
            .onAppear {
                DispatchQueue.main.async { pageFocused = true }
            }
        } else {
            let entries = book.contentsEntries
            let activeIndex = entries.firstIndex(where: { $0.chapter == book.position.chapter })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            let active = index == activeIndex
                            Button {
                                jump(entry.chapter, entry.fragment)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(entry.title).font(.system(size: 13, weight: active ? .semibold : .regular))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if active {
                                        Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(palette.accent)
                                    }
                                }
                                .padding(.vertical, 9)
                                .padding(.trailing, 10)
                                .padding(.leading, 10 + CGFloat(min(4, entry.depth)) * 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ReaderButtonStyle(palette: palette, selected: active))
                            .id(index)
                        }
                    }
                    .padding(13)
                }
                .onAppear {
                    if let activeIndex { proxy.scrollTo(activeIndex, anchor: .center) }
                }
            }
        }
    }

    private var validPage: Int? {
        guard let number = Int(page.trimmingCharacters(in: .whitespaces)), (1...book.sectionCount).contains(number) else {
            return nil
        }
        return number - 1
    }

    private func jumpToPage() {
        if let validPage { jump(validPage, nil) }
    }
}
