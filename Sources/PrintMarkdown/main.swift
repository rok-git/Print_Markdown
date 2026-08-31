import AppKit
import CoreText
import Foundation

enum PrintColorMode: String {
    case auto
    case color
    case monochrome

    var lpOptions: [String] {
        switch self {
        case .auto:
            return []
        case .color:
            return ["print-color-mode=color", "ColorModel=RGB"]
        case .monochrome:
            return ["print-color-mode=monochrome", "ColorModel=Gray"]
        }
    }
}

enum PrintSides: String {
    case auto
    case oneSided = "one-sided"
    case longEdge = "two-sided-long-edge"
    case shortEdge = "two-sided-short-edge"

    var lpOption: String? {
        switch self {
        case .auto:
            return nil
        case .oneSided:
            return "sides=one-sided"
        case .longEdge:
            return "sides=two-sided-long-edge"
        case .shortEdge:
            return "sides=two-sided-short-edge"
        }
    }
}

enum PaperSize: String {
    case a4 = "A4"
    case letter = "Letter"
    case b5 = "B5"

    var size: NSSize {
        switch self {
        case .a4:
            return NSSize(width: 595.28, height: 841.89)
        case .letter:
            return NSSize(width: 612, height: 792)
        case .b5:
            return NSSize(width: 515.91, height: 728.50)
        }
    }
}

enum Orientation: String {
    case portrait
    case landscape
}

enum Theme: String {
    case clean
    case serif
    case compact
}

struct Options {
    var inputMarkdown: URL?
    var outputPDF: URL?
    var outputDirectory: URL?
    var keepHTML: URL?
    var title: String?
    var printer: String?
    var printOptions: [String] = []
    var colorMode = PrintColorMode.auto
    var sides = PrintSides.auto
    var paperSize = PaperSize.a4
    var orientation = Orientation.portrait
    var theme = Theme.clean
    var fontSize: CGFloat = 13
    var margin: CGFloat = 46
    var shouldPrint = false
    var dryRun = false
}

struct RenderedMarkdown {
    let html: String
    let temporaryFiles: [URL]
}

enum AppError: Error, CustomStringConvertible {
    case usage(String)
    case missingInput
    case unreadableMarkdown(String)
    case invalidMarkdownEncoding(String)
    case cannotWriteOutput(String)
    case renderFailed(String)
    case printFailed(Int32, String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .missingInput:
            return "Input Markdown file is required."
        case .unreadableMarkdown(let path):
            return "Could not read Markdown file: \(path)"
        case .invalidMarkdownEncoding(let path):
            return "Markdown file is not valid UTF-8: \(path)"
        case .cannotWriteOutput(let path):
            return "Could not write output: \(path)"
        case .renderFailed(let message):
            return "Could not render PDF: \(message)"
        case .printFailed(let status, let output):
            return "Print command failed with status \(status).\n\(output)"
        }
    }
}

func printUsage() {
    let text = """
    Usage:
      print-markdown INPUT.md [options]

    Options:
      --output PATH             Save the formatted PDF at PATH
      --output-dir DIR          Save as DIR/INPUT.formatted.pdf
      --print                   Send the formatted PDF to lp
      --printer NAME            Printer name passed to lp -d
      --print-option OPTION     Printer option passed as lp -o OPTION. Repeatable
      --color MODE              auto, color, monochrome. Default: auto
      --sides MODE              auto, one-sided, two-sided-long-edge, two-sided-short-edge
      --paper SIZE              A4, Letter, B5. Default: A4
      --orientation MODE        portrait, landscape. Default: portrait
      --theme NAME              clean, serif, compact. Default: clean
      --font-size POINTS        Base font size. Default: 13
      --margin POINTS           Page margin. Default: 46
      --title TEXT              Override document title
      --keep-html PATH          Also save the generated HTML
      --dry-run                 Create the PDF but do not print
      --help                    Show this help
    """
    FileHandle.standardOutput.write(Data(text.utf8))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1

    while index < arguments.count {
        let argument = arguments[index]

        if argument == "--help" || argument == "-h" {
            printUsage()
            exit(0)
        } else if argument == "--dry-run" {
            options.dryRun = true
        } else if argument == "--print" {
            options.shouldPrint = true
        } else if argument.hasPrefix("--") {
            guard index + 1 < arguments.count else {
                throw AppError.usage("Missing value for \(argument).")
            }
            let value = arguments[index + 1]
            index += 1

            switch argument {
            case "--output":
                options.outputPDF = URL(fileURLWithPath: value)
            case "--output-dir":
                options.outputDirectory = URL(fileURLWithPath: value, isDirectory: true)
            case "--printer":
                options.printer = value
            case "--print-option":
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AppError.usage("Print option must not be empty.")
                }
                options.printOptions.append(value)
            case "--color":
                guard let colorMode = PrintColorMode(rawValue: value) else {
                    throw AppError.usage("Unknown color mode: \(value)")
                }
                options.colorMode = colorMode
            case "--sides":
                guard let sides = PrintSides(rawValue: value) else {
                    throw AppError.usage("Unknown sides mode: \(value)")
                }
                options.sides = sides
            case "--paper":
                guard let paperSize = PaperSize(rawValue: value) else {
                    throw AppError.usage("Unknown paper size: \(value)")
                }
                options.paperSize = paperSize
            case "--orientation":
                guard let orientation = Orientation(rawValue: value) else {
                    throw AppError.usage("Unknown orientation: \(value)")
                }
                options.orientation = orientation
            case "--theme":
                guard let theme = Theme(rawValue: value) else {
                    throw AppError.usage("Unknown theme: \(value)")
                }
                options.theme = theme
            case "--font-size":
                guard let fontSize = Double(value), fontSize > 0 else {
                    throw AppError.usage("Font size must be greater than zero.")
                }
                options.fontSize = CGFloat(fontSize)
            case "--margin":
                guard let margin = Double(value), margin >= 0 else {
                    throw AppError.usage("Margin must be zero or greater.")
                }
                options.margin = CGFloat(margin)
            case "--title":
                options.title = value
            case "--keep-html":
                options.keepHTML = URL(fileURLWithPath: value)
            default:
                throw AppError.usage("Unknown option: \(argument)")
            }
        } else if options.inputMarkdown == nil {
            options.inputMarkdown = URL(fileURLWithPath: argument)
        } else {
            throw AppError.usage("Unexpected argument: \(argument)")
        }

        index += 1
    }

    if options.outputPDF != nil && options.outputDirectory != nil {
        throw AppError.usage("Use either --output or --output-dir, not both.")
    }

    return options
}

