import json
from pathlib import Path
import unittest
from uuid import uuid4

from recorder import analyze_events, save_json


def clicks(*pairs):
    return [event for down, up in pairs for event in
            ({"kind": "down", "t_ms": down}, {"kind": "up", "t_ms": up})]


class RecorderTests(unittest.TestCase):
    def test_bounce_estimate_and_prediction(self):
        summary = analyze_events(clicks((0, 10), (13, 15), (1000, 1020)), 2)
        self.assertEqual(summary["extra_clicks"], 1)
        self.assertEqual(summary["extra_clicks_per_100_intended"], 50)
        self.assertEqual(summary["suggested_threshold_ms"], 4)
        self.assertEqual(summary["predicted_clicks_by_threshold_ms"]["50"], 2)
        self.assertEqual(summary["release_to_press_ms"], [3, 985])

    def test_no_fault_and_missing_click(self):
        self.assertIsNone(analyze_events(clicks((0, 20), (1000, 1020)), 2)["suggested_threshold_ms"])
        self.assertEqual(analyze_events(clicks((0, 20)), 2)["missing_clicks"], 1)

    def test_overlapping_clusters_have_no_recommendation(self):
        self.assertIsNone(analyze_events(clicks((0, 10), (13, 14), (17, 18)), 2)["suggested_threshold_ms"])
        self.assertIsNone(analyze_events(clicks((0, 10), (500, 510)), 1)["suggested_threshold_ms"])

    def test_invalid_data(self):
        for events, count in [(clicks((0, 1)), 0), ([], 1),
                              ([{"kind": "down", "t_ms": 0}], 1),
                              (clicks((2, 1)), 1), (clicks((0, float("nan"))), 1),
                              ([{"kind": "up", "t_ms": 0}], 1)]:
            with self.subTest(events=events, count=count), self.assertRaises(ValueError):
                analyze_events(events, count)

    def test_atomic_save_and_failed_replacement_preserves_previous_sample(self):
        path = Path(__file__).parent / f"sample-{uuid4().hex}.json"
        try:
            save_json(path, {"test": 1})
            self.assertEqual(json.loads(path.read_text()), {"test": 1})
            with self.assertRaises(ValueError):
                save_json(path, {"bad": float("nan")})
            self.assertEqual(json.loads(path.read_text()), {"test": 1})
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
