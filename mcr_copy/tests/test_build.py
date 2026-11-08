import importlib.util
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]

class BuildTests(unittest.TestCase):
    def test_complete_source_roundtrip(self):
        path=ROOT/'build_mcr_copy.py'
        self.assertTrue(path.exists(),'missing full-copy builder')
        spec=importlib.util.spec_from_file_location('builder',path)
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        raw=(ROOT/'mcr_copy/vendor/mcrm-1.15.5.lua').read_bytes()
        result,patches=mod.assemble(raw)
        # Removing precisely the recorded integrations must restore every byte.
        restored=result
        for before,after in reversed(patches):
            self.assertEqual(restored.count(after),1)
            restored=restored.replace(after,before,1)
        self.assertEqual(restored,raw)
        self.assertEqual(len(re.findall(rb'\.OnFrame\(',raw)),19)
        self.assertEqual(len(re.findall(rb'\.OnFrame\(',result)),19)
        self.assertIn(b'PalatkaMCR.draw_center()',result)
        self.assertIn(b'PalatkaMCR.capture(h)',result)
        self.assertGreater(result.index(b'PalatkaMCR.start();'),result.index(b'while not isSampAvailable()'))
        with self.assertRaises(ValueError):mod.assemble(raw+b'changed')

if __name__=='__main__':unittest.main()
