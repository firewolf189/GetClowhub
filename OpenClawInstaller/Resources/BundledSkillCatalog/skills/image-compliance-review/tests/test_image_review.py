import importlib.util
import tempfile
import unittest
from datetime import date
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "image_review.py"
SPEC = importlib.util.spec_from_file_location("image_review", SCRIPT_PATH)
image_review = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(image_review)


def sample_result(person, name, is_pass, issues=None, status="reviewed", summary=None):
    return {
        "person": person,
        "image_name": name,
        "relative_path": f"{person}/{name}",
        "status": status,
        "is_pass": is_pass,
        "summary": summary or ("合格" if is_pass else "不合格"),
        "issues": issues or [],
    }


class ImageReviewOutputTests(unittest.TestCase):
    def test_batch_markdown_lists_only_problem_images_but_counts_all_images(self):
        payload = image_review.build_payload(
            input_root=Path("/tmp/input"),
            rules_path=Path("/tmp/rules.md"),
            output_dir=Path("/tmp/output"),
            model_label="test model",
            results=[
                sample_result("张三", "ok.png", True),
                sample_result(
                    "张三",
                    "bad.png",
                    False,
                    [
                        {
                            "rule_id": "logo",
                            "description": "出现第三方品牌 logo",
                            "suggestion": "移除第三方 logo，仅保留公司 logo。",
                        }
                    ],
                ),
                sample_result(
                    "李四",
                    "manual.png",
                    False,
                    [
                        {
                            "rule_id": "copy",
                            "description": "外语文案语义无法确认",
                            "suggestion": "请人工确认文案含义后再判断。",
                        }
                    ],
                    status="manual_review",
                    summary="需人工复核",
                ),
            ],
        )

        markdown = image_review.render_markdown(payload, Path("/tmp/output"))

        self.assertIn("# 单批图片审核明细", markdown)
        self.assertIn("图片总数：3", markdown)
        self.assertIn("需人工复核：1", markdown)
        self.assertIn("| 张三 | 2 | 1 | 1 | 0 | 50.00% |", markdown)
        self.assertNotIn("图片：ok.png", markdown)
        self.assertIn("图片：bad.png", markdown)
        self.assertIn("结果：不合格", markdown)
        self.assertIn("1. Logo规范：出现第三方品牌 logo", markdown)
        self.assertIn("修改方案：移除第三方 logo，仅保留公司 logo。", markdown)
        self.assertIn("图片：manual.png", markdown)
        self.assertIn("结果：需人工复核", markdown)

    def test_period_stats_aggregates_review_results_json_by_date_range(self):
        in_range = image_review.build_payload(
            input_root=Path("/tmp/input"),
            rules_path=Path("/tmp/rules.md"),
            output_dir=Path("/tmp/output/one"),
            model_label="test model",
            results=[
                sample_result("张三", "a.png", True),
                sample_result("张三", "b.png", False, [{"description": "文案错误"}]),
                sample_result("张三", "c.png", False, [{"description": "需复核"}], status="manual_review", summary="需人工复核"),
                sample_result("李四", "d.png", True),
            ],
        )
        in_range["generated_at"] = "2026-06-03T10:00:00+00:00"
        out_of_range = image_review.build_payload(
            input_root=Path("/tmp/input"),
            rules_path=Path("/tmp/rules.md"),
            output_dir=Path("/tmp/output/two"),
            model_label="test model",
            results=[sample_result("张三", "old.png", True)],
        )
        out_of_range["generated_at"] = "2026-05-28T10:00:00+00:00"

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            one = root / "20260603-100000"
            two = root / "20260528-100000"
            one.mkdir()
            two.mkdir()
            (one / "review_results.json").write_text(image_review.json_dumps(in_range), encoding="utf-8")
            (two / "review_results.json").write_text(image_review.json_dumps(out_of_range), encoding="utf-8")

            stats = image_review.build_period_stats_from_root(
                root,
                since=date(2026, 6, 1),
                until=date(2026, 6, 18),
            )

        people = stats["people"]
        self.assertEqual(people["张三"]["total"], 3)
        self.assertEqual(people["张三"]["passed"], 1)
        self.assertEqual(people["张三"]["failed"], 1)
        self.assertEqual(people["张三"]["manual_review"], 1)
        self.assertEqual(people["张三"]["pass_rate"], 33.33)
        self.assertEqual(people["李四"]["pass_rate"], 100.0)

        markdown = image_review.render_period_stats_markdown(stats)
        self.assertIn("# 图片审核合格率统计", markdown)
        self.assertIn("统计周期：2026-06-01 至 2026-06-18", markdown)
        self.assertIn("| 张三 | 3 | 1 | 1 | 1 | 0 | 2 | 33.33% |", markdown)
        self.assertNotIn("old.png", markdown)


if __name__ == "__main__":
    unittest.main()