func htmlEscape(_ value: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(value.count)
    for character in value {
        switch character {
        case "&":
            escaped += "&amp;"
        case "<":
            escaped += "&lt;"
        case ">":
            escaped += "&gt;"
        case "\"":
            escaped += "&quot;"
        default:
            escaped.append(character)
        }
    }
    return escaped
}

func attributeEscape(_ value: String) -> String {
    htmlEscape(value).replacingOccurrences(of: "'", with: "&#39;")
}

func findClosing(_ needle: String, in text: String, from start: String.Index) -> String.Index? {
    text.range(of: needle, range: start..<text.endIndex)?.lowerBound
}

func renderInline(_ text: String) -> String {
    var html = ""
    var index = text.startIndex

    while index < text.endIndex {
        if text[index] == "`" {
            let next = text.index(after: index)
            if let end = findClosing("`", in: text, from: next) {
                html += "<code>\(htmlEscape(String(text[next..<end])))</code>"
                index = text.index(after: end)
                continue
            }
        }

        if text[index...].hasPrefix("![") {
            let altStart = text.index(index, offsetBy: 2)
            if let altEnd = findClosing("](", in: text, from: altStart) {
                let urlStart = text.index(altEnd, offsetBy: 2)
                if let urlEnd = findClosing(")", in: text, from: urlStart) {
                    let alt = String(text[altStart..<altEnd])
                    let url = String(text[urlStart..<urlEnd])
                    html += "<img src=\"\(attributeEscape(url))\" alt=\"\(attributeEscape(alt))\">"
                    index = text.index(after: urlEnd)
                    continue
                }
            }
        }

        if text[index] == "[" {
            let labelStart = text.index(after: index)
            if let labelEnd = findClosing("](", in: text, from: labelStart) {
                let urlStart = text.index(labelEnd, offsetBy: 2)
                if let urlEnd = findClosing(")", in: text, from: urlStart) {
                    let label = String(text[labelStart..<labelEnd])
                    let url = String(text[urlStart..<urlEnd])
                    html += "<a href=\"\(attributeEscape(url))\">\(renderInline(label))</a>"
                    index = text.index(after: urlEnd)
                    continue
                }
            }
        }

        if text[index...].hasPrefix("**") {
            let contentStart = text.index(index, offsetBy: 2)
            if let end = findClosing("**", in: text, from: contentStart) {
                html += "<strong>\(renderInline(String(text[contentStart..<end])))</strong>"
                index = text.index(end, offsetBy: 2)
                continue
            }
        }

        if text[index] == "*" {
            let contentStart = text.index(after: index)
            if let end = findClosing("*", in: text, from: contentStart) {
                html += "<em>\(renderInline(String(text[contentStart..<end])))</em>"
                index = text.index(after: end)
                continue
            }
        }

        html += htmlEscape(String(text[index]))
        index = text.index(after: index)
    }

    return html
}

func leadingHashCount(_ line: String) -> Int {
    var count = 0
    for character in line {
        if character == "#" && count < 6 {
            count += 1
        } else {
            break
        }
    }
    return count
}

func unorderedListText(_ trimmed: String) -> String? {
    for prefix in ["- ", "* ", "+ "] {
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
    }
    return nil
}

func orderedListText(_ trimmed: String) -> String? {
    var digits = ""
    var index = trimmed.startIndex
    while index < trimmed.endIndex, trimmed[index].isNumber {
        digits.append(trimmed[index])
        index = trimmed.index(after: index)
    }
    guard !digits.isEmpty, index < trimmed.endIndex, trimmed[index] == "." else {
        return nil
    }
    let afterPeriod = trimmed.index(after: index)
    guard afterPeriod < trimmed.endIndex, trimmed[afterPeriod] == " " else {
        return nil
    }
    return String(trimmed[trimmed.index(after: afterPeriod)...])
}

func isHorizontalRule(_ trimmed: String) -> Bool {
    guard trimmed.count >= 3 else {
        return false
    }
    let characters = Set(trimmed)
    return characters == ["-"] || characters == ["*"] || characters == ["_"]
}

func tableCells(_ line: String) -> [String]? {
    guard line.contains("|") else {
        return nil
    }
    var value = line.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("|") {
        value.removeFirst()
    }
    if value.hasSuffix("|") {
        value.removeLast()
    }
    return value.split(separator: "|", omittingEmptySubsequences: false).map {
        String($0).trimmingCharacters(in: .whitespaces)
    }
}

func isTableSeparator(_ line: String) -> Bool {
    guard let cells = tableCells(line), !cells.isEmpty else {
        return false
    }
    return cells.allSatisfy { cell in
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            return false
        }
        return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
    }
}

func isBlockStart(_ line: String, nextLine: String?) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed.hasPrefix("```") || trimmed.hasPrefix(">") || isHorizontalRule(trimmed) {
        return true
    }
    if unorderedListText(trimmed) != nil || orderedListText(trimmed) != nil {
        return true
    }
    let hashes = leadingHashCount(trimmed)
    if hashes > 0 {
        let afterHashes = trimmed.index(trimmed.startIndex, offsetBy: hashes)
        if afterHashes < trimmed.endIndex, trimmed[afterHashes] == " " {
            return true
        }
    }
    if let nextLine, tableCells(trimmed) != nil, isTableSeparator(nextLine) {
        return true
    }
    return false
}

