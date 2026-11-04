import Foundation

struct BookResource: Equatable {
    let path: String
    let fragment: String?

    init?(reference: String, relativeTo base: String) {
        let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let resource = parts.first else { return nil }
        let rawPath = String(resource.prefix { $0 != "?" })
        guard !rawPath.hasPrefix("//"), !(rawPath.split(separator: "/").first?.contains(":") ?? false) else { return nil }
        let path = rawPath.removingPercentEncoding ?? rawPath
        fragment = parts.count == 2 ? (parts[1].removingPercentEncoding ?? String(parts[1])) : nil
        if path.isEmpty {
            guard !base.isEmpty else { return nil }
            self.path = base
            return
        }

        var segments = path.hasPrefix("/") ? [] : base.split(separator: "/").dropLast().map(String.init)
        for segment in path.split(separator: "/") {
            switch segment {
            case ".": continue
            case "..":
                guard !segments.isEmpty else { return nil }
                segments.removeLast()
            default: segments.append(String(segment))
            }
        }
        let resolved = segments.joined(separator: "/")
        guard ZipArchive.isSafe(resolved) else { return nil }
        self.path = resolved
    }

    init(path: String, fragment: String?) {
        self.path = path
        self.fragment = fragment
    }
}

struct EPUB {
    let title: String?
    let author: String?
    let chapters: [BookChapter]
    let contents: [ContentsEntry]
    let cover: String?

