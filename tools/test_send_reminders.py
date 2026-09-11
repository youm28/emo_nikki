"""send_reminders.py のうち、Firebase に触れない部分のテスト。

    .venv/bin/python -m unittest tools/test_send_reminders.py
"""

import sys
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).parent))

from send_reminders import (  # noqa: E402
    DIARY,
    RECORD,
    build_link,
    build_message,
    reminder_for_hour,
)


class ReminderForHourTest(unittest.TestCase):
    def test_10時から19時は記録の通知(self):
        for hour in range(10, 20):
            self.assertIs(reminder_for_hour(hour), RECORD, hour)

    def test_21時は日記の通知(self):
        self.assertIs(reminder_for_hour(21), DIARY)

    def test_それ以外は送らない(self):
        # 20時台は記録も日記も送らない（19時台の記録と21時の日記の間）。
        for hour in [*range(0, 10), 20, 22, 23]:
            self.assertIsNone(reminder_for_hour(hour), hour)


class BuildLinkTest(unittest.TestCase):
    def query(self, url: str) -> dict[str, list[str]]:
        return parse_qs(urlparse(url).query)

    def test_記録の通知は本人の画面だけを開く(self):
        self.assertEqual(self.query(build_link("p01", RECORD)), {"u": ["p01"]})

    def test_日記の通知は日記欄を開く指定が付く(self):
        self.assertEqual(
            self.query(build_link("p01", DIARY)), {"u": ["p01"], "open": ["diary"]}
        )

    def test_日本語や記号の名前でも崩れない(self):
        # & や = を含む名前をそのまま繋ぐと、open の指定と混ざってしまう。
        self.assertEqual(
            self.query(build_link("山田&太=郎", DIARY)),
            {"u": ["山田&太=郎"], "open": ["diary"]},
        )


class BuildMessageTest(unittest.TestCase):
    def test_種類ごとの文言とリンクが入る(self):
        msg = build_message("p01", "tok", DIARY)
        self.assertEqual(msg.webpush.notification.title, "日記の時間です")
        self.assertIn("open=diary", msg.webpush.fcm_options.link)


if __name__ == "__main__":
    unittest.main()
