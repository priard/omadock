"""The live harness's startup gate.

A live suite's first read could land before the probe's dock had applied its
config copy and fail its first assertion - measured 1 raced read in 8 raw
sessions.

The wait belongs to the harness's startup path, once, so no suite's first read
has to race it: `probe_start` now requires `probe_ready`, which is true only
when the dock's state() reports configApplied: true. CI cannot run the live suites,
so this is the guard that the gate cannot be dropped (or duplicated at a call
site) without a red test - the failure mode it prevents is a suite that is green
by luck.

PROBE_SH overrides the script under test, to check the test can fail.
"""
import os
import pathlib
import re
import shlex
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIVE = ROOT / "tests" / "live"
HARNESS = LIVE / "probe.sh"
PROBE = pathlib.Path(os.environ.get("PROBE_SH", HARNESS))


def probe_start_body():
    """probe_start's body, from the definition to its closing brace."""
    text = PROBE.read_text()
    match = re.search(r"^probe_start\(\) \{\n(.*?)^\}$", text, re.S | re.M)
    assert match, "probe_start is not defined in %s" % PROBE.name
    return match.group(1)


class ReadyWitness(unittest.TestCase):
    """The witness itself: configApplied true, and nothing else."""

    def run_ready(self, stub):
        """probe_ready's exit status with probe_ipc replaced by `stub`."""
        script = "\n".join([
            "set -u",
            '. "%s" || { echo SOURCE-FAILED; exit 9; }' % PROBE,
            "probe_ipc() { %s; }" % stub,
            "probe_ready",
        ])
        result = subprocess.run(["bash", "-c", script], capture_output=True,
                                text=True, timeout=10)
        self.assertNotIn("SOURCE-FAILED", result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 9, result.stderr)
        return result.returncode

    def test_before_the_config_is_applied_is_not_ready(self):
        # The raced read: the dock answered IPC, its config copy is not applied.
        self.assertEqual(self.run_ready('echo \'{"configApplied":false}\''), 1)
        self.assertEqual(self.run_ready('echo "{}"'), 1)

    def test_an_applied_config_is_ready(self):
        self.assertEqual(self.run_ready('echo \'{"visible":true,"configApplied":true}\''), 0)

    def test_a_failed_or_odd_answer_is_not_ready(self):
        # A dead instance, an unknown endpoint, and an answer that is not a
        # state object: each must keep the caller waiting, not release it.
        self.assertEqual(self.run_ready("return 1"), 1)
        self.assertEqual(self.run_ready('echo "ipc: target omadock not running"'), 1)
        self.assertEqual(self.run_ready('echo "[true]"'), 1)


class StartupGate(unittest.TestCase):
    """`probe_start` waits on the witness before it reports success."""

    def test_probe_start_requires_the_gate(self):
        lines = probe_start_body().splitlines()
        gate = [i for i, l in enumerate(lines) if "probe_ready" in l]
        success = [i for i, l in enumerate(lines) if l.strip() == "return 0"]
        self.assertTrue(gate, "probe_start must require probe_ready before returning")
        self.assertTrue(success, "probe_start has no success path")
        self.assertLess(gate[0], success[0],
                        "the gate must be part of the condition that returns 0")
        # In the same condition as the IPC answer: a dock that answers only
        # after its config is applied must not slip through either.
        self.assertIn("ipc call omadock state", lines[gate[0]])

    def test_the_gate_lives_in_the_harness_alone(self):
        # One owner for the rule: a suite that waited on its own would be the
        # drift this gate exists to prevent.
        holders = sorted(p.name for p in LIVE.glob("*.sh")
                         if p != HARNESS and "probe_ready" in p.read_text())
        self.assertEqual(holders, [])


if __name__ == "__main__":
    unittest.main()
