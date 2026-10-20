"""Run inside a disposable sandbox; integration uses TEST_DOTFILES read-only."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("backports", REPO / "tools/backport-omarchy.py")
backports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backports)


class BackportTests(unittest.TestCase):
    @unittest.skipUnless(Path("/usr/share/omarchy/default/hypr/bootstrap.lua").exists(), "requires an installed upstream source")
    def test_generator_accepts_current_upstream_in_scratch(self):
        spec = importlib.util.spec_from_file_location("vendor", REPO / "tools/vendor-omarchy.py")
        vendor = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(vendor)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "runtime"
            vendor.copy_runtime(Path("/usr/share/omarchy"), root)
            vendor.patch_runtime(root, "4.0.6-1")
            self.assertEqual(backports.plan_runtime(root, renamed=False), {})
            provision = (root / "bin/omarchy-provision-user").read_text()
            self.assertIn('XDG_CURRENT_DESKTOP= xdg-settings set default-web-browser firefox.desktop', provision)

    def test_exact_context_and_idempotence(self):
        hunks = [{"old": "before\n", "new": "after\n"}]
        result = backports.apply_hunks("before\ncustom\n", hunks, "test", False)
        self.assertEqual(result, "after\ncustom\n")
        self.assertEqual(backports.apply_hunks(result, hunks, "test", False), result)
        with self.assertRaises(ValueError):
            backports.apply_hunks("unexpected\n", hunks, "test", False)

    def test_plan_does_not_partially_write_on_conflict(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entries = json.loads(backports.PATCHSET.read_text())["files"]
            first = root / backports.rename_name(entries[0]["path"])
            first.parent.mkdir(parents=True)
            text = "\n# unrelated context\n".join(
                backports.converted(h["old"], entries[0]["path"], True)
                for h in entries[0]["hunks"])
            first.write_text(text)
            with self.assertRaises(ValueError):
                backports.plan_runtime(root)
            self.assertEqual(first.read_text(), text)


@unittest.skipUnless(os.environ.get("TEST_DOTFILES"), "set TEST_DOTFILES for integration")
class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = Path(os.environ["TEST_DOTFILES"])
        self.dotfiles = self.root / "dotfiles"
        self.runtime = self.dotfiles / "platform/.local/share/wh01s17"
        # Only the bounded review scope, never unrelated user files or secrets.
        entries = json.loads(backports.PATCHSET.read_text())["files"]
        for entry in entries:
            relative = backports.rename_name(entry["path"])
            original = source / "platform/.local/share/wh01s17" / relative
            if original.exists():
                target = self.runtime / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, target)
        self.runtime.mkdir(parents=True, exist_ok=True)
        (self.runtime / "UPSTREAM").write_text("Omarchy 4.0.4-1\n")
        relative = "desktop/.config/omarchy/plugins/wh01s17.monitor/Panel.qml"
        target = self.dotfiles / relative
        target.parent.mkdir(parents=True)
        shutil.copy2(source / relative, target)
        changes = backports.plan_runtime(self.runtime)
        changes.update(backports.plan_monitor(self.dotfiles))
        backports.write_changes(changes)

    def test_second_application_and_script_syntax(self):
        self.assertEqual(backports.plan_runtime(self.runtime), {})
        self.assertEqual(backports.plan_monitor(self.dotfiles), {})
        for script in (self.runtime / "bin").iterdir():
            subprocess.run(["bash", "-n", script], check=True)
        for relative in ("install/user/mise-work.sh",):
            subprocess.run(["bash", "-n", self.runtime / relative], check=True)
        self.assertTrue(os.access(self.runtime / "bin/wh01s17-hw-nvidia-display", os.X_OK))
        self.assertNotIn("{{ cwd }}/bin", (self.runtime / "install/user/mise-work.sh").read_text())

    def mock(self, name, body):
        self.mock_bin.mkdir(exist_ok=True)
        path = self.mock_bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def test_package_operands_never_become_privileged_options(self):
        self.mock_bin = self.root / "bin"
        log = self.root / "argv.jsonl"
        self.mock("wh01s17-pkg-missing", "exit 0")
        self.mock("sudo", 'exec "$@"')
        recorder = '#!/usr/bin/python3\nimport os,json,sys\nwith open(os.environ["ARGV_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
        for name in ("pacman", "yay"):
            path = self.mock_bin / name
            path.write_text(recorder)
            path.chmod(0o755)
        environment = {"PATH": f"{self.mock_bin}:/usr/bin", "ARGV_LOG": str(log)}
        for name in ("wh01s17-pkg-add", "wh01s17-pkg-aur-add"):
            log.write_text("")
            subprocess.run([self.runtime / "bin" / name, "--hookdir=/untrusted", "harmless"],
                           env=environment, check=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(calls[0], ["-S", "--noconfirm", "--needed", "--", "--hookdir=/untrusted", "harmless"])
            self.assertEqual(calls[1], ["-Q", "--", "--hookdir=/untrusted"])

    def test_idle_zero_and_calendar_civil_dates(self):
        idle = self.runtime / "shell/plugins/services/idle/IdleModel.js"
        clock = self.runtime / "shell/plugins/panels/clock/Model.js"
        program = '''const fs = require("fs"), vm = require("vm"), assert = require("assert");
function load(path) {
  const sandbox = {module: {exports: {}}};
  vm.runInNewContext(fs.readFileSync(path, "utf8").replace(/^\\.pragma library\\s*/, ""), sandbox);
  return sandbox.module.exports;
}
const idle = load(process.argv[1]);
assert.equal(idle.firstIdleTimeout(0, 300), 300);
assert.equal(idle.firstIdleTimeout(150, 0), 150);
assert.equal(idle.firstIdleTimeout(0, 0), 0);
assert.equal(idle.delayAfterFirstIdle(0, 150), 0);
const clock = load(process.argv[2]);
const days = clock.monthGrid(2026, 8, 1, "2026-09-06").flatMap(week => week.days);
assert.equal(days.length, 42);
assert.equal(new Set(days.map(d => d.key)).size, 42);
assert.equal(days.filter(d => d.inMonth).length, 30);
'''
        subprocess.run([shutil.which("node"), "--jitless", "--max-old-space-size=64", "-e", program, str(idle), str(clock)],
                       env={"PATH": "/usr/bin", "TZ": "America/Santiago"}, check=True)

    def test_lock_reads_actual_state_and_monitor_customizations_survive(self):
        lock = (self.runtime / "shell/plugins/lock/Service.qml").read_text()
        self.assertIn('if (!root.currentlyLocked() && !root.beginLock())', lock)
        self.assertIn('wh01s17-hyprland-session-lock-stranded', lock)
        monitor = (self.dotfiles / "desktop/.config/omarchy/plugins/wh01s17.monitor/Panel.qml").read_text()
        self.assertNotIn('["hyprctl", "keyword", "monitor"', monitor)
        self.assertIn('actionProc.command = ["hyprctl", "eval", expr]', monitor)
        self.assertIn('function updateDisplays', monitor)
        self.assertIn('unmirrored=1', monitor)


class MiseCleanupTests(unittest.TestCase):
    def test_stock_ignored_symlink_and_failed_revocation(self):
        for case in ("stock", "ignored", "symlink", "failure"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                home, mock_bin = root / "home", root / "bin"
                (home / "Work").mkdir(parents=True)
                mock_bin.mkdir()
                log = root / "calls"
                mise = mock_bin / "mise"
                mise.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >>"$CALL_LOG"\nexit "${MOCK_STATUS:-0}"\n')
                mise.chmod(0o755)
                config = home / "Work/.mise.toml"
                original = '[env]\n_.path = "{{ cwd }}/bin"\n'
                if case == "symlink":
                    target = home / "custom-mise.toml"
                    target.write_text(original + 'KEEP = "yes"\n')
                    config.symlink_to(target)
                else:
                    config.write_text(original)
                if case == "ignored":
                    ignored = home / ".local/state/mise/ignored-configs/work"
                    ignored.parent.mkdir(parents=True)
                    ignored.symlink_to(home / "Work")
                environment = {"HOME": str(home), "PATH": f"{mock_bin}:/usr/bin", "CALL_LOG": str(log), "WH01S17_MISE_BIN": str(mise)}
                if case == "failure":
                    environment["MOCK_STATUS"] = "1"
                result = subprocess.run(["bash", REPO / "patches/mise-work-cleanup.sh"],
                                        env=environment, capture_output=True)
                marker = home / ".local/state/wh01s17/fixes/mise-work-path-v1"
                if case == "failure":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(marker.exists())
                    self.assertEqual(config.read_text(), original)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertTrue(marker.exists())
                    if case == "symlink":
                        self.assertTrue(config.is_symlink())
                        self.assertIn('KEEP = "yes"', config.read_text())
                        self.assertNotIn("{{ cwd }}/bin", config.read_text())
                    else:
                        self.assertFalse(config.exists())
                    if case == "ignored":
                        self.assertFalse(log.exists())
                        self.assertTrue(ignored.is_symlink())

    def test_custom_config_backup_trust_revocation_and_once_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, mock_bin = root / "home", root / "bin"
            (home / "Work").mkdir(parents=True)
            mock_bin.mkdir()
            log = root / "calls"
            mise = mock_bin / "mise"
            mise.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >>"$CALL_LOG"\n')
            mise.chmod(0o755)
            config = home / "Work/.mise.toml"
            original = '[env]\n_.path = "{{ cwd }}/bin"\nKEEP = "yes"\n'
            config.write_text(original)
            environment = {"HOME": str(home), "PATH": f"{mock_bin}:/usr/bin", "CALL_LOG": str(log), "WH01S17_MISE_BIN": str(mise)}
            script = REPO / "patches/mise-work-cleanup.sh"
            subprocess.run(["bash", script], env=environment, check=True, capture_output=True)
            self.assertNotIn("{{ cwd }}/bin", config.read_text())
            self.assertIn('KEEP = "yes"', config.read_text())
            self.assertEqual(next(config.parent.glob(".mise.toml.bak.*")).read_text(), original)
            self.assertIn("trust --untrust", log.read_text())
            before = log.read_text()
            subprocess.run(["bash", script], env=environment, check=True, capture_output=True)
            self.assertEqual(log.read_text(), before)


if __name__ == "__main__":
    unittest.main()
