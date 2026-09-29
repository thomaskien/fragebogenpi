#!/usr/bin/env python3
"""Regressionstests für Zeitserver, Chrony-Client und Abschalttimer."""

from __future__ import annotations

import os
import shlex
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ShellHarness:
    def __init__(self, testcase: unittest.TestCase, script_name: str) -> None:
        self.testcase = testcase
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        source = (ROOT / script_name).read_text(encoding="utf-8")
        self.testcase.assertTrue(source.rstrip().endswith('main "$@"'))
        source = source.rstrip().removesuffix('main "$@"')
        self.source = self.root / script_name
        self.source.write_text(source, encoding="utf-8")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.log"
        self.state = self.root / "nft-state"
        self._write_stubs()

    def _stub(self, name: str, body: str = "exit 0") -> None:
        path = self.bin / name
        path.write_text(
            "#!/bin/sh\n"
            'printf \'%s %s\\n\' "$(basename "$0")" "$*" >> "$STUB_LOG"\n'
            + body
            + "\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _write_stubs(self) -> None:
        for command in ("chronyd", "dnsmasq", "systemctl", "sysctl"):
            self._stub(command)
        self._stub("chronyc", 'exit "${CHRONYC_EXIT:-0}"')
        self._stub(
            "ip",
            textwrap.dedent(
                """
                if [ "$1 $2 $3" = "-4 -o addr" ]; then
                  printf '2: wlan0    inet 10.23.0.1/24 brd 10.23.0.255 scope global wlan0\\n'
                fi
                exit 0
                """
            ).strip(),
        )
        self._stub(
            "nft",
            textwrap.dedent(
                """
                if [ "$1 $2" = "list chain" ]; then
                  [ "${NFT_LIST_EXIT:-0}" = 0 ] || exit "$NFT_LIST_EXIT"
                  [ ! -f "$NFT_STATE" ] || cat "$NFT_STATE"
                  printf 'iif "wlan0" drop\\n'
                elif [ "$1 $2" = "insert rule" ]; then
                  shift 5
                  printf '%s\\n' "$*" >> "$NFT_STATE"
                elif [ "$1" = "-c" ]; then
                  exit "${NFT_CHECK_EXIT:-0}"
                fi
                exit 0
                """
            ).strip(),
        )

    def run(self, body: str, *, check: bool = True, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "TEST_SOURCE": str(self.source),
                "TEST_ROOT": str(self.root),
                "STUB_LOG": str(self.log),
                "NFT_STATE": str(self.state),
            }
        )
        if extra_env:
            env.update(extra_env)
        result = subprocess.run(
            ["bash", "-c", 'source "$TEST_SOURCE"\n' + body],
            text=True,
            capture_output=True,
            env=env,
            cwd=ROOT,
            check=False,
        )
        if check and result.returncode != 0:
            self.testcase.fail(
                f"Shell-Harness schlug fehl ({result.returncode})\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        return result

    def close(self) -> None:
        self.tempdir.cleanup()


class FragebogenpiTimeServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sh = ShellHarness(self, "fragebogenpi.sh")

    def tearDown(self) -> None:
        self.sh.close()

    def test_server_chrony_and_both_dnsmasq_paths(self) -> None:
        result = self.sh.run(
            r'''
            CHRONY_CONF="$TEST_ROOT/chrony.conf"
            write_and_activate_chrony_server_config
            write_dnsmasq_ap_config "$TEST_ROOT/dns-enabled.conf" yes
            write_dnsmasq_ap_config "$TEST_ROOT/dhcp-only.conf" no
            '''
        )
        chrony = (self.sh.root / "chrony.conf").read_text()
        self.assertIn("pool 2.debian.pool.ntp.org iburst", chrony)
        self.assertIn("bindaddress 10.23.0.1", chrony)
        self.assertIn("binddevice wlan0", chrony)
        self.assertIn("allow 10.23.0.0/24", chrony)
        self.assertIn("cmdport 0", chrony)
        self.assertNotIn("local stratum", chrony)
        for name in ("dns-enabled.conf", "dhcp-only.conf"):
            config = (self.sh.root / name).read_text()
            self.assertEqual(config.count("dhcp-option-force=option:ntp-server,10.23.0.1"), 1)
        self.assertIn("address=/#/10.23.0.1", (self.sh.root / "dns-enabled.conf").read_text())
        self.assertIn("port=0", (self.sh.root / "dhcp-only.conf").read_text())
        commands = self.sh.log.read_text()
        self.assertIn("chronyd -p -f", commands)
        self.assertIn("systemctl enable chrony", commands)
        self.assertIn("systemctl restart chrony", commands)
        self.assertNotIn("ERROR", result.stderr)

    def test_full_firewall_rule_is_narrow_and_before_drop(self) -> None:
        self.sh.run(
            r'''
            NFTABLES_CONF="$TEST_ROOT/nftables.conf"
            SYSCTL_CONF="$TEST_ROOT/sysctl.conf"
            setup_firewall_nftables_wlan_only http
            '''
        )
        config = (self.sh.root / "nftables.conf").read_text()
        rule = 'iif "wlan0" ip saddr 10.23.0.0/24 ip daddr 10.23.0.1 udp dport 123 accept'
        self.assertIn(rule, config)
        self.assertLess(config.index(rule), config.index('iif "wlan0" drop'))
        self.assertEqual(config.count("udp dport 123"), 1)

    def test_mode6_preserves_foreign_rules_and_is_idempotent(self) -> None:
        dns = self.sh.root / "dnsmasq.conf"
        firewall = self.sh.root / "nftables.conf"
        dns.write_text(
            "interface=wlan0\nbind-interfaces\nlisten-address=10.23.0.1\n"
            "port=0\ndhcp-range=10.23.0.50,10.23.0.150,255.255.255.0,12h\n"
            "# fremder dnsmasq-Kommentar\n"
        )
        firewall.write_text(
            "#!/usr/sbin/nft -f\n"
            "table inet fremd { chain input { counter accept } }\n"
            "table inet fragebogenpi {\n"
            "  chain input {\n"
            "    type filter hook input priority 0; policy accept;\n"
            "    tcp dport 9999 accept comment \"fremde-regel\"\n"
            "    iif \"wlan0\" drop\n"
            "  }\n"
            "  chain forward {\n"
            "    type filter hook forward priority 0; policy accept;\n"
            "    iif \"wlan0\" drop\n"
            "    oif \"wlan0\" drop\n"
            "  }\n"
            "}\n"
        )
        self.sh.run(
            r'''
            DNSMASQ_CONF="$TEST_ROOT/dnsmasq.conf"
            NFTABLES_CONF="$TEST_ROOT/nftables.conf"
            validate_time_server_only_prerequisites
            activate_time_server_only_changes
            activate_time_server_only_changes
            '''
        )
        dns_after = dns.read_text()
        firewall_after = firewall.read_text()
        self.assertIn("# fremder dnsmasq-Kommentar", dns_after)
        self.assertEqual(dns_after.count("dhcp-option-force=option:ntp-server,10.23.0.1"), 1)
        self.assertIn("table inet fremd { chain input { counter accept } }", firewall_after)
        self.assertIn('tcp dport 9999 accept comment "fremde-regel"', firewall_after)
        self.assertEqual(firewall_after.count('comment "fragebogenpi-ntp"'), 1)
        self.assertNotIn("udp dport 123", firewall_after.split("chain forward", 1)[1])
        self.assertEqual(self.sh.state.read_text().count("fragebogenpi-ntp"), 1)
        commands = self.sh.log.read_text()
        self.assertIn("dnsmasq --test --conf-file=", commands)
        self.assertIn("nft -c -f", commands)
        self.assertEqual(commands.count("nft insert rule"), 1)
        self.assertEqual(len(list(self.sh.root.glob(".dnsmasq.conf.bak.*"))), 1)
        self.assertEqual(list(self.sh.root.glob("dnsmasq.conf.bak.*")), [])

    def test_mode6_rejects_unknown_firewall_before_patch(self) -> None:
        dns = self.sh.root / "dnsmasq.conf"
        firewall = self.sh.root / "nftables.conf"
        dns.write_text("interface=wlan0\nlisten-address=10.23.0.1\n")
        firewall.write_text("table inet fremd { chain input { accept } }\n")
        before_dns = dns.read_text()
        before_firewall = firewall.read_text()
        result = self.sh.run(
            r'''
            DNSMASQ_CONF="$TEST_ROOT/dnsmasq.conf"
            NFTABLES_CONF="$TEST_ROOT/nftables.conf"
            validate_time_server_only_prerequisites
            ''',
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Modus 6 abgelehnt", result.stderr)
        self.assertEqual(dns.read_text(), before_dns)
        self.assertEqual(firewall.read_text(), before_firewall)

    def test_mode6_upgrades_actual_full_installer_firewall(self) -> None:
        for mode in ("http", "https"):
            with self.subTest(mode=mode):
                self.sh.run(
                    r'''
                    NFTABLES_CONF="$TEST_ROOT/nftables.conf"
                    SYSCTL_CONF="$TEST_ROOT/sysctl.conf"
                    setup_firewall_nftables_wlan_only "$TEST_WEB_MODE"
                    ''',
                    extra_env={"TEST_WEB_MODE": mode},
                )
                firewall = self.sh.root / "nftables.conf"
                original = "".join(line for line in firewall.read_text().splitlines(keepends=True)
                                   if 'comment "fragebogenpi-ntp"' not in line)
                # Eine fremde Chain darf denselben WLAN-drop-Anker enthalten.
                original += 'table inet fremd {\n  chain input {\n    iif "wlan0" drop\n  }\n}\n'
                firewall.write_text(original)
                self.sh.run(r'''
                    NFTABLES_CONF="$TEST_ROOT/nftables.conf"
                    validate_fragebogenpi_firewall_structure "$NFTABLES_CONF"
                    patch_firewall_ntp_rule_persistent
                    patch_firewall_ntp_rule_persistent
                ''')
                result = firewall.read_text()
                restored = "".join(line for line in result.splitlines(keepends=True)
                                   if 'comment "fragebogenpi-ntp"' not in line)
                self.assertEqual(restored, original)
                self.assertEqual(result.count('comment "fragebogenpi-ntp"'), 1)
                self.assertNotIn("udp dport 123", result.split("chain forward", 1)[1])

    def test_invalid_nft_candidate_keeps_both_original_files(self) -> None:
        dns = self.sh.root / "dnsmasq.conf"
        firewall = self.sh.root / "nftables.conf"
        dns.write_text("interface=wlan0\nlisten-address=10.23.0.1\n")
        firewall.write_text('table inet fragebogenpi {\n  chain input {\n    iif "wlan0" drop\n  }\n}\n')
        before = (dns.read_text(), firewall.read_text())
        result = self.sh.run(r'''
            DNSMASQ_CONF="$TEST_ROOT/dnsmasq.conf"
            NFTABLES_CONF="$TEST_ROOT/nftables.conf"
            activate_time_server_only_changes
        ''', check=False, extra_env={"NFT_CHECK_EXIT": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((dns.read_text(), firewall.read_text()), before)
        self.assertNotIn("systemctl restart", self.sh.log.read_text())
        self.assertNotIn("nft insert", self.sh.log.read_text())

    def test_missing_or_changed_live_firewall_is_rejected(self) -> None:
        result = self.sh.run("time_server_live_ntp_state", check=False,
                             extra_env={"NFT_LIST_EXIT": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.sh.state.write_text('udp dport 123 accept comment "fragebogenpi-ntp"\n')
        result = self.sh.run("time_server_live_ntp_state", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("nft insert", self.sh.log.read_text())


class WartezimmerTimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sh = ShellHarness(self, "wartezimmer.sh")

    def tearDown(self) -> None:
        self.sh.close()

    def test_client_uses_only_configured_server_and_warns_bounded(self) -> None:
        result = self.sh.run(
            r'''
            CHRONY_CONF="$TEST_ROOT/chrony.conf"
            FRAGEBOGENPI_SERVER_IP="10.23.0.1"
            configure_ntp_client
            ''',
            extra_env={"CHRONYC_EXIT": "1"},
        )
        config = (self.sh.root / "chrony.conf").read_text()
        self.assertIn("server 10.23.0.1 iburst", config)
        self.assertIn("port 0", config)
        self.assertIn("cmdport 0", config)
        self.assertNotIn("pool ", config)
        self.assertNotIn("sourcedir", config)
        self.assertIn("versucht es weiter", result.stderr)
        self.assertIn("chronyc waitsync 5 0.0 0.0 1", self.sh.log.read_text())

    def test_time_prompt_accepts_boundaries_and_corrects_invalid_value(self) -> None:
        result = self.sh.run(
            r'''
            ask_daily_poweroff_config <<< $'24:00\n23:59\n../etc/passwd\n\n'
            printf '%s|%s\n' "$POWEROFF_TIME" "$POWEROFF_TIMEZONE"
            '''
        )
        self.assertIn("23:59|Europe/Berlin", result.stdout)
        self.assertIn("Bitte HH:MM", result.stderr)
        self.assertIn("Bitte eine vorhandene IANA-Zeitzone", result.stderr)

        result = self.sh.run(
            r'''
            ask_daily_poweroff_config <<< $'00:00\n\n'
            printf '%s\n' "$POWEROFF_TIME"
            '''
        )
        self.assertTrue(result.stdout.rstrip().endswith("00:00"))

    def test_timezone_validation_rejects_traversal(self) -> None:
        result = self.sh.run(
            r'''
            is_valid_poweroff_timezone Europe/Berlin
            ! is_valid_poweroff_timezone ../etc/passwd
            ! is_valid_poweroff_timezone /etc/passwd
            if is_valid_poweroff_timezone zone.tab; then exit 1; fi
            if is_valid_poweroff_timezone zone1970.tab; then exit 1; fi
            '''
        )
        self.assertEqual(result.returncode, 0)

    def test_timer_reconfiguration_and_disable_are_safe_and_idempotent(self) -> None:
        service = self.sh.root / "wartezimmer-poweroff.service"
        timer = self.sh.root / "wartezimmer-poweroff.timer"
        self.sh.run(
            r'''
            POWEROFF_SERVICE="$TEST_ROOT/wartezimmer-poweroff.service"
            POWEROFF_TIMER="$TEST_ROOT/wartezimmer-poweroff.timer"
            POWEROFF_TIME="23:59"
            POWEROFF_TIMEZONE="Europe/Berlin"
            configure_daily_poweroff
            configure_daily_poweroff
            '''
        )
        service_text = service.read_text()
        timer_text = timer.read_text()
        self.assertIn("chronyc waitsync 1 1.0 0.0 1", service_text)
        self.assertIn("$$(TZ=Europe/Berlin", service_text)
        self.assertIn("date +%%H:%%M", service_text)
        self.assertIn('= "23:59"', service_text)
        self.assertIn("ExecStart=/usr/bin/systemctl poweroff", service_text)
        self.assertIn("OnCalendar=*-*-* 23:59:00 Europe/Berlin", timer_text)
        self.assertIn("AccuracySec=1s", timer_text)
        self.assertIn("RandomizedDelaySec=0", timer_text)
        self.assertIn("Persistent=false", timer_text)
        commands = self.sh.log.read_text()
        self.assertNotIn("systemctl start wartezimmer-poweroff.service", commands)
        self.assertEqual(commands.count("systemctl start wartezimmer-poweroff.timer"), 2)

        self.sh.run(
            r'''
            POWEROFF_SERVICE="$TEST_ROOT/wartezimmer-poweroff.service"
            POWEROFF_TIMER="$TEST_ROOT/wartezimmer-poweroff.timer"
            POWEROFF_TIME=""
            configure_daily_poweroff
            '''
        )
        self.assertFalse(service.exists())
        self.assertFalse(timer.exists())
        commands = self.sh.log.read_text()
        self.assertIn("systemctl disable wartezimmer-poweroff.timer", commands)

    def test_nein_disables_without_timezone_question(self) -> None:
        result = self.sh.run(
            r'''
            POWEROFF_TIME="12:00"
            ask_daily_poweroff_config <<< $'nein\n'
            printf '<%s>\n' "$POWEROFF_TIME"
            '''
        )
        self.assertTrue(result.stdout.rstrip().endswith("<>"))

    def test_poweroff_conditions_skip_unsynced_and_late_clock(self) -> None:
        self.sh.run(r'''
            POWEROFF_SERVICE="$TEST_ROOT/wartezimmer-poweroff.service"
            POWEROFF_TIMER="$TEST_ROOT/wartezimmer-poweroff.timer"
            POWEROFF_TIME="18:30"
            configure_daily_poweroff
        ''')
        self.sh._stub("date", 'printf "%s\\n" "$STUB_TIME"')
        unit = (self.sh.root / "wartezimmer-poweroff.service").read_text()
        conditions = [line.split("=", 1)[1] for line in unit.splitlines()
                      if line.startswith("ExecCondition=")]
        self.assertEqual(len(conditions), 2)
        env = os.environ.copy()
        env["STUB_LOG"] = str(self.sh.log)
        # Expand exactly the systemd escapes used here, then execute only conditions.
        commands = [shlex.split(line.replace("%%", "%").replace("$$", "$"))
                    for line in conditions]
        commands[0][0] = str(self.sh.bin / "chronyc")
        commands[1][2] = commands[1][2].replace("/usr/bin/date", str(self.sh.bin / "date"))
        for synced, clock, expected in ((False, "18:30", False),
                                        (True, "18:30", True),
                                        (True, "18:31", False),
                                        (True, "19:00", False)):
            with self.subTest(synced=synced, clock=clock):
                env.update(CHRONYC_EXIT="0" if synced else "1", STUB_TIME=clock)
                would_poweroff = all(subprocess.run(command, env=env, capture_output=True).returncode == 0
                                    for command in commands)
                self.assertEqual(would_poweroff, expected)
        self.assertNotIn("systemctl poweroff", self.sh.log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