func tableTextAttributes(font: NSFont, color: NSColor = NSColor(red: 0.12, green: 0.16, blue: 0.21, alpha: 1)) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineSpacing = 1
    return [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle
    ]
}

func measuredTextSize(_ text: String, font: NSFont, constrainedTo width: CGFloat? = nil) -> CGSize {
    let attributed = NSAttributedString(string: text, attributes: tableTextAttributes(font: font))
    let measuringSize = CGSize(width: width ?? CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    let rect = attributed.boundingRect(
        with: measuringSize,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return CGSize(width: ceil(rect.width), height: ceil(rect.height))
}

func writeTableImage(headers: [String], rows: [[String]], options: Options) throws -> URL {
    let columnCount = headers.count
    let pageContentWidth = max(120, pageSize(for: options).width - options.margin * 2)
    let fontSize = max(8, options.fontSize * 0.92)
    let bodyFont = NSFont.systemFont(ofSize: fontSize)
    let headerFont = NSFont.boldSystemFont(ofSize: fontSize)
    let horizontalPadding: CGFloat = 8
    let verticalPadding: CGFloat = 7
    let minimumColumnWidth: CGFloat = 46

    var naturalWidths = Array(repeating: minimumColumnWidth, count: columnCount)
    for columnIndex in 0..<columnCount {
        let headerSize = measuredTextSize(headers[columnIndex], font: headerFont)
        naturalWidths[columnIndex] = max(naturalWidths[columnIndex], headerSize.width + horizontalPadding * 2)
        for row in rows {
            let cell = columnIndex < row.count ? row[columnIndex] : ""
            let cellSize = measuredTextSize(cell, font: bodyFont)
            naturalWidths[columnIndex] = max(naturalWidths[columnIndex], cellSize.width + horizontalPadding * 2)
        }
    }

    let naturalTotalWidth = naturalWidths.reduce(0, +)
    let widthScale = naturalTotalWidth > pageContentWidth ? pageContentWidth / naturalTotalWidth : 1
    let columnWidths = naturalWidths.map { max(minimumColumnWidth, floor($0 * widthScale)) }
    let imageWidth = ceil(columnWidths.reduce(0, +)) + 1

    func rowHeight(cells: [String], font: NSFont) -> CGFloat {
        var height: CGFloat = 0
        for columnIndex in 0..<columnCount {
            let cell = columnIndex < cells.count ? cells[columnIndex] : ""
            let textWidth = max(12, columnWidths[columnIndex] - horizontalPadding * 2)
            height = max(height, measuredTextSize(cell, font: font, constrainedTo: textWidth).height)
        }
        return max(ceil(font.pointSize * 2.0), ceil(height + verticalPadding * 2))
    }

    var rowHeights: [CGFloat] = [rowHeight(cells: headers, font: headerFont)]
    rowHeights.append(contentsOf: rows.map { rowHeight(cells: $0, font: bodyFont) })
    let imageHeight = ceil(rowHeights.reduce(0, +)) + 1

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(imageWidth * 2),
        pixelsHigh: Int(imageHeight * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw AppError.renderFailed("could not create table bitmap.")
    }
    bitmap.size = NSSize(width: imageWidth, height: imageHeight)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw AppError.renderFailed("could not create table graphics context.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    NSColor.white.setFill()
    CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight).fill()

    let borderColor = NSColor(red: 0.82, green: 0.86, blue: 0.91, alpha: 1)
    let headerFill = NSColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
    let alternateFill = NSColor(red: 0.98, green: 0.99, blue: 1, alpha: 1)
    var topOffset: CGFloat = 0
    let allRows = [headers] + rows

    for rowIndex in 0..<allRows.count {
        let cells = allRows[rowIndex]
        let rowH = rowHeights[rowIndex]
        let y = imageHeight - topOffset - rowH - 1
        let fillColor: NSColor = rowIndex == 0 ? headerFill : (rowIndex.isMultiple(of: 2) ? alternateFill : .white)
        fillColor.setFill()
        CGRect(x: 0, y: y, width: imageWidth, height: rowH).fill()

        var x: CGFloat = 0
        for columnIndex in 0..<columnCount {
            let columnWidth = columnWidths[columnIndex]
            let cellRect = CGRect(x: x, y: y, width: columnWidth, height: rowH)
            borderColor.setStroke()
            NSBezierPath(rect: cellRect).stroke()

            let text = columnIndex < cells.count ? cells[columnIndex] : ""
            let font = rowIndex == 0 ? headerFont : bodyFont
            let attributes = tableTextAttributes(font: font)
            let textRect = cellRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
            NSAttributedString(string: text, attributes: attributes).draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            x += columnWidth
        }

        topOffset += rowH
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw AppError.renderFailed("could not encode table image.")
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("print-markdown-tables", isDirectory: true)
    let outputURL = directory.appendingPathComponent("\(UUID().uuidString).png")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)
    } catch {
        throw AppError.cannotWriteOutput(outputURL.path)
    }
    return outputURL
}

func renderMarkdown(_ markdown: String, options: Options) throws -> RenderedMarkdown {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var htmlParts: [String] = []
    var temporaryFiles: [URL] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            index += 1
            continue
        }

        if trimmed.hasPrefix("```") {
            let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            index += 1
            var codeLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeLines.append(lines[index])
                index += 1
            }
            if index < lines.count {
                index += 1
            }
            let className = language.isEmpty ? "" : " class=\"language-\(attributeEscape(language))\""
            htmlParts.append("<pre><code\(className)>\(htmlEscape(codeLines.joined(separator: "\n")))</code></pre>")
            continue
        }

        let hashCount = leadingHashCount(trimmed)
        if hashCount > 0 {
            let afterHashes = trimmed.index(trimmed.startIndex, offsetBy: hashCount)
            if afterHashes < trimmed.endIndex, trimmed[afterHashes] == " " {
                let contentStart = trimmed.index(after: afterHashes)
                let content = String(trimmed[contentStart...])
                htmlParts.append("<h\(hashCount)>\(renderInline(content))</h\(hashCount)>")
                index += 1
                continue
            }
        }

        if isHorizontalRule(trimmed) {
            htmlParts.append("<hr>")
            index += 1
            continue
        }

        if let nextLine = index + 1 < lines.count ? lines[index + 1] : nil,
           let headers = tableCells(trimmed),
           isTableSeparator(nextLine) {
            index += 2
            var rows: [[String]] = []
            while index < lines.count, tableCells(lines[index]) != nil, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(tableCells(lines[index]) ?? [])
                index += 1
            }
            let tableImageURL = try writeTableImage(headers: headers, rows: rows, options: options)
            temporaryFiles.append(tableImageURL)
            htmlParts.append("<p><img class=\"table-image\" src=\"\(attributeEscape(tableImageURL.absoluteString))\" alt=\"Markdown table\"></p>")
            continue
        }

        if trimmed.hasPrefix(">") {
            var quoteLines: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard current.hasPrefix(">") else {
                    break
                }
                quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
            }
            htmlParts.append("<blockquote>\(quoteLines.map(renderInline).joined(separator: "<br>"))</blockquote>")
            continue
        }

        if unorderedListText(trimmed) != nil {
            var items: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard let item = unorderedListText(current) else {
                    break
                }
                items.append(item)
                index += 1
            }
            let renderedItems = items.map {
                "<p class=\"list-item\">&bull;&nbsp;&nbsp;\(renderInline($0))</p>"
            }
            htmlParts.append(renderedItems.joined(separator: "\n"))
            continue
        }

        if orderedListText(trimmed) != nil {
            var items: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard let item = orderedListText(current) else {
                    break
                }
                items.append(item)
                index += 1
            }
            let renderedItems = items.enumerated().map { itemIndex, item in
                "<p class=\"list-item\">\(itemIndex + 1).&nbsp;&nbsp;\(renderInline(item))</p>"
            }
            htmlParts.append(renderedItems.joined(separator: "\n"))
            continue
        }

        var paragraphLines = [trimmed]
        index += 1
        while index < lines.count {
            let next = lines[index]
            let nextLine = index + 1 < lines.count ? lines[index + 1] : nil
            if isBlockStart(next, nextLine: nextLine) {
                break
            }
            paragraphLines.append(next.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        htmlParts.append("<p>\(renderInline(paragraphLines.joined(separator: " ")))</p>")
    }

    return RenderedMarkdown(html: htmlParts.joined(separator: "\n"), temporaryFiles: temporaryFiles)
}

