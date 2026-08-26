#!/usr/bin/env python3
"""Write the Nerd Font icons into Panel.qml as escapes.

The glyphs live in Supplementary Private Use Area A, which does not survive
every editor and clipboard on the way into the file. Spelling them as surrogate
escapes keeps Panel.qml plain ASCII and the icons intact. Every codepoint here
was checked against the installed font with `fc-list :charset=...`.
"""
import os
import re

PANEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Panel.qml")

ICONS = {
    "youtube": 0xF05C3,    # md-youtube
    "twitch": 0xF0543,     # md-twitch
    "bell": 0xF009A,       # md-bell
    "tower": 0xF071D,      # md-radio-tower
    "close": 0xF0156,      # md-close
}


def escape(codepoint):
    """QML string literal for one codepoint, as a UTF-16 surrogate pair."""
    offset = codepoint - 0x10000
    return "\\u%04x\\u%04x" % (0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF))


REPLACEMENTS = [
    # itemIcon(): Twitch streams get the Twitch mark, uploads the YouTube one.
    ('return String((item || {}).kind) === "twitch" ? "" : ""',
     'return String((item || {}).kind) === "twitch" ? "%s" : "%s"'
     % (escape(ICONS["twitch"]), escape(ICONS["youtube"]))),
    # barText(): a tower while something is live, a bell for unread arrivals.
    ('if (monitor.liveCount > 0) return " " + monitor.liveCount',
     'if (monitor.liveCount > 0) return "%s " + monitor.liveCount' % escape(ICONS["tower"])),
    ('if (monitor.unseenCount > 0) return " " + monitor.unseenCount',
     'if (monitor.unseenCount > 0) return "%s " + monitor.unseenCount' % escape(ICONS["bell"])),
    # Panel hero.
    ('                text: ""\n                color: root.monitor && root.monitor.liveCount > 0',
     '                text: root.monitor && root.monitor.liveCount > 0 ? "%s" : "%s"\n'
     '                color: root.monitor && root.monitor.liveCount > 0'
     % (escape(ICONS["tower"]), escape(ICONS["bell"]))),
    # Connect Twitch button.
    ('                    ? "Waiting for approval…" : "Connect Twitch"\n                  iconText: ""',
     '                    ? "Waiting for approval…" : "Connect Twitch"\n'
     '                  iconText: "%s"' % escape(ICONS["twitch"])),
    # Close-the-player button.
    ('                iconText: ""\n                bordered: true\n                foreground: root.urgent',
     '                iconText: "%s"\n                bordered: true\n                foreground: root.urgent'
     % escape(ICONS["close"])),
    # Chime test buttons.
    ('                text: "Test YouTube"\n                iconText: ""',
     '                text: "Test YouTube"\n                iconText: "%s"' % escape(ICONS["youtube"])),
    ('                text: "Test Twitch"\n                iconText: ""',
     '                text: "Test Twitch"\n                iconText: "%s"' % escape(ICONS["twitch"])),
]

if __name__ == "__main__":
    with open(PANEL, "r", encoding="utf-8") as handle:
        source = handle.read()
    missed = []
    for needle, replacement in REPLACEMENTS:
        if needle not in source:
            missed.append(needle.splitlines()[0][:60])
            continue
        source = source.replace(needle, replacement, 1)
    with open(PANEL, "w", encoding="utf-8") as handle:
        handle.write(source)
    leftover = len(re.findall(r'(?:text|iconText): ""', source))
    print("patched %d of %d" % (len(REPLACEMENTS) - len(missed), len(REPLACEMENTS)))
    for line in missed:
        print("  MISSED:", line)
    print("empty icon slots left:", leftover)
