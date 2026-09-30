#!/usr/bin/env python3
"""Mode-7-Migration mit isolierten Dienst-/Firewall-Stubs und echten Konfigurationsdateien."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'fragebogenpi.sh').read_text().rsplit('main "$@"', 1)[0]


class InstallerHttpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.source = self.base / 'installer.sh'
        self.source.write_text(SOURCE)
        self.log = self.base / 'calls'
        self.live = self.base / 'live'
        self.live.write_text('')
        self.stub('ip', '''printf '[{"addr_info":[{"local":"192.0.2.42","scope":"global"}]}]\\n' ''')
        self.stub('chronyc', 'exit 0')
        self.stub('flock', 'exit 0')  # Python-Zertifikatstest prüft den echten flock-Lock separat.
        self.stub('a2enmod', 'exit 0')
        self.stub('systemctl', '''
if [ "$1" = is-active ]; then
  case "$*" in
    *https-renew.timer*) exit 1 ;;
    *) exit 0 ;;
  esac
fi
if [ "$1" = enable ] && [ "${FAIL_TIMER:-0}" = 1 ]; then exit 1; fi
exit 0
''')
        self.stub('nft', '''
if [ "$1" = -a ]; then
  cat "$TEST_LIVE"
  printf '    iifname "wlan0" drop # handle 20\\n'
elif [ "$1" = -c ]; then
  exit "${FAIL_NFT:-0}"
elif [ "$1" = insert ]; then
  printf '    iifname "wlan0" ip daddr 192.0.2.42 tcp dport 443 accept comment "fragebogenpi-https" # handle 90\\n' > "$TEST_LIVE"
elif [ "$1" = delete ]; then
  : > "$TEST_LIVE"
fi
''')
        self.variables = {
            'AP_IP': '192.0.2.42', 'HOSTNAME_FQDN': 'praxisbox',
            'APACHE_WLAN_DIR': str(self.base / 'apache'),
            'APACHE_WLAN_CONF': str(self.base / 'apache' / 'apache.conf'),
            'APACHE_WLAN_SERVICE': str(self.base / 'apache.service'),
            'APACHE_WLAN_LOG_DIR': str(self.base / 'log'),
            'APACHE_WLAN_RUN_DIR': str(self.base / 'run'),
            'WEBROOT_WLAN': str(self.base / 'webroot'),
            'HTTPS_PUBLIC_DIR': str(self.base / 'https' / 'public'),
            'SSL_DIR': str(self.base / 'ssl'),
            'SSL_KEY': str(self.base / 'ssl' / 'fragebogenpi.key'),
            'SSL_CRT': str(self.base / 'ssl' / 'fragebogenpi.crt'),
            'HTTPS_HELPER': str(self.base / 'helper'),
            'HTTPS_RENEW_SERVICE': str(self.base / 'renew.service'),
            'HTTPS_RENEW_TIMER': str(self.base / 'renew.timer'),
            'TABLET_COUNT_FILE': str(self.base / 'tablet-count'),
            'NFTABLES_CONF': str(self.base / 'nft.conf'),
        }
        self.conf = Path(self.variables['APACHE_WLAN_CONF'])
        self.nft = Path(self.variables['NFTABLES_CONF'])
        self.nft.write_text('''table inet unrelated {
 chain input { type filter hook input priority 10; policy accept; }
}
table inet fragebogenpi {
 chain input {
    type filter hook input priority 0;
    policy accept;
    iif "wlan0" ip daddr 192.0.2.42 tcp dport 80 accept
    iif "wlan0" drop
 }
 chain forward {
    iif "wlan0" drop
    oif "wlan0" drop
 }
}
''')
        Path(self.variables['APACHE_WLAN_SERVICE']).write_text('existing service\n')
        Path(self.variables['WEBROOT_WLAN']).mkdir()
        Path(self.variables['WEBROOT_WLAN'], 'tablet.php').write_text('existing app\n')
        Path(self.variables['SSL_DIR']).mkdir()
        Path(self.variables['SSL_CRT']).write_text('previous certificate\n')
        Path(self.variables['SSL_DIR'], 'https.json').write_text('previous configuration\n')
        self.run_shell('write_apache_wlan_config http legacy')
        self.original = self.conf.read_bytes()
        self.original_nft = self.nft.read_bytes()

    def tearDown(self):
        self.temp.cleanup()

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\nprintf "%s %s\\n" "' + name + '" "$*" >> "$TEST_CALLS"\n' + body)
        path.chmod(0o755)

    def run_shell(self, body, overrides='', check=True, **extra):
        env = os.environ.copy()
        env.update(PATH=str(self.bin) + ':' + env['PATH'], TEST_CALLS=str(self.log),
                   TEST_LIVE=str(self.live), TEST_SSL=self.variables['SSL_DIR'])
        env.update(extra)
        result = subprocess.run(['bash', '-c', 'source ' + shlex.quote(str(self.source)) + '\n' +
                                '\n'.join(k + '=' + shlex.quote(v) for k, v in self.variables.items()) +
                                '\n' + overrides + '\n' + body], env=env, text=True, capture_output=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    @staticmethod
    def crypto_stub():
        return '''
install_https_tools() {
cat > "$HTTPS_HELPER" <<'HELPER'
#!/bin/sh
printf 'new certificate\\n' > "$TEST_SSL/fragebogenpi.crt"
printf 'new configuration\\n' > "$TEST_SSL/https.json"
exit "${FAIL_ACTIVATE:-0}"
HELPER
chmod 0755 "$HTTPS_HELPER"
}
prepare_https_certificate() { return "${FAIL_PREPARE:-0}"; }
'''

    def test_legacy_http_upgrade_and_repeat_are_additive(self):
        self.run_shell('setup_https_only', self.crypto_stub())
        self.assertIn('DocumentRoot "' + self.variables['HTTPS_PUBLIC_DIR'] + '"', self.conf.read_text())
        self.assertIn('Listen 192.0.2.42:443', self.conf.read_text())
        self.assertIn('AliasMatch "^/wartezimmer', self.conf.read_text())
        self.assertEqual(self.nft.read_text().count('comment "fragebogenpi-https"'), 1)
        self.assertIn('table inet unrelated {\n chain input { type filter hook input priority 10; policy accept; }\n}', self.nft.read_text())
        self.assertEqual(Path(self.variables['WEBROOT_WLAN'], 'tablet.php').read_text(), 'existing app\n')
        first_conf, first_nft = self.conf.read_bytes(), self.nft.read_bytes()
        self.run_shell('setup_https_only', self.crypto_stub())
        self.assertEqual(self.conf.read_bytes(), first_conf)
        self.assertEqual(self.nft.read_bytes(), first_nft)
        self.assertEqual(self.log.read_text().count('nft insert rule'), 1)
        self.assertNotIn('restart nftables', self.log.read_text())
        self.assertNotIn('apache2.service', self.log.read_text())
        self.assertNotIn('a2enmod', self.log.read_text())

    def test_legacy_https_configuration_is_supported(self):
        self.run_shell('write_apache_wlan_config https legacy')
        self.run_shell('setup_https_only', self.crypto_stub())
        self.assertIn('/.fragebogenpi-tablets.php', self.conf.read_text())

    def test_custom_apache_or_missing_firewall_is_rejected_before_mutations(self):
        self.conf.write_text(self.conf.read_text() + '\nAlias /custom /srv/custom\n')
        result = self.run_shell('setup_https_only', self.crypto_stub(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Individuelle oder unbekannte', result.stderr)
        self.assertIn('Alias /custom', self.conf.read_text())
        self.assertEqual(self.nft.read_bytes(), self.original_nft)
        self.assertNotIn('a2enmod', self.log.read_text())

    def test_failures_restore_original_apache_cert_config_and_live_firewall(self):
        for flag in ('FAIL_NFT', 'FAIL_PREPARE', 'FAIL_ACTIVATE', 'FAIL_TIMER'):
            with self.subTest(flag=flag):
                result = self.run_shell('setup_https_only', self.crypto_stub(), check=False, **{flag: '1'})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.conf.read_bytes(), self.original)
                self.assertEqual(self.nft.read_bytes(), self.original_nft)
                self.assertEqual(Path(self.variables['SSL_CRT']).read_text(), 'previous certificate\n')
                self.assertEqual(Path(self.variables['SSL_DIR'], 'https.json').read_text(), 'previous configuration\n')
                self.assertEqual(self.live.read_text(), '')

    def test_firewall_rule_cannot_be_after_drop_or_point_elsewhere(self):
        self.live.write_text('iifname "wlan0" ip daddr 192.0.2.99 tcp dport 443 accept comment "fragebogenpi-https" # handle 90\n')
        result = self.run_shell('setup_https_only', self.crypto_stub(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.conf.read_bytes(), self.original)
        self.assertEqual(self.nft.read_bytes(), self.original_nft)

    def test_bad_tablet_count_or_missing_numbered_endpoint_aborts_before_changes(self):
        count_file = Path(self.variables['TABLET_COUNT_FILE'])
        for value in ('bad', '3\n'):
            count_file.write_text(value)
            result = self.run_shell('setup_https_only', self.crypto_stub(), check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.conf.read_bytes(), self.original)
            self.assertEqual(self.nft.read_bytes(), self.original_nft)
        self.assertNotIn('a2enmod', self.log.read_text())

    def test_daily_service_and_timer_are_root_only_and_persistent(self):
        self.run_shell('install_https_tools')
        self.assertIn('Persistent=true', Path(self.variables['HTTPS_RENEW_TIMER']).read_text())
        service = Path(self.variables['HTTPS_RENEW_SERVICE']).read_text()
        self.assertIn('User=root', service)
        self.assertIn(' renew\n', service)
        self.assertIn('ProtectSystem=strict', service)
        self.assertEqual(Path(self.variables['HTTPS_HELPER']).stat().st_mode & 0o777, 0o755)


if __name__ == '__main__':
    unittest.main(verbosity=2)