func css(for options: Options) -> String {
    let bodyFont: String
    let lineHeight: String
    let paragraphMargin: String
    let codeSize: CGFloat

    switch options.theme {
    case .clean:
        bodyFont = "-apple-system, BlinkMacSystemFont, \"Hiragino Sans\", \"Yu Gothic\", \"Noto Sans CJK JP\", sans-serif"
        lineHeight = "1.64"
        paragraphMargin = "0 0 0.82rem"
        codeSize = options.fontSize * 0.9
    case .serif:
        bodyFont = "\"Hiragino Mincho ProN\", \"Yu Mincho\", \"Times New Roman\", serif"
        lineHeight = "1.72"
        paragraphMargin = "0 0 0.9rem"
        codeSize = options.fontSize * 0.88
    case .compact:
        bodyFont = "-apple-system, BlinkMacSystemFont, \"Hiragino Sans\", \"Yu Gothic\", sans-serif"
        lineHeight = "1.48"
        paragraphMargin = "0 0 0.55rem"
        codeSize = options.fontSize * 0.88
    }

    return """
    @page {
      margin: \(options.margin)pt;
    }
    * {
      box-sizing: border-box;
    }
    html {
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    body {
      margin: 0;
      color: #1f2933;
      background: white;
      font-family: \(bodyFont);
      font-size: \(options.fontSize)pt;
      line-height: \(lineHeight);
    }
    h1, h2, h3, h4, h5, h6 {
      color: #111827;
      line-height: 1.25;
      margin: 1.1rem 0 0.45rem;
      page-break-after: avoid;
      break-after: avoid;
    }
    h1 {
      font-size: 2rem;
      border-bottom: 2px solid #e5e7eb;
      padding-bottom: 0.28rem;
      margin-top: 0;
    }
    h2 {
      font-size: 1.45rem;
      border-bottom: 1px solid #e5e7eb;
      padding-bottom: 0.18rem;
    }
    h3 { font-size: 1.18rem; }
    h4, h5, h6 { font-size: 1rem; }
    p {
      margin: \(paragraphMargin);
      orphans: 3;
      widows: 3;
    }
    a {
      color: #0f5f8f;
      text-decoration: none;
      border-bottom: 0.5px solid rgba(15, 95, 143, 0.35);
    }
    p.list-item {
      margin: 0.12rem 0 0.12rem 1.35rem;
      text-indent: -1.35rem;
    }
    blockquote {
      margin: 0.75rem 0 0.9rem;
      padding: 0.45rem 0 0.45rem 0.8rem;
      border-left: 3px solid #94a3b8;
      color: #475569;
      background: #f8fafc;
    }
    code {
      font-family: "SFMono-Regular", Menlo, Consolas, "Liberation Mono", monospace;
      font-size: \(codeSize)pt;
      background: #f3f4f6;
      color: #111827;
      padding: 0.08rem 0.22rem;
      border-radius: 3px;
    }
    pre {
      margin: 0.8rem 0 1rem;
      padding: 0.75rem 0.85rem;
      background: #f6f8fa;
      border: 1px solid #e5e7eb;
      border-radius: 6px;
      overflow-wrap: break-word;
      white-space: pre-wrap;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    pre code {
      display: block;
      padding: 0;
      background: transparent;
      border-radius: 0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 0.85rem 0 1rem;
      font-size: 0.94em;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    th, td {
      border: 1px solid #d8dee9;
      padding: 0.34rem 0.45rem;
      text-align: left;
      vertical-align: top;
    }
    th {
      background: #eef2f7;
      color: #111827;
      font-weight: 700;
    }
    tr:nth-child(even) td {
      background: #fafbfc;
    }
    img {
      max-width: 100%;
      height: auto;
      display: block;
      margin: 0.7rem auto 1rem;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    hr {
      border: none;
      border-top: 1px solid #d8dee9;
      margin: 1.15rem 0;
    }
    """
}

