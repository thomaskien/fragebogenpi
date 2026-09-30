#!/usr/bin/env python3
"""HTTP/HTTPS-Integration gegen einen isolierten Apache mit PHP-FastCGI auf hohen Loopback-Ports.

Benötigt Apache 2.4, PHP-CGI und Erlaubnis, lokale Testports zu binden.
Systemkonfiguration/Dienste bleiben unangetastet. Keine Patientendaten.
"""
import getpass
import grp
import http.client
import os
from pathlib import Path
import shlex
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
import unittest

from https_certificates_test import SOURCE, https

HTTPD = shutil.which('apache2') or shutil.which('httpd') or ('/usr/sbin/httpd' if Path('/usr/sbin/httpd').exists() else None)
PHP_CGI = shutil.which('php-cgi')
MOD_DIR = Path('/usr/libexec/apache2') if Path('/usr/libexec/apache2').exists() else Path('/usr/lib/apache2/modules')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


@unittest.skipUnless(HTTPD and PHP_CGI and MOD_DIR.exists(), 'Apache/PHP-CGI mit Modulen fehlt')
class ApacheHttpsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='fragebogenpi-apache-')
        cls.base = Path(cls.temp.name)
        cls.processes = []
        cls.addClassCleanup(cls.cleanup)
        cls.http, cls.https, cls.fcgi = free_port(), free_port(), free_port()
        cls.webroot = cls.base / 'webroot'
        cls.webroot.mkdir()
        cls.count = cls.base / 'tablet-count'
        cls.count.write_text('1\n')
        cls.state = cls.base / 'ssl'
        cls.manager = https.Manager(cls.state)
        cls.cfg = {'ip': '127.0.0.1', 'dns': ['fragebogenpi', 'fragebogenpi.local']}
        with cls.manager.locked():
            cls.manager.create_leaf(cls.cfg, int(time.time()), cls.state / 'initial.crt', create=True)
            https.atomic(cls.manager.cert, (cls.state / 'initial.crt').read_bytes())
        shell = cls.base / 'source.sh'
        shell.write_text(SOURCE.rsplit('main "$@"', 1)[0])
        cls.conf = cls.base / 'apache.conf'
        variables = {'AP_IP': '127.0.0.1', 'APACHE_WLAN_CONF': str(cls.conf),
                     'APACHE_WLAN_DIR': str(cls.base / 'apache'),
                     'APACHE_WLAN_RUN_DIR': str(cls.base / 'run'),
                     'APACHE_WLAN_LOG_DIR': str(cls.base / 'log'),
                     'HTTPS_PUBLIC_DIR': str(cls.base / 'https' / 'public'),
                     'WEBROOT_WLAN': str(cls.webroot), 'TABLET_COUNT_FILE': str(cls.count),
                     'SSL_CRT': str(cls.manager.cert), 'SSL_KEY': str(cls.manager.key)}
        cls.public = Path(variables['HTTPS_PUBLIC_DIR'])
        (cls.base / 'run').mkdir()
        subprocess.run(['bash', '-c', 'source ' + shlex.quote(str(shell)) + '\n' +
                        '\n'.join(k + '=' + shlex.quote(v) for k, v in variables.items()) +
                        '\ninstall_https_public_pages\nwrite_apache_wlan_config https'], check=True)
        cls.public.joinpath('ca.crt').write_bytes(https.run('openssl', 'x509', '-in', cls.manager.ca, '-outform', 'DER'))
        cls.webroot.joinpath('tablet.php').write_text('<?php echo "TABLET_SINGLE";')
        cls.webroot.joinpath('tablet2.php').write_text('<?php echo "TABLET_TWO";')
        cls.webroot.joinpath('api.php').write_text('<?php header("Content-Type: application/json"); echo "{\\"ok\\":true}";')
        cls.webroot.joinpath('asset.css').write_text('body {color: blue}')
        cls.webroot.joinpath('wartezimmer-server.php').write_text('<?php header("Content-Type: application/json"); echo "{\\"zimmer\\":1}";')
        modules = ['mpm_prefork', 'authz_core', 'authz_host', 'log_config', 'mime', 'dir', 'alias', 'rewrite', 'setenvif', 'ssl', 'socache_shmcb', 'proxy', 'proxy_fcgi']
        if (MOD_DIR / 'mod_unixd.so').exists():
            modules.insert(1, 'unixd')
        prefix = '\n'.join(f'LoadModule {m}_module "{MOD_DIR}/mod_{m}.so"' for m in modules) + '\n'
        conf = cls.conf.read_text()
        conf = conf.replace('IncludeOptional /etc/apache2/mods-enabled/*.load', '').replace('IncludeOptional /etc/apache2/mods-enabled/*.conf', '')
        conf = conf.replace('127.0.0.1:80', f'127.0.0.1:{cls.http}').replace('127.0.0.1:443', f'127.0.0.1:{cls.https}')
        conf = conf.replace('User www-data', 'User ' + getpass.getuser()).replace('Group www-data', 'Group ' + grp.getgrgid(os.getgid()).gr_name)
        mime = '/etc/apache2/mime.types' if Path('/etc/apache2/mime.types').exists() else '/etc/mime.types'
        conf = conf.replace('TypesConfig /etc/mime.types', 'TypesConfig ' + mime)
        cls.conf.write_text(prefix + conf + f'\nProxyFCGIBackendType GENERIC\n<FilesMatch "\\.php$">\nSetHandler "proxy:fcgi://127.0.0.1:{cls.fcgi}"\n</FilesMatch>\n')
        check = subprocess.run([HTTPD, '-t', '-f', str(cls.conf)], capture_output=True, text=True)
        if check.returncode:
            raise RuntimeError(check.stderr)
        cls.output = (cls.base / 'process.log').open('wb')
        cls.processes.append(subprocess.Popen([PHP_CGI, '-b', f'127.0.0.1:{cls.fcgi}'], stdout=cls.output, stderr=cls.output, start_new_session=True))
        cls.processes.append(subprocess.Popen([HTTPD, '-f', str(cls.conf), '-DFOREGROUND'], stdout=cls.output, stderr=cls.output, start_new_session=True))
        cls.context = ssl.create_default_context(cafile=str(cls.manager.ca))
        for _ in range(60):
            try:
                with socket.create_connection(('127.0.0.1', cls.https), timeout=0.5):
                    with socket.create_connection(('127.0.0.1', cls.fcgi), timeout=0.5):
                        break
            except OSError:
                if any(p.poll() is not None for p in cls.processes):
                    raise RuntimeError((cls.base / 'process.log').read_text())
                time.sleep(0.1)
        else:
            raise RuntimeError('Test-Apache nicht bereit')

    @classmethod
    def cleanup(cls):
        for process in reversed(cls.processes):
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if hasattr(cls, 'output'):
            cls.output.close()
        cls.temp.cleanup()

    def request(self, path, tls=False, method='GET'):
        if tls:
            connection = http.client.HTTPSConnection('127.0.0.1', self.https, context=self.context, timeout=5)
        else:
            connection = http.client.HTTPConnection('127.0.0.1', self.http, timeout=5)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_http_is_setup_even_for_direct_php_post_and_selection_alias(self):
        for path in ('/', '/index.html', '/tablet.php', '/tablet2.php?patient=secret', '/api.php', '/.fragebogenpi-tablets.php', '/tablets.php', '/missing', '/ca.key'):
            for method in ('GET', 'POST'):
                with self.subTest(path=path, method=method):
                    status, headers, body = self.request(path, method=method)
                    self.assertEqual(status, 200)
                    self.assertIn('Sichere Verbindung'.encode(), body)
                    self.assertNotIn('Location', headers)
                    self.assertNotIn(b'PRIVATE KEY', body)

    def test_ca_download_is_public_root_certificate_on_both_protocols(self):
        for tls in (False, True):
            status, headers, body = self.request('/ca.crt', tls)
            self.assertEqual(status, 200)
            self.assertTrue(headers['Content-Type'].startswith('application/x-x509-ca-cert'))
            self.assertEqual(body, self.public.joinpath('ca.crt').read_bytes())

    def test_waiting_room_stays_http_and_does_not_enter_access_log(self):
        status, headers, body = self.request('/wartezimmer-server.php?room=1')
        self.assertEqual((status, body), (200, b'{"zimmer":1}'))
        self.assertNotIn('wartezimmer-server.php', (self.base / 'log' / 'fragebogenpi-wlan-http-access.log').read_text())

    def test_https_root_and_index_single_or_multiple(self):
        self.count.write_text('1\n')
        for path in ('/', '/index.html'):
            status, headers, body = self.request(path, True)
            self.assertEqual(status, 302)
            self.assertEqual(headers['Location'], '/tablet.php')
        self.count.write_text('3\n')
        status, headers, body = self.request('/', True)
        self.assertEqual(status, 200)
        for number in range(1, 4):
            self.assertIn(f'href="/tablet{number}.php"'.encode(), body)
        self.count.write_text('1\n')

    def test_https_direct_tablet_assets_and_api_are_preserved(self):
        for path, expected in (('/tablet.php', b'TABLET_SINGLE'), ('/tablet2.php', b'TABLET_TWO'),
                               ('/api.php', b'{"ok":true}'), ('/asset.css', b'body {color: blue}')):
            status, _, body = self.request(path, True)
            self.assertEqual((status, body), (200, expected))

    def test_public_route_verification_uses_only_setup_routes(self):
        from unittest import mock
        http_connection, https_connection = http.client.HTTPConnection, http.client.HTTPSConnection
        def plain(host, **kwargs):
            return http_connection(host, self.http, **kwargs)
        def secure(host, **kwargs):
            return https_connection(host, self.https, **kwargs)
        from types import SimpleNamespace
        client = SimpleNamespace(HTTPConnection=plain, HTTPSConnection=secure)
        with mock.patch.object(https, 'http', SimpleNamespace(client=client)):
            self.manager.verify_public_routes(self.cfg)

    def test_real_wire_verification_then_reload_after_renewal(self):
        # Ausschließlich den Testport abbilden; Manager prüft echte CA, IP und DER-Zertifikat.
        original = socket.create_connection
        def connect(address, **kwargs):
            return original(('127.0.0.1', self.https), **kwargs)
        from unittest import mock
        with mock.patch.object(https.socket, 'create_connection', side_effect=connect):
            self.manager.verify_served(self.cfg, https.run('openssl', 'x509', '-in', self.manager.cert, '-outform', 'DER'))
            with self.manager.locked():
                candidate = self.state / 'next.crt'
                self.manager.create_leaf(self.cfg, int(time.time()), candidate)
                https.atomic(self.manager.cert, candidate.read_bytes())
            subprocess.run([HTTPD, '-f', str(self.conf), '-k', 'graceful'], check=True, capture_output=True)
            self.manager.verify_served(self.cfg, https.run('openssl', 'x509', '-in', self.manager.cert, '-outform', 'DER'))
        self.assertEqual(self.request('/tablet2.php', True)[2], b'TABLET_TWO')


if __name__ == '__main__':
    unittest.main(verbosity=2)
