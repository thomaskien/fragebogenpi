#!/usr/bin/env python3
from pathlib import Path
import stat
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "fragebogenpi.sh").read_text()
FRAGMENT = SOURCE[SOURCE.index("install_https_public_pages() {"):SOURCE.index("install_https_tools() {")]
PHP = shutil.which("php")
PHP_CGI = shutil.which("php-cgi")


class HttpsPagesTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="fragebogenpi https ")
        self.base = Path(self.temporary_directory.name)
        self.public_dir = self.base / "Öffentlich & 'Web'"
        self.count_file = self.base / "Tablet $Anzahl 'mit' \\ Zeichen.txt"
        fragment = self.base / "pages.sh"
        fragment.write_text(FRAGMENT)
        install_script = r'''
set -euo pipefail
source "$1"
HTTPS_PUBLIC_DIR="$2"
AP_IP="$3"
TABLET_COUNT_FILE="$4"
install_https_public_pages
'''
        subprocess.run(
            ["bash", "-c", install_script, "bash", str(fragment), str(self.public_dir), "10.23.0.1", str(self.count_file)],
            check=True,
            text=True,
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_static_setup_page_and_permissions(self):
        index_file = self.public_dir / "index.html"
        tablets_file = self.public_dir / "tablets.php"

        self.assertTrue(index_file.is_file())
        self.assertTrue(tablets_file.is_file())
        self.assertEqual(stat.S_IMODE(self.public_dir.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(index_file.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(tablets_file.stat().st_mode), 0o644)

        page = index_file.read_text(encoding="utf-8")
        self.assertIn('<a class="button secondary" href="/ca.crt">', page)
        self.assertIn('href="https://10.23.0.1/"', page)
        self.assertIn("Profil geladen", page)
        self.assertIn("VPN &amp; Geräteverwaltung", page)
        self.assertIn("Zertifikatsvertrauenseinstellungen", page)
        self.assertIn("volle Vertrauen", page)
        self.assertIn(r"/^\/tablet(?:[1-9])?\.php$/", page)
        self.assertNotIn("fetch(", page)
        self.assertNotIn("location.replace", page)
        self.assertNotIn("window.location.href =", page)
        self.assertNotIn("http-equiv=\"refresh\"", page.lower())

    @unittest.skipUnless(PHP, "PHP CLI fehlt")
    def test_php_syntax_is_valid_with_special_count_file_path(self):
        result = subprocess.run(
            [str(PHP), "-l", str(self.public_dir / "tablets.php")],
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("No syntax errors detected", result.stdout)

    @unittest.skipUnless(PHP_CGI, "PHP CGI fehlt")
    def test_missing_three_and_invalid_tablet_configuration(self):
        status, headers, body = self.request()
        self.assertEqual(status, 302)
        self.assertEqual(headers.get("location"), "/tablet.php")
        self.assertEqual(body, b"")

        self.count_file.write_text("1\n", encoding="utf-8")
        status, headers, body = self.request()
        self.assertEqual(status, 302)
        self.assertEqual(headers.get("location"), "/tablet.php")
        self.assertEqual(body, b"")

        self.count_file.write_text("3\n", encoding="utf-8")
        status, headers, body = self.request()
        decoded = body.decode("utf-8")
        self.assertEqual(status, 200)
        self.assertTrue(headers.get("content-type", "").startswith("text/html"))
        for tablet_id in range(1, 4):
            self.assertIn(f'href="/tablet{tablet_id}.php"', decoded)
            self.assertIn(f">Tablet {tablet_id}<", decoded)
        self.assertNotIn('href="/tablet4.php"', decoded)

        self.count_file.write_text("3<script>\n", encoding="utf-8")
        status, headers, body = self.request()
        self.assertEqual(status, 500)
        self.assertTrue(headers.get("content-type", "").startswith("text/plain"))
        self.assertIn("Ungültige Tablet-Konfiguration", body.decode("utf-8"))
        self.assertNotIn(b"<script>", body)

    def request(self):
        result = subprocess.run(
            [str(PHP_CGI), str(self.public_dir / "tablets.php")],
            check=False,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
        header_block, separator, body = result.stdout.partition(b"\r\n\r\n")
        self.assertEqual(separator, b"\r\n\r\n", result.stdout.decode("utf-8", errors="replace"))
        headers = {}
        status = 200
        for raw_line in header_block.decode("utf-8").split("\r\n"):
            name, value = raw_line.split(":", 1)
            headers[name.lower()] = value.strip()
            if name == "Status":
                status = int(value.strip().split(" ", 1)[0])
        return status, headers, body


if __name__ == "__main__":
    unittest.main()