func documentTitle(for inputURL: URL, options: Options) -> String {
    options.title ?? inputURL.deletingPathExtension().lastPathComponent
}

func htmlDocument(markdown: String, inputURL: URL, options: Options) throws -> RenderedMarkdown {
    let title = documentTitle(for: inputURL, options: options)
    let renderedMarkdown = try renderMarkdown(markdown, options: options)
    let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>\(htmlEscape(title))</title>
      <style>\(css(for: options))</style>
    </head>
    <body>
    \(renderedMarkdown.html)
    </body>
    </html>
    """
    return RenderedMarkdown(html: html, temporaryFiles: renderedMarkdown.temporaryFiles)
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case code(String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [MarkdownBlock] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            index += 1
            continue
        }

        if trimmed.hasPrefix("```") {
            index += 1
            var codeLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeLines.append(lines[index])
                index += 1
            }
            if index < lines.count {
                index += 1
            }
            blocks.append(.code(codeLines.joined(separator: "\n")))
            continue
        }

        let hashCount = leadingHashCount(trimmed)
        if hashCount > 0 {
            let afterHashes = trimmed.index(trimmed.startIndex, offsetBy: hashCount)
            if afterHashes < trimmed.endIndex, trimmed[afterHashes] == " " {
                let contentStart = trimmed.index(after: afterHashes)
                blocks.append(.heading(level: hashCount, text: String(trimmed[contentStart...])))
                index += 1
                continue
            }
        }

        if isHorizontalRule(trimmed) {
            blocks.append(.horizontalRule)
            index += 1
            continue
        }

        if let nextLine = index + 1 < lines.count ? lines[index + 1] : nil,
           let headers = tableCells(trimmed),
           isTableSeparator(nextLine) {
            index += 2
            var rows: [[String]] = []
            while index < lines.count, let row = tableCells(lines[index]), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(row)
                index += 1
            }
            blocks.append(.table(headers: headers, rows: rows))
            continue
        }

        if trimmed.hasPrefix(">") {
            var quoteLines: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard current.hasPrefix(">") else {
                    break
                }
                quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
            }
            blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
            continue
        }

        if unorderedListText(trimmed) != nil {
            var items: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard let item = unorderedListText(current) else {
                    break
                }
                items.append(item)
                index += 1
            }
            blocks.append(.unorderedList(items))
            continue
        }

        if orderedListText(trimmed) != nil {
            var items: [String] = []
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard let item = orderedListText(current) else {
                    break
                }
                items.append(item)
                index += 1
            }
            blocks.append(.orderedList(items))
            continue
        }

        var paragraphLines = [trimmed]
        index += 1
        while index < lines.count {
            let next = lines[index]
            let nextLine = index + 1 < lines.count ? lines[index + 1] : nil
            if isBlockStart(next, nextLine: nextLine) {
                break
            }
            paragraphLines.append(next.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
    }

    return blocks
}

func pageSize(for options: Options) -> NSSize {
    let size = options.paperSize.size
    switch options.orientation {
    case .portrait:
        return size
    case .landscape:
        return NSSize(width: size.height, height: size.width)
    }
}

func bodyFont(for options: Options) -> NSFont {
    switch options.theme {
    case .clean, .compact:
        return NSFont.systemFont(ofSize: options.fontSize)
    case .serif:
        return NSFont(name: "Hiragino Mincho ProN", size: options.fontSize) ?? NSFont.systemFont(ofSize: options.fontSize)
    }
}

func headingFont(level: Int, options: Options) -> NSFont {
    let multiplier: CGFloat
    switch level {
    case 1:
        multiplier = 2.0
    case 2:
        multiplier = 1.45
    case 3:
        multiplier = 1.18
    default:
        multiplier = 1.0
    }
    return NSFont.boldSystemFont(ofSize: options.fontSize * multiplier)
}

func textColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func paragraphStyle(lineHeightMultiple: CGFloat, alignment: NSTextAlignment = .left) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = lineHeightMultiple
    style.alignment = alignment
    return style
}

func attributedText(_ text: String, font: NSFont, color: NSColor, lineHeightMultiple: CGFloat = 1.45) -> NSAttributedString {
    NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle(lineHeightMultiple: lineHeightMultiple)
        ]
    )
}

func attributedInlineText(_ text: String, baseFont: NSFont, boldFont: NSFont, codeFont: NSFont, color: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var index = text.startIndex

    func append(_ value: String, font: NSFont, color: NSColor = color) {
        result.append(NSAttributedString(string: value, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle(lineHeightMultiple: 1.45)
        ]))
    }

    while index < text.endIndex {
        if text[index] == "`" {
            let next = text.index(after: index)
            if let end = findClosing("`", in: text, from: next) {
                append(String(text[next..<end]), font: codeFont)
                index = text.index(after: end)
                continue
            }
        }

        if text[index...].hasPrefix("**") {
            let contentStart = text.index(index, offsetBy: 2)
            if let end = findClosing("**", in: text, from: contentStart) {
                append(String(text[contentStart..<end]), font: boldFont)
                index = text.index(end, offsetBy: 2)
                continue
            }
        }

        if text[index] == "[" {
            let labelStart = text.index(after: index)
            if let labelEnd = findClosing("](", in: text, from: labelStart) {
                let urlStart = text.index(labelEnd, offsetBy: 2)
                if let urlEnd = findClosing(")", in: text, from: urlStart) {
                    append(String(text[labelStart..<labelEnd]), font: baseFont, color: textColor(15, 95, 143))
                    index = text.index(after: urlEnd)
                    continue
                }
            }
        }

        append(String(text[index]), font: baseFont)
        index = text.index(after: index)
    }

    return result
}

func textHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        nil,
        CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
        nil
    )
    return ceil(size.height)
}

func drawAttributed(_ attributed: NSAttributedString, in rect: CGRect, context: CGContext) {
    let path = CGMutablePath()
    path.addRect(rect)
    context.textMatrix = .identity
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
    CTFrameDraw(frame, context)
}

func tableLayout(headers: [String], rows: [[String]], options: Options, contentWidth: CGFloat) -> (columnWidths: [CGFloat], rowHeights: [CGFloat], totalHeight: CGFloat) {
    let columnCount = max(1, headers.count)
    let fontSize = max(8, options.fontSize * 0.92)
    let body = NSFont.systemFont(ofSize: fontSize)
    let header = NSFont.boldSystemFont(ofSize: fontSize)
    let horizontalPadding: CGFloat = 8
    let verticalPadding: CGFloat = 7
    let minimumColumnWidth: CGFloat = 46

    var naturalWidths = Array(repeating: minimumColumnWidth, count: columnCount)
    for columnIndex in 0..<columnCount {
        naturalWidths[columnIndex] = max(
            naturalWidths[columnIndex],
            measuredTextSize(headers[columnIndex], font: header).width + horizontalPadding * 2
        )
        for row in rows {
            let cell = columnIndex < row.count ? row[columnIndex] : ""
            naturalWidths[columnIndex] = max(
                naturalWidths[columnIndex],
                measuredTextSize(cell, font: body).width + horizontalPadding * 2
            )
        }
    }

    let naturalTotal = naturalWidths.reduce(0, +)
    let scale = naturalTotal > contentWidth ? contentWidth / naturalTotal : 1
    let columnWidths = naturalWidths.map { max(minimumColumnWidth, floor($0 * scale)) }

    func heightForRow(_ cells: [String], font: NSFont) -> CGFloat {
        var height: CGFloat = 0
        for columnIndex in 0..<columnCount {
            let cell = columnIndex < cells.count ? cells[columnIndex] : ""
            let width = max(12, columnWidths[columnIndex] - horizontalPadding * 2)
            height = max(height, measuredTextSize(cell, font: font, constrainedTo: width).height)
        }
        return ceil(height + verticalPadding * 2)
    }

    var rowHeights = [heightForRow(headers, font: header)]
    rowHeights.append(contentsOf: rows.map { heightForRow($0, font: body) })
    return (columnWidths, rowHeights, rowHeights.reduce(0, +))
}

func drawTable(headers: [String], rows: [[String]], atTopY topY: CGFloat, contentRect: CGRect, options: Options, context: CGContext) {
    let layout = tableLayout(headers: headers, rows: rows, options: options, contentWidth: contentRect.width)
    let allRows = [headers] + rows
    let fontSize = max(8, options.fontSize * 0.92)
    let body = NSFont.systemFont(ofSize: fontSize)
    let header = NSFont.boldSystemFont(ofSize: fontSize)
    let horizontalPadding: CGFloat = 8
    let verticalPadding: CGFloat = 5
    let headerFill = NSColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1).cgColor
    let alternateFill = NSColor(red: 0.98, green: 0.99, blue: 1, alpha: 1).cgColor
    let borderColor = NSColor(red: 0.82, green: 0.86, blue: 0.91, alpha: 1).cgColor
    var rowTop = topY

    for rowIndex in 0..<allRows.count {
        let rowHeight = layout.rowHeights[rowIndex]
        let rowRect = CGRect(x: contentRect.minX, y: rowTop - rowHeight, width: layout.columnWidths.reduce(0, +), height: rowHeight)
        context.setFillColor(rowIndex == 0 ? headerFill : (rowIndex.isMultiple(of: 2) ? alternateFill : NSColor.white.cgColor))
        context.fill(rowRect)

        var x = contentRect.minX
        for columnIndex in 0..<layout.columnWidths.count {
            let columnWidth = layout.columnWidths[columnIndex]
            let cellRect = CGRect(x: x, y: rowTop - rowHeight, width: columnWidth, height: rowHeight)
            context.setStrokeColor(borderColor)
            context.setLineWidth(0.8)
            context.stroke(cellRect)

            let cell = columnIndex < allRows[rowIndex].count ? allRows[rowIndex][columnIndex] : ""
            let font = rowIndex == 0 ? header : body
            let text = attributedText(cell, font: font, color: textColor(31, 41, 51), lineHeightMultiple: 1.25)
            let textRect = cellRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
            drawAttributed(text, in: textRect, context: context)
            x += columnWidth
        }
        rowTop -= rowHeight
    }
}

func attributedString(from html: String, baseURL: URL) throws -> NSAttributedString {
    let data = Data(html.utf8)
    let readingOptions: [NSAttributedString.DocumentReadingOptionKey: Any] = [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue,
        .baseURL: baseURL
    ]
    do {
        return try NSAttributedString(data: data, options: readingOptions, documentAttributes: nil)
    } catch {
        throw AppError.renderFailed(error.localizedDescription)
    }
}

func renderPDF(html: String, baseURL: URL, outputURL: URL, options: Options) throws {
    let attributedText = try attributedString(from: html, baseURL: baseURL)
    let pageSize = pageSize(for: options)
    let pageRect = CGRect(origin: .zero, size: pageSize)
    let contentRect = pageRect.insetBy(dx: options.margin, dy: options.margin)

    guard contentRect.width > 0, contentRect.height > 0 else {
        throw AppError.renderFailed("page margin is larger than the paper size.")
    }

    let outputData = NSMutableData()
    guard let consumer = CGDataConsumer(data: outputData as CFMutableData) else {
        throw AppError.renderFailed("could not create PDF data consumer.")
    }

    var mediaBox = pageRect
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw AppError.renderFailed("could not create PDF context.")
    }

    let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
    var textRange = CFRange(location: 0, length: 0)
    let textLength = attributedText.length

    repeat {
        context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)

        let path = CGMutablePath()
        path.addRect(contentRect)
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, textRange, path, nil)
        CTFrameDraw(frame, context)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        context.endPDFPage()

        guard visibleRange.length > 0 else {
            throw AppError.renderFailed("no text fit on the page; try a smaller margin or font size.")
        }
        textRange.location += visibleRange.length
    } while textRange.location < textLength

    context.closePDF()

    guard outputData.write(to: outputURL, atomically: true) else {
        throw AppError.cannotWriteOutput(outputURL.path)
    }
}

func renderPDF(blocks: [MarkdownBlock], outputURL: URL, options: Options) throws {
    let pageSize = pageSize(for: options)
    let pageRect = CGRect(origin: .zero, size: pageSize)
    let contentRect = pageRect.insetBy(dx: options.margin, dy: options.margin)

    guard contentRect.width > 0, contentRect.height > 0 else {
        throw AppError.renderFailed("page margin is larger than the paper size.")
    }

    let outputData = NSMutableData()
    guard let consumer = CGDataConsumer(data: outputData as CFMutableData) else {
        throw AppError.renderFailed("could not create PDF data consumer.")
    }

    var mediaBox = pageRect
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw AppError.renderFailed("could not create PDF context.")
    }

    let body = bodyFont(for: options)
    let bold = NSFont.boldSystemFont(ofSize: options.fontSize)
    let code = NSFont.monospacedSystemFont(ofSize: options.fontSize * 0.92, weight: .regular)
    let mainColor = textColor(31, 41, 51)
    var currentTopY = contentRect.maxY
    var pageIsOpen = false

    func beginPage() {
        context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)
        currentTopY = contentRect.maxY
        pageIsOpen = true
    }

    func endPageIfNeeded() {
        if pageIsOpen {
            context.endPDFPage()
            pageIsOpen = false
        }
    }

    func ensureSpace(_ height: CGFloat) {
        if !pageIsOpen {
            beginPage()
        } else if currentTopY - height < contentRect.minY {
            endPageIfNeeded()
            beginPage()
        }
    }

    func heightForTextRange(framesetter: CTFramesetter, range: CFRange) -> CGFloat {
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            range,
            nil,
            CGSize(width: contentRect.width, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        return ceil(size.height)
    }

    func drawTextBlock(_ text: NSAttributedString, spacingAfter: CGFloat, background: CGColor? = nil, leftRule: CGColor? = nil) throws {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var textRange = CFRange(location: 0, length: 0)

        while textRange.location < text.length {
            if !pageIsOpen {
                beginPage()
            }

            var availableHeight = currentTopY - contentRect.minY
            if availableHeight < options.fontSize * 2 {
                endPageIfNeeded()
                beginPage()
                availableHeight = currentTopY - contentRect.minY
            }

            let availableRect = CGRect(
                x: contentRect.minX,
                y: contentRect.minY,
                width: contentRect.width,
                height: availableHeight
            )
            let path = CGMutablePath()
            path.addRect(availableRect)
            context.textMatrix = .identity
            let frame = CTFramesetterCreateFrame(framesetter, textRange, path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)

            guard visibleRange.length > 0 else {
                throw AppError.renderFailed("text did not fit on the page; try a smaller margin or font size.")
            }

            let drawnHeight = min(availableHeight, max(options.fontSize, heightForTextRange(framesetter: framesetter, range: visibleRange)))
            let usedRect = CGRect(
                x: contentRect.minX,
                y: currentTopY - drawnHeight,
                width: contentRect.width,
                height: drawnHeight
            )

            if let background {
                context.setFillColor(background)
                context.fill(usedRect.insetBy(dx: -4, dy: -3))
            }
            if let leftRule {
                context.setFillColor(leftRule)
                context.fill(CGRect(x: contentRect.minX - 7, y: usedRect.minY - 3, width: 3, height: usedRect.height + 6))
            }

            CTFrameDraw(frame, context)
            textRange.location += visibleRange.length
            currentTopY -= drawnHeight

            if textRange.location < text.length {
                endPageIfNeeded()
            }
        }

        if currentTopY - spacingAfter < contentRect.minY {
            currentTopY = contentRect.minY
        } else {
            currentTopY -= spacingAfter
        }
    }

    for block in blocks {
        switch block {
        case .heading(let level, let text):
            let font = headingFont(level: level, options: options)
            let title = attributedInlineText(text, baseFont: font, boldFont: font, codeFont: code, color: textColor(17, 24, 39))
            let height = textHeight(title, width: contentRect.width)
            let spacingAfter: CGFloat = level == 1 ? 12 : 8
            ensureSpace(height + spacingAfter + (level <= 2 ? 4 : 0))
            let rect = CGRect(x: contentRect.minX, y: currentTopY - height, width: contentRect.width, height: height)
            drawAttributed(title, in: rect, context: context)
            currentTopY -= height
            if level <= 2 {
                context.setStrokeColor(NSColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1).cgColor)
                context.setLineWidth(level == 1 ? 1.2 : 0.8)
                context.move(to: CGPoint(x: contentRect.minX, y: currentTopY - 2))
                context.addLine(to: CGPoint(x: contentRect.maxX, y: currentTopY - 2))
                context.strokePath()
                currentTopY -= 4
            }
            currentTopY -= spacingAfter

        case .paragraph(let text):
            let paragraph = attributedInlineText(text, baseFont: body, boldFont: bold, codeFont: code, color: mainColor)
            try drawTextBlock(paragraph, spacingAfter: options.theme == .compact ? 6 : 10)

        case .unorderedList(let items):
            let text = items.map { "•  \($0)" }.joined(separator: "\n")
            try drawTextBlock(attributedInlineText(text, baseFont: body, boldFont: bold, codeFont: code, color: mainColor), spacingAfter: 8)

        case .orderedList(let items):
            let text = items.enumerated().map { "\($0.offset + 1).  \($0.element)" }.joined(separator: "\n")
            try drawTextBlock(attributedInlineText(text, baseFont: body, boldFont: bold, codeFont: code, color: mainColor), spacingAfter: 8)

        case .blockquote(let text):
            try drawTextBlock(
                attributedText(text, font: body, color: textColor(71, 85, 105), lineHeightMultiple: 1.45),
                spacingAfter: 10,
                background: NSColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1).cgColor,
                leftRule: NSColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1).cgColor
            )

        case .code(let text):
            try drawTextBlock(
                attributedText(text, font: code, color: textColor(17, 24, 39), lineHeightMultiple: 1.25),
                spacingAfter: 12,
                background: NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1).cgColor
            )

        case .table(let headers, let rows):
            let layout = tableLayout(headers: headers, rows: rows, options: options, contentWidth: contentRect.width)
            let totalHeight = layout.totalHeight + 14
            ensureSpace(totalHeight)
            drawTable(headers: headers, rows: rows, atTopY: currentTopY, contentRect: contentRect, options: options, context: context)
            currentTopY -= totalHeight

        case .horizontalRule:
            ensureSpace(18)
            context.setStrokeColor(NSColor(red: 0.85, green: 0.87, blue: 0.91, alpha: 1).cgColor)
            context.setLineWidth(0.8)
            context.move(to: CGPoint(x: contentRect.minX, y: currentTopY - 8))
            context.addLine(to: CGPoint(x: contentRect.maxX, y: currentTopY - 8))
            context.strokePath()
            currentTopY -= 18
        }
    }

    endPageIfNeeded()
    context.closePDF()

    guard outputData.write(to: outputURL, atomically: true) else {
        throw AppError.cannotWriteOutput(outputURL.path)
    }
}

func defaultOutputURL(inputURL: URL, options: Options) -> URL {
    if let outputPDF = options.outputPDF {
        return outputPDF
    }
    if let outputDirectory = options.outputDirectory {
        let basename = inputURL.deletingPathExtension().lastPathComponent + ".formatted.pdf"
        return outputDirectory.appendingPathComponent(basename)
    }
    return makeTemporaryOutputURL()
}

func makeTemporaryOutputURL() -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return directory.appendingPathComponent("print-markdown-\(UUID().uuidString).pdf")
}

func lpArguments(for pdfURL: URL, options: Options) -> [String] {
    var arguments: [String] = []
    if let printer = options.printer {
        arguments.append(contentsOf: ["-d", printer])
    }
    for colorOption in options.colorMode.lpOptions {
        arguments.append(contentsOf: ["-o", colorOption])
    }
    if let sidesOption = options.sides.lpOption {
        arguments.append(contentsOf: ["-o", sidesOption])
    }
    for printOption in options.printOptions {
        arguments.append(contentsOf: ["-o", printOption])
    }
    arguments.append(pdfURL.path)
    return arguments
}

func printPDF(_ pdfURL: URL, options: Options) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
    process.arguments = lpArguments(for: pdfURL, options: options)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
        throw AppError.printFailed(process.terminationStatus, output)
    }

    FileHandle.standardOutput.write(Data(output.utf8))
}

func writeString(_ value: String, to url: URL) throws {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        throw AppError.cannotWriteOutput(url.path)
    }
}

func run() throws {
    let options = try parseOptions(CommandLine.arguments)
    guard let inputURL = options.inputMarkdown else {
        throw AppError.missingInput
    }

    if options.outputPDF == nil && options.outputDirectory == nil && !options.shouldPrint && !options.dryRun {
        throw AppError.usage("Specify --output or --output-dir to save the formatted PDF, or --print to print it.")
    }

    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw AppError.unreadableMarkdown(inputURL.path)
    }
    let inputData: Data
    do {
        inputData = try Data(contentsOf: inputURL)
    } catch {
        throw AppError.unreadableMarkdown(inputURL.path)
    }
    guard let markdown = String(data: inputData, encoding: .utf8) else {
        throw AppError.invalidMarkdownEncoding(inputURL.path)
    }

    if let keepHTML = options.keepHTML {
        let renderedDocument = try htmlDocument(markdown: markdown, inputURL: inputURL, options: options)
        try writeString(renderedDocument.html, to: keepHTML)
    }

    let blocks = parseMarkdownBlocks(markdown)
    let outputURL = defaultOutputURL(inputURL: inputURL, options: options)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try renderPDF(blocks: blocks, outputURL: outputURL, options: options)

    if options.dryRun || !options.shouldPrint {
        print("Formatted PDF created: \(outputURL.path)")
        return
    }

    try printPDF(outputURL, options: options)

    if options.outputPDF == nil && options.outputDirectory == nil {
        try? FileManager.default.removeItem(at: outputURL)
    }
}

do {
    try run()
} catch let error as AppError {
    FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
    FileHandle.standardError.write(Data("Run with --help for usage.\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
