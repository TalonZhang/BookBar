import CoreFoundation
import CryptoKit
import Foundation
import PDFKit

enum BookImporter {
    static func importBook(_ source: URL, into booksDirectory: URL, excluding fingerprints: Set<String>) throws -> Book? {
        guard let format = BookFormat(rawValue: source.pathExtension.lowercased()) else { throw LibraryError.unsupported }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else { throw LibraryError.unsupported }
        guard (properties.fileSize ?? 0) <= 300 * 1024 * 1024 else { throw LibraryError.tooLarge }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= 300 * 1024 * 1024 else { throw LibraryError.tooLarge }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !fingerprints.contains(fingerprint) else { return nil }

        let name = source.deletingPathExtension().lastPathComponent
        return try create(in: booksDirectory) { id, folder in
            switch format {
            case .epub:
                try ZipArchive(data).extract(to: folder)
                let epub = try EPUB(root: folder)
                return Book(id: id, title: epub.title ?? name, author: epub.author, format: format,
                            fingerprint: fingerprint, chapters: epub.chapters, contents: epub.contents,
                            cover: epub.cover, pdfPageCount: nil)
            case .txt:
                guard let text = decodeText(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LibraryError.invalidTXT
                }
                let chapters = try writeText(text, to: folder)
                return Book(id: id, title: name, author: nil, format: format, fingerprint: fingerprint,
                            chapters: chapters, contents: [], cover: nil, pdfPageCount: nil)
            case .pdf:
                guard let pdf = PDFDocument(data: data) else { throw LibraryError.invalidPDF }
                guard !pdf.isLocked else { throw LibraryError.protected }
                guard pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
                try data.write(to: folder.appendingPathComponent("book.pdf"))
                let metadata = pdf.documentAttributes
                let title = (metadata?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let author = (metadata?[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return Book(id: id, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? name,
                            author: author.flatMap { $0.isEmpty ? nil : $0 }, format: format,
                            fingerprint: fingerprint, chapters: [], contents: [], cover: nil, pdfPageCount: pdf.pageCount)
            }
        }
    }

    static func demo(in booksDirectory: URL) throws -> Book {
        try create(in: booksDirectory) { id, folder in
            let chapters = try DemoBook.sections.enumerated().map { index, section in
                let path = "chapter-\(index).html"
                let body = "<h1>\(escape(section.title))</h1>" + section.paragraphs.map { "<p>\(escape($0))</p>" }.joined()
                try document(body).write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
                return BookChapter(title: section.title, path: path)
            }
            return Book(id: id, title: "午后的空白", author: "BookBar · 试读", format: .txt, fingerprint: "sample",
                        chapters: chapters, contents: [], cover: nil, pdfPageCount: nil)
        }
    }

    private static func create(in booksDirectory: URL, build: (UUID, URL) throws -> Book) throws -> Book {
        let id = UUID()
        let staging = booksDirectory.appendingPathComponent(".import-\(id.uuidString)", isDirectory: true)
        let destination = booksDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let files = FileManager.default
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        let book = try build(id, staging)
        try files.moveItem(at: staging, to: destination)
        return book
    }

    private static func decodeText(_ data: Data) -> String? {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") {
            text = utf8
        } else if data.contains(0) {
            let sample = data.prefix(1024)
            let evenZeros = sample.enumerated().filter { $0.offset.isMultiple(of: 2) && $0.element == 0 }.count
            let oddZeros = sample.filter { $0 == 0 }.count - evenZeros
            guard max(evenZeros, oddZeros) > sample.count / 10, evenZeros != oddZeros else { return nil }
            text = String(data: data, encoding: oddZeros > evenZeros ? .utf16LittleEndian : .utf16BigEndian)
        } else {
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
            text = String(data: data, encoding: String.Encoding(rawValue: gb))
                ?? String(data: data, encoding: String.Encoding(rawValue: big5))
                ?? String(data: data, encoding: .windowsCP1252)
        }
        return text?.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    }

    private static func writeText(_ text: String, to folder: URL) throws -> [BookChapter] {
        var chapters: [BookChapter] = []
        var start = text.startIndex
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: 12_000, limitedBy: text.endIndex) ?? text.endIndex
            var end = limit
            if limit < text.endIndex,
               let newline = text[text.index(start, offsetBy: 8_000)..<limit].lastIndex(of: "\n") {
                end = text.index(after: newline)
            }
            let path = "chapter-\(chapters.count).html"
            let title = "第 \(chapters.count + 1) 节"
            let body = "<div class=\"pb-plain\">\(escape(String(text[start..<end])))</div>"
            try document(body).write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
            chapters.append(BookChapter(title: title, path: path))
            start = end
        }
        return chapters
    }

    private static func document(_ body: String) -> String {
        "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
