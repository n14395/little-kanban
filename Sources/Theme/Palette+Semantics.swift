import SwiftUI

extension Palette {
    private var isDarkScheme: Bool { colorScheme == .dark }

    /// The dot beside a card's metadata row.
    func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: accent
        case .medium: isDarkScheme ? Color(hex: 0xE0A83A) : Color(hex: 0xC98A16)
        case .low: isDarkScheme ? ink(0.38) : Color(hex: 0xB4AEA4)
        }
    }

    /// The due chip's colours. Completed work reads green regardless of date;
    /// otherwise "Today" is urgent, the near days are warm, everything else is
    /// neutral ink.
    func dueTone(due: String, columnID: BoardColumn.ID) -> (background: Color, foreground: Color) {
        if columnID == BoardColumn.done.id {
            return isDarkScheme
                ? (Color(hex: 0x50BEAA, opacity: 0.16), Color(hex: 0x8FD9C8))
                : (Color(hex: 0x1F6F63, opacity: 0.12), Color(hex: 0x175A50))
        }
        if due == "Today" {
            return isDarkScheme
                ? (Color(hex: 0xF05A5A, opacity: 0.18), Color(hex: 0xF3A3A3))
                : (Color(hex: 0xBE2828, opacity: 0.12), Color(hex: 0xA32222))
        }
        if due == "Thu" || due == "Fri" {
            return isDarkScheme
                ? (Color(hex: 0xE6AF3C, opacity: 0.18), Color(hex: 0xEFCB84))
                : (Color(hex: 0xC98A16, opacity: 0.16), Color(hex: 0x8A5D06))
        }
        return (ink(0.06), ink(0.55))
    }
}
