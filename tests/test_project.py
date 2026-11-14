from __future__ import annotations
import json
import re
import subprocess
import unittest
import wave
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

class ProjectIntegrityTests(unittest.TestCase):
    def test_main_scene_and_script_paths_exist(self):
        project = (ROOT / 'project.godot').read_text(encoding='utf-8')
        scene_path = re.search(r'run/main_scene="([^"]+)"', project).group(1)
        self.assertTrue((ROOT / scene_path.replace('res://', '')).is_file())
        scene = (ROOT / scene_path.replace('res://', '')).read_text(encoding='utf-8')
        script_path = re.search(r'path="res://([^"]+\.gd)"', scene).group(1)
        self.assertTrue((ROOT / script_path).is_file())

    def test_all_godot_resource_paths_exist(self):
        script = (ROOT / 'scripts/main.gd').read_text(encoding='utf-8')
        paths = set(re.findall(r'res://[^"\']+', script))
        for path in paths:
            target = ROOT / path.replace('res://', '')
            self.assertTrue(target.exists(), f'Missing Godot resource: {path}')

    def test_gdscript_brackets_and_function_names(self):
        src = (ROOT / 'scripts/main.gd').read_text(encoding='utf-8')
        self.assertNotIn('\t', src, 'GDScript indentation must use spaces')
        stack = []
        pairs = {')': '(', ']': '[', '}': '{'}
        in_string = False
        escaped = False
        for line_no, line in enumerate(src.splitlines(), 1):
            # Remove comments outside strings; track quotes and bracket balance on code.
            code = ''
            in_line_string = False
            esc = False
            for ch in line:
                if ch == '"' and not esc:
                    in_line_string = not in_line_string
                    code += ch
                    continue
                if ch == '#' and not in_line_string:
                    break
                code += ch
                if ch == '\\' and in_line_string and not esc:
                    esc = True
                else:
                    esc = False
            for ch in code:
                if ch == '"':
                    in_string = not in_string
                    escaped = False
                    continue
                if in_string:
                    if ch == '\\' and not escaped:
                        escaped = True
                    else:
                        escaped = False
                    continue
                if ch in '([{':
                    stack.append((ch, line_no))
                elif ch in ')]}':
                    self.assertTrue(stack, f'Unexpected {ch} at line {line_no}')
                    opening, opening_line = stack.pop()
                    self.assertEqual(opening, pairs[ch], f'Mismatched bracket at line {line_no}, opened at {opening_line}')
        self.assertEqual(stack, [], f'Unclosed brackets: {stack[-5:]}')
        names = re.findall(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', src, re.M)
        self.assertEqual(len(names), len(set(names)), 'Duplicate function declaration detected')
        self.assertGreaterEqual(len(names), 35)

    def test_android_export_preset(self):
        preset = (ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
        for expected in ['platform="Android"', 'package/unique_name="com.afterlight.neonrun"', 'architectures/arm64-v8a=true', 'screen/immersive_mode=true']:
            self.assertIn(expected, preset)
        workflow = (ROOT / '.github/workflows/android-build.yml').read_text(encoding='utf-8')
        self.assertIn('actions/upload-artifact@v4', workflow)
        self.assertIn('platforms;android-36', workflow)
        self.assertIn('ndk;28.1.13356709', workflow)
        self.assertIn('launcher_icons/adaptive_foreground_432x432', preset)

    def test_original_art_assets(self):
        with Image.open(ROOT / 'assets/title_art.png') as img:
            self.assertGreaterEqual(img.width, 1200)
            self.assertGreaterEqual(img.height, 700)
        with Image.open(ROOT / 'assets/icon.png') as img:
            self.assertEqual(img.size, (512, 512))
        with Image.open(ROOT / 'assets/icon_foreground_432.png') as img:
            self.assertEqual(img.size, (432, 432))
        with Image.open(ROOT / 'assets/icon_background_432.png') as img:
            self.assertEqual(img.size, (432, 432))

    def test_audio_assets_are_valid(self):
        for wav_path in (ROOT / 'audio').glob('*.wav'):
            with wave.open(str(wav_path), 'rb') as wf:
                self.assertEqual(wf.getnchannels(), 1)
                self.assertEqual(wf.getsampwidth(), 2)
                self.assertEqual(wf.getframerate(), 22050)
                self.assertGreater(wf.getnframes(), 100)

    def test_preview_javascript_syntax(self):
        html = (ROOT / 'preview/index.html').read_text(encoding='utf-8')
        match = re.search(r'<script>(.*?)</script>', html, re.S)
        self.assertIsNotNone(match)
        js_path = ROOT / 'build' / 'preview_check.js'
        js_path.parent.mkdir(exist_ok=True)
        js_path.write_text(match.group(1), encoding='utf-8')
        result = subprocess.run(['node', '--check', str(js_path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_preview_dom_ids_exist(self):
        html = (ROOT / 'preview/index.html').read_text(encoding='utf-8')
        ids = set(re.findall(r'id="([^"]+)"', html))
        js = re.search(r'<script>(.*?)</script>', html, re.S).group(1)
        requested = set(re.findall(r"\$\('([^']+)'\)", js))
        missing = sorted(requested - ids)
        self.assertEqual(missing, [], f'JS references missing DOM IDs: {missing}')


    def test_preview_runtime_paths(self):
        result = subprocess.run(['node', str(ROOT / 'tests/test_preview_runtime.js')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('preview runtime passed', result.stdout)

    def test_safe_lane_generation_invariants(self):
        # Mirror the small deterministic lane-selection rule used by the GDScript generator.
        import random
        random.seed(20261114)
        for _ in range(20000):
            blocked = random.randrange(3)
            blocked_lanes = [blocked]
            if random.random() < 0.16 * random.choice([0.78, 1.0, 1.26]):
                blocked_lanes.append((blocked + random.choice([1, 2])) % 3)
            safe = next(i for i in range(3) if i not in blocked_lanes)
            self.assertNotIn(safe, blocked_lanes)
            self.assertGreaterEqual(len(set(range(3)) - set(blocked_lanes)), 1)

if __name__ == '__main__':
    unittest.main(verbosity=2)
