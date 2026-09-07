"""Local packaging fails closed without touching installations or credentials."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('package_local', Path(__file__).with_name('package-local.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class LocalPackageTests(unittest.TestCase):
    def test_test_failure_stops_before_build_or_packaging(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(package, 'ROOT', Path(temp)), \
                patch.object(package, 'version_info', return_value=('0.1.0', '1')), \
                patch.object(package, 'run', side_effect=RuntimeError('Tests failed')) as run:
            with self.assertRaisesRegex(RuntimeError, 'Tests failed'):
                package.main()
            self.assertEqual(run.call_count, 1)
            self.assertIn('test', run.call_args.args)
            self.assertEqual(len(list(Path(temp).rglob('tests.log'))), 1)
            self.assertEqual(list(Path(temp).rglob('*.dmg')), [])


if __name__ == '__main__':
    unittest.main()
