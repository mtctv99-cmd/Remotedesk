import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from msi import preprocess


class AuditFixesTest(unittest.TestCase):
    def test_msi_executes_binary_as_argument_list(self):
        proc = SimpleNamespace(communicate=lambda: (b'2026-11-18 09:00', None))
        with tempfile.TemporaryDirectory() as tmp, patch.object(subprocess, 'Popen', return_value=proc) as popen:
            args = SimpleNamespace(version='1.2.3', revision_version=0)
            self.assertTrue(preprocess.init_global_vars(Path(tmp) / 'folder with spaces', 'DeskAgent', args))
            self.assertEqual(popen.call_args.args[0], [str(Path(tmp) / 'folder with spaces' / 'DeskAgent.exe'), '--build-date'])
            self.assertFalse(popen.call_args.kwargs.get('shell', False))


if __name__ == '__main__':
    unittest.main()
