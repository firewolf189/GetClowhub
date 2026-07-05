import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "watch_nas_images.py"
SPEC = importlib.util.spec_from_file_location("watch_nas_images", SCRIPT_PATH)
watch_nas_images = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules["watch_nas_images"] = watch_nas_images
SPEC.loader.exec_module(watch_nas_images)


class WatchNasImagesSafetyTests(unittest.TestCase):
    def test_default_batch_limit_keeps_vision_context_bounded(self):
        self.assertLessEqual(watch_nas_images.DEFAULT_CONFIG["batch_limit"], 12)

    def test_default_trigger_uses_isolated_session_per_batch(self):
        command = watch_nas_images.DEFAULT_CONFIG["trigger"]["command"]
        self.assertIn("--session-id", command)
        session_id_arg = command[command.index("--session-id") + 1]
        self.assertIn("{batch_id}", session_id_arg)


if __name__ == "__main__":
    unittest.main()
