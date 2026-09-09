"""Check the plugin's persistent notification launch arguments offline."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NotificationTests(unittest.TestCase):
    def notification_args(self, action, url="https://example.com/watch?v=1&x=2"):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "notify-send"
            capture = Path(directory) / "arguments"
            stub.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$NOTIFY_CAPTURE"\n')
            stub.chmod(0o755)
            subprocess.run(
                [str(ROOT / "creators-notify"), "--title", 'Creator "live"',
                 "--url", url, "--default", action,
                 "--pip-position", "top-left", "--pip-size", "large"],
                env={**os.environ, "PATH": directory + ":" + os.environ["PATH"],
                     "NOTIFY_CAPTURE": str(capture)},
                capture_output=True, check=True,
            )
            return capture.read_bytes().decode().split("\0")[:-1]

    def command(self, action):
        prefix = "--hint=string:omarchy-exec-argv:"
        hints = [arg[len(prefix):] for arg in self.notification_args(action)
                 if arg.startswith(prefix)]
        self.assertEqual(len(hints), 1)
        return json.loads(hints[0])

    def test_browser_click_has_persistent_command(self):
        self.assertEqual(self.command("browser"),
                         ["omarchy-launch-browser", "https://example.com/watch?v=1&x=2"])

    def test_pip_click_preserves_settings_and_title(self):
        self.assertEqual(self.command("pip"),
                         [str(ROOT / "creators-pip"), "open",
                          "https://example.com/watch?v=1&x=2", "--title", 'Creator "live"',
                          "--position", "top-left", "--size", "large"])

    def test_disabled_or_missing_url_has_no_persistent_command(self):
        for action, url in [("none", "https://example.com"), ("browser", "")]:
            self.assertFalse(any("omarchy-exec-argv" in arg
                                 for arg in self.notification_args(action, url)))


if __name__ == "__main__":
    unittest.main()
