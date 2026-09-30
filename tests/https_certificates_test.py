#!/usr/bin/env python3
"""Echte OpenSSL-Zertifikate, isolierte Apache-/Chrony-Aufrufe; keine Systemänderungen."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'fragebogenpi.sh').read_text()
CODE = SOURCE.split("<<'PY_HTTPS_MANAGER'\n", 1)[1].split('\nPY_HTTPS_MANAGER\n', 1)[0]
https = types.ModuleType('https_manager')
exec(compile(CODE, 'embedded-https-manager.py', 'exec'), https.__dict__)
REAL_RUN = https.run


class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory()
        cls.baseline = Path(cls.fixture.name) / 'baseline'
        cls.now = int(time.time())
        manager = https.Manager(cls.baseline)
        with manager.locked():
            manager.create_leaf({'ip': '127.0.0.1', 'dns': ['fragebogenpi', 'fragebogenpi.local']},
                                cls.now, cls.baseline / 'first.crt', create=True)
            https.atomic(manager.cert, (cls.baseline / 'first.crt').read_bytes())

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.state = self.base / 'state'
        shutil.copytree(self.baseline, self.state)
        self.manager = https.Manager(self.state)
        self.cfg = {'ip': '127.0.0.1', 'dns': ['fragebogenpi', 'fragebogenpi.local'],
                    'interface': 'wlan0', 'public': str(self.base / 'public'),
                    'apache': str(self.base / 'apache.conf'), 'run': str(self.base / 'run'),
                    'log': str(self.base / 'log'),
                    'ca_fingerprint': hashlib.sha256(REAL_RUN('openssl', 'x509', '-in', self.manager.ca, '-outform', 'DER')).hexdigest()}
        https.atomic(self.manager.config, https.json_bytes(self.cfg))
        https.atomic(self.state / 'last-success.json', https.json_bytes({'reference': self.now}))
        self.old = self.manager.cert.read_bytes()
        self.ca = self.manager.ca.read_bytes()
        self.key = self.manager.key.read_bytes()
        self.system_calls = []
        patcher = mock.patch.object(self.manager, "verify_public_routes")
        self.public_routes = patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        self.temp.cleanup()

    def system_stub(self, *args, **kwargs):
        if args[0] == 'systemctl':
            self.system_calls.append(args)
            return b''
        return REAL_RUN(*args, **kwargs)

    def candidate(self):
        path = self.state / 'candidate.crt'
        self.manager.create_leaf(self.cfg, self.now, path)
        return path

    def test_exact_window_ca_extensions_key_usage_and_serial_change(self):
        path = self.candidate()
        self.assertEqual(https.dates(path), (self.now - 365 * 86400, self.now + 365 * 86400))
        ca_before, ca_after = https.dates(self.manager.ca)
        self.assertEqual(ca_before, self.now - 365 * 86400)
        self.assertGreater(ca_after - self.now, 49 * 365 * 86400)
        self.assertNotEqual(REAL_RUN('openssl', 'x509', '-in', path, '-noout', '-serial'),
                            REAL_RUN('openssl', 'x509', '-in', self.manager.cert, '-noout', '-serial'))
        REAL_RUN('openssl', 'verify', '-CAfile', self.manager.ca, '-purpose', 'sslserver',
                 '-verify_ip', '127.0.0.1', path)
        # Beide Ränder der vom iPad verwendbaren Zertifikatskette prüfen.
        for reference in (self.now - 365 * 86400 + 1, self.now + 365 * 86400 - 1):
            REAL_RUN('openssl', 'verify', '-CAfile', self.manager.ca, '-attime', reference, path)
        self.assertIn('IP Address:127.0.0.1', https.cert_text(path))
        self.assertNotIn('DNS:127.0.0.1', https.cert_text(path))
        self.assertEqual(self.manager.key.read_bytes(), self.key)
        self.assertEqual(self.manager.ca.read_bytes(), self.ca)

    def test_renew_really_issues_and_activates_a_new_certificate_every_time(self):
        with mock.patch.object(https, 'run', side_effect=self.system_stub), \
             mock.patch.object(self.manager, 'reference_time', return_value=self.now), \
             mock.patch.object(self.manager, 'check_address'), \
             mock.patch.object(self.manager, 'apache_test'), \
             mock.patch.object(self.manager, 'verify_served') as served:
            with self.manager.locked():
                self.manager.renew()
            first = self.manager.cert.read_bytes()
            with self.manager.locked():
                self.manager.renew()
            second = self.manager.cert.read_bytes()
            self.assertEqual(served.call_count, 2)
        self.assertNotEqual(self.old, first)
        self.assertNotEqual(first, second)
        self.assertEqual(self.manager.ca.read_bytes(), self.ca)
        self.assertEqual(self.manager.key.read_bytes(), self.key)
        self.assertEqual(self.system_calls, [('systemctl', 'reload', https.SERVICE)] * 2)
        self.assertEqual((self.state / 'previous' / 'fragebogenpi.crt').read_bytes(), first)

    def test_activation_restores_working_cert_after_config_reload_or_probe_failure(self):
        for stage in ('apache', 'reload', 'probe', 'routes'):
            with self.subTest(stage=stage):
                candidate = self.candidate()
                self.public_routes.side_effect = RuntimeError("HTTP-Einrichtungsseite falsch") if stage == "routes" else None
                def system(*args, **kwargs):
                    if args[0] == 'systemctl' and stage == 'reload' and not self.system_calls:
                        self.system_calls.append(args)
                        raise RuntimeError('simulierter Reload-Fehler')
                    return self.system_stub(*args, **kwargs)
                self.system_calls.clear()
                test_effect = [RuntimeError('ungültige Konfiguration'), None] if stage == 'apache' else None
                with mock.patch.object(https, 'run', side_effect=system), \
                     mock.patch.object(self.manager, 'apache_test', side_effect=test_effect), \
                     mock.patch.object(self.manager, 'verify_served', side_effect=RuntimeError('falsches Wire-Zertifikat') if stage == 'probe' else None):
                    with self.assertRaises(RuntimeError):
                        self.manager.activate(self.cfg, self.now, candidate)
                self.assertEqual(self.manager.cert.read_bytes(), self.old)
                self.assertEqual(json.loads(self.manager.config.read_text()), self.cfg)
                self.assertEqual(self.manager.ca.read_bytes(), self.ca)
                self.assertFalse((self.state / 'activation-recovery.json').exists())

    def test_failed_initial_start_stops_new_apache_and_restores_files(self):
        candidate = self.candidate()
        self.manager.cert.unlink()
        self.manager.config.unlink()
        with mock.patch.object(https, 'run', side_effect=self.system_stub), \
             mock.patch.object(self.manager, 'apache_test'), \
             mock.patch.object(self.manager, 'verify_served', side_effect=RuntimeError('falsches Zertifikat')):
            with self.assertRaises(RuntimeError):
                self.manager.activate(self.cfg, self.now, candidate, start=True)
        self.assertEqual(self.system_calls, [('systemctl', 'start', https.SERVICE), ('systemctl', 'stop', https.SERVICE)])
        self.assertFalse(self.manager.cert.exists())
        self.assertFalse(self.manager.config.exists())

    def test_missing_ca_pair_with_remaining_backup_does_not_create_a_new_root(self):
        self.manager.ca.unlink()
        self.manager.ca_key.unlink()
        self.manager.config.unlink()
        with self.assertRaisesRegex(RuntimeError, 'Frühere CA-Daten'):
            self.manager.ensure_ca(self.now, create=True)
        self.assertFalse(self.manager.ca.exists())
        self.assertEqual((self.state / 'ca-backup' / 'ca.crt').read_bytes(), self.ca)

    def test_recovery_journal_restores_after_interrupted_exchange(self):
        old_config = self.manager.config.read_bytes()
        https.atomic(self.state / 'activation-recovery.json', https.json_bytes({
            'cert': self.old.decode(), 'config': old_config.decode(),
            'success': json.dumps({'reference': self.now})}))
        https.atomic(self.manager.cert, self.candidate().read_bytes())
        with mock.patch.object(https, 'run', side_effect=self.system_stub), mock.patch.object(self.manager, 'apache_test'):
            self.manager.recover(self.cfg)
        self.assertEqual(self.manager.cert.read_bytes(), self.old)
        self.assertFalse((self.state / 'activation-recovery.json').exists())

    def test_bad_san_bad_key_or_empty_candidate_never_replaces_live_certificate(self):
        path = self.candidate()
        wrong_cfg = dict(self.cfg, ip='192.0.2.99')
        with self.assertRaises(RuntimeError):
            self.manager.activate(wrong_cfg, self.now, path)
        path.write_text('')
        with self.assertRaises(RuntimeError):
            self.manager.activate(self.cfg, self.now, path)
        self.assertEqual(self.manager.cert.read_bytes(), self.old)
        shutil.copyfile(self.manager.ca_key, self.manager.key)
        with self.assertRaisesRegex(RuntimeError, 'Server-Key'):
            self.manager.validate_leaf(self.cfg, self.now, self.state / 'first.crt')
        self.assertEqual(self.manager.cert.read_bytes(), self.old)

    def test_ca_is_never_silently_regenerated_even_during_setup(self):
        self.manager.ca.unlink()
        with self.assertRaisesRegex(RuntimeError, 'Root-CA fehlt'):
            self.manager.prepare(self.cfg)
        with self.assertRaisesRegex(RuntimeError, 'unvollständig'):
            self.manager.ensure_ca(self.now, create=True)
        self.assertFalse(self.manager.ca.exists())
        self.assertEqual(self.manager.cert.read_bytes(), self.old)

    def test_unsynchronized_clock_keeps_current_certificate(self):
        with mock.patch.object(https, 'run', side_effect=lambda *args, **kw: (_ for _ in ()).throw(RuntimeError('Chrony unsynchronisiert')) if args[0] == 'chronyc' else REAL_RUN(*args, **kw)), \
             mock.patch.object(self.manager, 'check_address'):
            with self.assertRaisesRegex(RuntimeError, 'Chrony'):
                self.manager.renew()
        self.assertEqual(self.manager.cert.read_bytes(), self.old)
        with mock.patch.object(https, 'run', return_value=b''), mock.patch.object(https.time, 'time', return_value=self.now - 600):
            with self.assertRaisesRegex(RuntimeError, 'zurückgesprungen'):
                self.manager.reference_time()

    def test_changed_ip_is_rejected(self):
        with mock.patch.object(https, 'run', return_value=b'[{"addr_info":[{"local":"192.0.2.3"}]}]'):
            with self.assertRaisesRegex(RuntimeError, 'nicht am WLAN'):
                self.manager.check_address(self.cfg)

    def test_parallel_processes_and_symlink_targets_are_rejected(self):
        with self.manager.locked():
            with self.assertRaisesRegex(RuntimeError, 'läuft bereits'):
                with https.Manager(self.state).locked():
                    pass
        link = self.state / 'link'
        link.symlink_to(self.manager.cert)
        with self.assertRaisesRegex(RuntimeError, 'Symlink'):
            https.atomic(link, b'bad')
        self.assertEqual(self.manager.cert.read_bytes(), self.old)

    def test_ca_download_contains_only_public_root_der_and_private_modes(self):
        with mock.patch.object(self.manager, 'check_address'), mock.patch.object(self.manager, 'reference_time', return_value=self.now):
            self.manager.prepare(self.cfg)
        public = Path(self.cfg['public']) / 'ca.crt'
        der = REAL_RUN('openssl', 'x509', '-in', self.manager.ca, '-outform', 'DER')
        self.assertEqual(public.read_bytes(), der)
        for path in (self.manager.key, self.manager.ca_key, self.state / 'ca-backup' / 'ca.key'):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(public.stat().st_mode & 0o777, 0o644)
        self.assertFalse((Path(self.cfg['public']) / 'ca.key').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
