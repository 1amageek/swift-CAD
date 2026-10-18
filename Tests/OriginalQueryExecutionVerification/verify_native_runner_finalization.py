import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

parser = argparse.ArgumentParser(description='Check owned native runner finalization.')
parser.add_argument('--source', type=Path, default=Path(__file__).with_name('native_tests.py'))
parser.add_argument('--output', type=Path, required=True)
options = parser.parse_args()
SOURCE = options.source.resolve()
ROOT = SOURCE.parents[2]
OUTPUT = options.output.resolve()
if OUTPUT == ROOT or ROOT in OUTPUT.parents:
    parser.error('--output must be outside the selected package')
tree = ast.parse(SOURCE.read_text())
function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'run')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


namespace = dict(os=os, signal=signal, subprocess=subprocess, time=time,
                 ROOT=ROOT, RSS_BYTES=10 * 1024**3, require=require,
                 digest=lambda p: hashlib.sha256(p.read_bytes()).hexdigest())
exec(compile(ast.Module(body=[function], type_ignores=[]), str(SOURCE), 'exec'), namespace)
run = namespace['run']
RESULTS = {}


class OwnedRunTests(unittest.TestCase):
    def invoke(self, name, program, limit=3):
        with tempfile.TemporaryDirectory(prefix='swift-cad-runner-control-') as folder:
            path = Path(folder) / 'child.log'
            result = run([sys.executable, '-c', program], path, dict(os.environ),
                         time.monotonic() + 10, limit)
            self.assertEqual(result['logSHA256'], hashlib.sha256(path.read_bytes()).hexdigest())
            RESULTS[name] = result
            return result

    def test_success(self):
        result = self.invoke('success', 'print("owned success", flush=True)')
        self.assertEqual(result['exitCode'], 0)
        self.assertIsNone(result['stopReason'])
        self.assertFalse(result['cleanupIncomplete'])
        self.assertFalse(result['cleanupSignals'])

    def test_exit_seven(self):
        result = self.invoke('exit7', 'raise SystemExit(7)')
        self.assertEqual(result['exitCode'], 7)
        self.assertIsNone(result['stopReason'])
        self.assertFalse(result['cleanupIncomplete'])

    def test_timeout(self):
        result = self.invoke('timeout', 'import time; time.sleep(30)', limit=0.1)
        self.assertEqual(result['stopReason'], 'wallLimit')
        self.assertNotEqual(result['exitCode'], 0)
        self.assertFalse(result['cleanupIncomplete'])
        self.assertTrue(result['cleanupSignals'])
        self.assertTrue(all(event['group'] == result['launchIdentity']['pid']
                            for event in result['cleanupSignals']))

    def held_child_control(self, name, signal_error=False, identity_error=False):
        children = []
        real_popen, real_getsid = subprocess.Popen, os.getsid
        root_pid = None

        def create(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            if args[0][0] == sys.executable:
                children.append(child)
            return child

        def session(pid):
            if identity_error and children and pid == children[0].pid:
                # Initial creation proof succeeds; later cleanup proof is refused.
                nonlocal root_pid
                if root_pid is None:
                    root_pid = pid
                else:
                    return pid + 1
            return real_getsid(pid)

        try:
            with patch.object(subprocess, 'Popen', side_effect=create), \
                    patch.object(os, 'getsid', side_effect=session), \
                    patch.object(os, 'killpg', side_effect=PermissionError(1, 'control denied')) as kill:
                result = self.invoke(name, 'import time; time.sleep(30)', limit=0.1)
                self.assertTrue(result['cleanupIncomplete'])
                self.assertEqual(result['stopReason'], 'wallLimit')
                self.assertNotEqual(result['exitCode'], 0)
                self.assertTrue(result['cleanupErrors'])
                if identity_error:
                    kill.assert_not_called()
                else:
                    self.assertTrue(kill.called)
                    self.assertTrue(all(call.args[0] == children[0].pid for call in kill.call_args_list))
        finally:
            # These exact Popen objects remain exclusively held, unreaped children.
            for child in children:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=3)

    def test_cleanup_permission_failure_is_receipted(self):
        self.held_child_control('deniedCleanup', signal_error=True)

    def test_unproven_session_is_never_signaled(self):
        self.held_child_control('unprovenSession', identity_error=True)

    def test_cancelled_monitor(self):
        real_sleep = time.sleep
        interrupted = False

        def sleep(seconds):
            nonlocal interrupted
            if not interrupted:
                interrupted = True
                raise KeyboardInterrupt('control cancellation')
            return real_sleep(seconds)

        with patch.object(time, 'sleep', side_effect=sleep):
            result = self.invoke('cancelled', 'import time; time.sleep(30)')
        self.assertEqual(result['stopReason'], 'cancelled')
        self.assertNotEqual(result['exitCode'], 0)
        self.assertTrue(any(error['type'] == 'KeyboardInterrupt' for error in result['cleanupErrors']))

    def test_log_hash_permission_failure_is_receipted(self):
        with tempfile.TemporaryDirectory(prefix='swift-cad-runner-control-') as folder:
            path = Path(folder) / 'child.log'
            with patch.dict(namespace, digest=lambda p: (_ for _ in ()).throw(
                    PermissionError(1, 'control hash denied'))):
                result = run([sys.executable, '-c', 'print("completed child")'], path,
                             dict(os.environ), time.monotonic() + 10, 3)
            RESULTS['deniedHash'] = result
            self.assertEqual(result['exitCode'], 0)
            self.assertIsNotNone(result['stopReason'])
            self.assertTrue(result['cleanupIncomplete'])
            self.assertIsNone(result['logSHA256'])
            self.assertTrue(any(error['phase'] == 'logMetadata' and error['errno'] == 1
                                for error in result['cleanupErrors']))

    def test_log_metadata_permission_failure_is_receipted(self):
        with tempfile.TemporaryDirectory(prefix='swift-cad-runner-control-') as folder:
            path = Path(folder) / 'child.log'
            with patch.object(Path, 'is_file', side_effect=PermissionError(1, 'control stat denied')):
                result = run([sys.executable, '-c', 'print("completed child")'], path,
                             dict(os.environ), time.monotonic() + 10, 3)
            RESULTS['deniedMetadata'] = result
            self.assertIsNotNone(result['stopReason'])
            self.assertTrue(result['cleanupIncomplete'])
            self.assertIsNone(result['logSHA256'])
            self.assertTrue(any(error['phase'] == 'logMetadata' and error['errno'] == 1
                                for error in result['cleanupErrors']))

    def test_raced_foreign_subgroup_is_never_signaled(self):
        real_popen, real_output, real_getsid, real_killpg = (
            subprocess.Popen, subprocess.check_output, os.getsid, os.killpg)
        foreign = real_popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                             start_new_session=True)
        children, attempts = [], []

        def create(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            if args[0][0] == sys.executable:
                children.append(child)
            return child

        def stale_snapshot(*args, **kwargs):
            output = real_output(*args, **kwargs)
            if children:
                # The old observation claims this recycled subgroup belonged to the
                # driver. Its ID is now held by a real, unrelated test-owned session.
                rows = [line for line in output.splitlines()
                        if int(line.split()[0]) != foreign.pid]
                rows.append(f'{foreign.pid} {children[0].pid} {foreign.pid} {os.getuid()} 1')
                return '\n'.join(rows) + '\n'
            return output

        def stale_session(pid):
            return children[0].pid if children and pid == foreign.pid else real_getsid(pid)

        def signal_group(group, signum):
            attempts.append((group, signum))
            if group == foreign.pid:
                raise AssertionError('A raced unpinned subgroup was signaled')
            return real_killpg(group, signum)

        try:
            with patch.object(subprocess, 'Popen', side_effect=create), \
                    patch.object(subprocess, 'check_output', side_effect=stale_snapshot), \
                    patch.object(os, 'getsid', side_effect=stale_session), \
                    patch.object(os, 'killpg', side_effect=signal_group):
                result = self.invoke('racedForeignSubgroup', 'import time; time.sleep(30)', limit=0.1)
            self.assertTrue(result['cleanupIncomplete'])
            self.assertEqual(result['stopReason'], 'wallLimit')
            self.assertTrue(attempts)
            self.assertTrue(all(group == children[0].pid for group, signum in attempts))
            self.assertIsNone(foreign.poll())
        finally:
            for child in [*children, foreign]:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=3)


if __name__ == '__main__':
    started = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(OwnedRunTests)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    OUTPUT.write_text(json.dumps(dict(
        status='passed' if outcome.wasSuccessful() else 'failed',
        testsRun=outcome.testsRun, failures=len(outcome.failures), errors=len(outcome.errors),
        elapsedSeconds=time.monotonic() - started, cases=RESULTS), indent=2) + '\n')
    raise SystemExit(0 if outcome.wasSuccessful() else 1)