    init(root: URL) throws {
        let container = try XMLTree.read("META-INF/container.xml", from: root)
        let packagePaths = container.child("rootfiles")?.children ?? []
        guard let opf = packagePaths.first(where: {
            $0.attributes["media-type"] == "application/oebps-package+xml"
        }) ?? packagePaths.first,
              let packagePath = opf.attributes["full-path"], ZipArchive.isSafe(packagePath) else {
            throw LibraryError.invalidEPUB
        }

        let package = try XMLTree.read(packagePath, from: root)
        let metadata = package.child("metadata")
        title = metadata?.child("title")?.value
        author = metadata?.child("creator")?.value

        var manifest: [String: ManifestItem] = [:]
        for node in package.child("manifest")?.children ?? [] {
            guard let id = node.attributes["id"], let href = node.attributes["href"],
                  let type = node.attributes["media-type"],
                  let resource = BookResource(reference: href, relativeTo: packagePath) else { continue }
            let properties = Set((node.attributes["properties"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            manifest[id] = ManifestItem(resource: resource, type: type, properties: properties)
        }

        let spine = package.child("spine")
        var spinePaths: [String] = []
        var seen = Set<String>()
        for item in spine?.children ?? [] {
            guard let id = item.attributes["idref"], let entry = manifest[id],
                  ["application/xhtml+xml", "text/html"].contains(entry.type),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(entry.resource.path).path),
                  seen.insert(entry.resource.path).inserted else { continue }
            spinePaths.append(entry.resource.path)
        }
        if spinePaths.isEmpty {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("META-INF/encryption.xml").path) {
                throw LibraryError.protected
            }
            throw LibraryError.invalidEPUB
        }
        if let encryption = try? XMLTree.read("META-INF/encryption.xml", from: root) {
            let protectedPaths = Set(encryption.descendants("CipherReference").compactMap {
                $0.attributes["URI"].flatMap { BookResource(reference: $0, relativeTo: "")?.path }
            })
            if spinePaths.contains(where: protectedPaths.contains) { throw LibraryError.protected }
        }

        let toc: [TOCItem]
        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
           let html = try? XMLTree.read(nav.resource.path, from: root),
           let navigation = html.descendants("nav").first(where: { node in
               let type = node.attributes["epub:type"] ?? node.attributes["type"] ?? ""
               return type.split(whereSeparator: \.isWhitespace).contains("toc") || node.attributes["role"] == "doc-toc"
           }) ?? html.descendants("nav").first,
           let list = navigation.child("ol") {
            toc = Self.navEntries(list, base: nav.resource.path, depth: 0)
        } else if let tocID = spine?.attributes["toc"], let ncx = manifest[tocID],
                  let document = try? XMLTree.read(ncx.resource.path, from: root),
                  let navMap = document.child("navMap") {
            toc = Self.ncxEntries(navMap, base: ncx.resource.path, depth: 0)
        } else {
            toc = []
        }

        let indices = Dictionary(uniqueKeysWithValues: spinePaths.enumerated().map { ($0.element, $0.offset) })
        contents = toc.compactMap { item in
            guard let index = indices[item.resource.path] else { return nil }
            return ContentsEntry(title: item.title, chapter: index, fragment: item.resource.fragment, depth: item.depth)
        }
        var chapterTitles: [Int: String] = [:]
        for entry in contents where chapterTitles[entry.chapter] == nil {
            chapterTitles[entry.chapter] = entry.title
        }
        chapters = spinePaths.enumerated().map { index, path in
            BookChapter(title: chapterTitles[index] ?? "第 \(index + 1) 节", path: path)
        }

        let legacyCover = metadata?.children.first(where: { $0.attributes["name"] == "cover" })?.attributes["content"]
        let coverItem = manifest.values.first(where: { $0.properties.contains("cover-image") }) ?? legacyCover.flatMap { manifest[$0] }
        cover = coverItem?.resource.path
    }

    private struct ManifestItem {
        let resource: BookResource
        let type: String
        let properties: Set<String>
    }

    private struct TOCItem {
        let title: String
        let resource: BookResource
        let depth: Int
    }

    private static func navEntries(_ list: XMLNode, base: String, depth: Int) -> [TOCItem] {
        list.children.filter { $0.name == "li" }.flatMap { item -> [TOCItem] in
            var entries: [TOCItem] = []
            if let link = item.child("a"), let title = link.value, let href = link.attributes["href"],
               let resource = BookResource(reference: href, relativeTo: base) {
                entries.append(TOCItem(title: title, resource: resource, depth: depth))
            }
            if let nested = item.child("ol") {
                entries += navEntries(nested, base: base, depth: depth + 1)
            }
            return entries
        }
    }

    private static func ncxEntries(_ node: XMLNode, base: String, depth: Int) -> [TOCItem] {
        node.children.filter { $0.name == "navPoint" }.flatMap { item -> [TOCItem] in
            var entries: [TOCItem] = []
            if let title = item.child("navLabel")?.value, let href = item.child("content")?.attributes["src"],
               let resource = BookResource(reference: href, relativeTo: base) {
                entries.append(TOCItem(title: title, resource: resource, depth: depth))
            }
            entries += ncxEntries(item, base: base, depth: depth + 1)
            return entries
        }
    }
}

private final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(_ name: String, attributes: [String: String] = [:]) {
        self.name = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = attributes
    }

    var value: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func child(_ name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func descendants(_ name: String) -> [XMLNode] {
        children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(name)
        }
    }
}

private final class XMLTree: NSObject, XMLParserDelegate {
    private var stack = [XMLNode("root")]
    private var textCount = 0

    static func read(_ path: String, from root: URL) throws -> XMLNode {
        let url = root.appendingPathComponent(path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4 * 1024 * 1024, let parser = XMLParser(contentsOf: url) else { throw LibraryError.invalidEPUB }
        let tree = XMLTree()
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = tree
        guard parser.parse(), let document = tree.stack.first?.children.first else { throw LibraryError.invalidEPUB }
        return document
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard stack.count < 128 else { parser.abortParsing(); return }
        let node = XMLNode(name, attributes: attributes)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textCount += string.utf8.count
        guard textCount <= 4 * 1024 * 1024 else { parser.abortParsing(); return }
        stack.last?.text.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if let string = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard stack.count > 1 else { return }
        let node = stack.removeLast()
        if ["a", "text", "title", "creator", "navLabel", "span", "em", "strong", "b", "i"].contains(node.name) {
            stack.last?.text.append(node.text)
        }
    }
}
