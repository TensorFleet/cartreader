import Foundation

struct QuickAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case menu
        case page
        case letter
    }

    let id: String
    let title: String
    let value: String
    let kind: Kind
}

struct MenuParser {
    private static let menuPattern = try! NSRegularExpression(
        pattern: #"^\s*([0-6])\)\s*(.*?)\s*$"#
    )

    private(set) var actions: [QuickAction] = []
    private var lineBuffer = ""
    private var menuOptions: [(key: String, label: String)] = []

    mutating func consume(_ text: String) {
        // Swift treats CRLF as one extended grapheme cluster, so parse scalars to
        // preserve the firmware's line boundaries even when chunks contain "\r\n".
        for scalar in text.unicodeScalars {
            if scalar.value == 10 {
                handleLine(lineBuffer)
                lineBuffer.removeAll(keepingCapacity: true)
            } else if scalar.value != 13 {
                lineBuffer.unicodeScalars.append(scalar)
            }
            if lineBuffer.unicodeScalars.count > 500 {
                lineBuffer.removeAll(keepingCapacity: true)
            }
        }
    }

    private mutating func handleLine(_ line: String) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = Self.menuPattern.firstMatch(in: line, range: range),
           let keyRange = Range(match.range(at: 1), in: line),
           let labelRange = Range(match.range(at: 2), in: line) {
            let key = String(line[keyRange])
            let label = String(line[labelRange])
            guard !label.isEmpty else { return }

            if key == "0" {
                menuOptions.removeAll(keepingCapacity: true)
            }
            menuOptions.removeAll { $0.key == key }
            menuOptions.append((key, label))
            rebuildMenuActions()
            return
        }

        if line.lowercased().hasPrefix("enter first letter") {
            actions = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { character in
                let value = String(character)
                return QuickAction(id: "letter-\(value)", title: value, value: value, kind: .letter)
            }
        }
    }

    private mutating func rebuildMenuActions() {
        actions = menuOptions.map { option in
            QuickAction(
                id: "menu-\(option.key)",
                title: "\(option.key)  \(option.label)",
                value: option.key,
                kind: .menu
            )
        }
        if !menuOptions.isEmpty {
            actions.append(QuickAction(id: "page-up", title: "▲ page (u)", value: "u", kind: .page))
            actions.append(QuickAction(id: "page-down", title: "▼ page (d)", value: "d", kind: .page))
        }
    }
}
