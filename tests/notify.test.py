"""Check the plugin's persistent notification launch arguments offline."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NotificationTests(unittest.TestCase):
    def notification_result(self, action, url="https://example.com/watch?v=1&x=2",
                            native=True, chosen=""):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "notify-send"
            capture = Path(directory) / "arguments"
            opened = Path(directory) / "opened"
            stub.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$NOTIFY_CAPTURE"\n'
                            'printf "%s" "$NOTIFY_CHOSEN"\n')
            stub.chmod(0o755)
            shell = Path(directory) / "omarchy-shell"
            shell.write_text('#!/bin/bash\n[[ $NOTIFY_NATIVE == 1 ]] && echo ok\n')
            shell.chmod(0o755)
            browser = Path(directory) / "omarchy-launch-browser"
            browser.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$OPEN_CAPTURE"\n')
            browser.chmod(0o755)
            subprocess.run(
                [str(ROOT / "creators-notify"), "--title", 'Creator "live"',
                 "--url", url, "--default", action,
                 "--pip-position", "top-left", "--pip-size", "large"],
                env={**os.environ, "PATH": directory + ":" + os.environ["PATH"],
                     "NOTIFY_CAPTURE": str(capture), "OPEN_CAPTURE": str(opened),
                     "NOTIFY_NATIVE": "1" if native else "0", "NOTIFY_CHOSEN": chosen},
                capture_output=True, check=True,
            )
            return (capture.read_bytes().decode().split("\0")[:-1],
                    opened.read_bytes().decode().split("\0")[:-1] if opened.exists() else [])

    def notification_args(self, action, url="https://example.com/watch?v=1&x=2"):
        return self.notification_result(action, url)[0]

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

    def test_buttons_have_saved_commands_after_sender_exit(self):
        prefix = "--hint=string:omarchy-actions:"
        for default in ["browser", "pip", "none"]:
            args, opened = self.notification_result(default)
            actions = [json.loads(arg[len(prefix):]) for arg in args if arg.startswith(prefix)]
            self.assertEqual(actions, [[
                {"label": "Open", "argv": self.command("browser")},
                {"label": "PiP", "argv": self.command("pip")},
            ]])
            self.assertFalse(any(arg.startswith("--action=") for arg in args))
            self.assertEqual(opened, [])

    def test_missing_url_has_no_buttons(self):
        self.assertFalse(any("omarchy-actions" in arg
                             for arg in self.notification_args("browser", "")))

    def test_other_servers_return_browser_actions(self):
        for chosen in ["browser", "default"]:
            args, opened = self.notification_result("browser", native=False, chosen=chosen)
            self.assertIn("--action=default=Open", args)
            self.assertIn("--action=browser=Open", args)
            self.assertIn("--action=pip=PiP", args)
            self.assertFalse(any("omarchy-actions" in arg for arg in args))
            self.assertEqual(opened, ["https://example.com/watch?v=1&x=2"])

    def test_other_servers_can_disable_the_body_action(self):
        args, opened = self.notification_result("none", native=False)
        self.assertNotIn("--action=default=Open", args)
        self.assertIn("--action=browser=Open", args)
        self.assertIn("--action=pip=PiP", args)
        self.assertEqual(opened, [])


if __name__ == "__main__":
    unittest.main()
