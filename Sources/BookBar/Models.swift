import Foundation

enum BookFormat: String, Codable {
    case epub, txt, pdf
    var label: String { rawValue.uppercased() }
}

struct BookChapter: Codable, Hashable {
    let title: String
    let path: String
}

struct ContentsEntry: Codable, Hashable {
    let title: String
    let chapter: Int
    let fragment: String?
    let depth: Int
}

struct ReadingPosition: Codable, Equatable {
    var chapter = 0
    var fraction = 0.0
}

struct Book: Codable, Identifiable {
    let id: UUID
    let title: String
    let author: String?
    let format: BookFormat
    let fingerprint: String
    let chapters: [BookChapter]
    let contents: [ContentsEntry]
    let cover: String?
    let pdfPageCount: Int?
    var position = ReadingPosition()
    var lastOpened: Date?

    var sectionCount: Int { pdfPageCount ?? chapters.count }

    var percentage: Int {
        guard sectionCount > 0 else { return 0 }
        if format == .pdf {
            guard lastOpened != nil else { return 0 }
            return (position.chapter + 1) * 100 / sectionCount
        }
        return Int(100 * (Double(position.chapter) + position.fraction) / Double(sectionCount))
    }

    var contentsEntries: [ContentsEntry] {
        if !contents.isEmpty { return contents }
        return chapters.enumerated().map {
            ContentsEntry(title: $0.element.title, chapter: $0.offset, fragment: nil, depth: 0)
        }
    }
}

enum ReadingTheme: String, Codable, CaseIterable, Identifiable {
    case paper, warm, night, glass
    var id: Self { self }
    var title: String {
        switch self {
        case .paper: return "清白"
        case .warm: return "暖纸"
        case .night: return "夜读"
        case .glass: return "半透"
        }
    }
    var background: String {
        switch self {
        case .paper: return "#F8FAF7"
        case .warm: return "#F7F0E3"
        case .night: return "#222A28"
        case .glass: return "#EDF1F1"
        }
    }
    var ink: String {
        switch self {
        case .paper: return "#25372E"
        case .warm: return "#362D22"
        case .night: return "#E3EBE3"
        case .glass: return "#20282A"
        }
    }
    var muted: String {
        switch self {
        case .paper: return "#5A6B60"
        case .warm: return "#6B6050"
        case .night: return "#AFBDB3"
        case .glass: return "#465358"
        }
    }
    var accent: String {
        switch self {
        case .paper: return "#266044"
        case .warm: return "#3A664C"
        case .night: return "#9CD2AE"
        case .glass: return "#315951"
        }
    }
}

enum PanelSize: String, Codable, CaseIterable, Identifiable {
    case compact, standard, large
    var id: Self { self }
    var title: String {
        switch self {
        case .compact: return "小"
        case .standard: return "标准"
        case .large: return "宽"
        }
    }
    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 370, height: 450)
        case .standard: return CGSize(width: 470, height: 565)
        case .large: return CGSize(width: 610, height: 680)
        }
    }
}

struct ReaderPreferences: Codable, Equatable {
    var fontSize = 18
    var lineHeight = 1.8
    var theme = ReadingTheme.warm
    var panelSize = PanelSize.standard
}

struct LibraryState: Codable {
    var books: [Book] = []
    var selectedID: UUID?
    var preferences = ReaderPreferences()
}

struct ReaderRequest: Equatable {
    let bookID: UUID
    let chapter: Int
    let fraction: Double
    let fragment: String?
    let token = UUID()
}

enum LibraryError: LocalizedError {
    case unsupported, tooLarge, invalidArchive, protected, invalidEPUB, invalidTXT, invalidPDF

    var errorDescription: String? {
        switch self {
        case .unsupported: return "请选择 EPUB、TXT 或 PDF 文件。"
        case .tooLarge: return "文件太大，或解压后的内容超过 300 MB。"
        case .invalidArchive: return "EPUB 压缩包损坏，或使用了不支持的压缩方式。"
        case .protected: return "这本书受密码或 DRM 保护，无法导入。"
        case .invalidEPUB: return "没有找到可阅读的 EPUB 正文。"
        case .invalidTXT: return "无法识别 TXT 编码，或文件没有正文。"
        case .invalidPDF: return "无法打开此 PDF，或文件没有页面。"
        }
    }
}
