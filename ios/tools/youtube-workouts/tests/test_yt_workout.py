"""Offline tests: yt-dlp and Claude are replaced by fakes. Run: python3 -m unittest discover -s tests"""
import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import yt_workout as yw  # noqa: E402

LIBRARY = yw.load_library(yw.DEFAULT_LIBRARY)


def ex(name, sets, **kw):
    base = {"name": name, "library_id": None, "muscle": None, "equipment": None, "tracking": None,
            "sets": sets, "rest_seconds": None, "superset_group": None, "note": None, "part": 1, "timestamp": None}
    base.update(kw)
    return base


def s(reps, weight=None, unit=None, type="normal", reps_max=None):
    return {"type": type, "reps": reps, "reps_max": reps_max, "weight": weight, "weight_unit": unit}


def extraction(*exercises, warnings=()):
    return {"title": "T", "summary": "S", "warnings": list(warnings), "exercises": list(exercises)}


class LibraryTests(unittest.TestCase):
    def test_every_swift_row_is_parsed(self):
        self.assertEqual(len(LIBRARY), 36)
        bench = LIBRARY["bench"]
        self.assertEqual((bench["name"], bench["muscle"], bench["equipment"], bench["tracking"]),
                         ("Barbell bench press", "Chest", "Barbell", "weightReps"))
        self.assertEqual(bench["defaults"], {"sets": 3, "weightKg": 60.0, "reps": 8, "restSeconds": 150})
        self.assertEqual(len(bench["cues"]), 3)
        self.assertEqual(bench["mediaKey"], "bench")
        self.assertNotIn("mediaKey", LIBRARY["cpress"])
        self.assertEqual(LIBRARY["plank"]["tracking"], "duration")
        self.assertEqual(LIBRARY["skull"]["barKg"], 10.0)

    def test_a_changed_format_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Lib.swift"
            path.write_text('row("a", "A", .chest, "", .barbell, .weightReps, media: nil)\n')
            with self.assertRaises(SystemExit):
                yw.load_library(path)


class TranscriptTests(unittest.TestCase):
    def test_json3_drops_sound_tags_and_empty_events(self):
        data = {"events": [{"tStartMs": 1000, "segs": [{"utf8": "[Music]"}]},
                           {"tStartMs": 65000, "segs": [{"utf8": "Start with "}, {"utf8": "squats\n"}]},
                           {"tStartMs": 66000}]}
        self.assertEqual(yw.parse_json3(data), [(65.0, "Start with squats")])

    def test_window_groups_lines_under_their_time(self):
        lines = [(1, "a"), (19, "b"), (21, "c"), (3725, "d")]
        self.assertEqual(yw.window_transcript(lines), "[0:00] a b\n[0:20] c\n[1:02:00] d")

    def test_caption_choice_prefers_uploaded_then_original_language(self):
        info = {"subtitles": {"de": [{}]}, "automatic_captions": {"en": [{}], "en-orig": [{}]}}
        self.assertEqual(yw.pick_caption(info, ["en"]), ("auto", "en-orig"))
        info["subtitles"]["en-US"] = [{}]
        self.assertEqual(yw.pick_caption(info, ["en"]), ("manual", "en-US"))
        self.assertEqual(yw.pick_caption({"automatic_captions": {"fr-orig": [{}], "en": [{}]}}, ["de"]),
                         ("auto", "fr-orig"))
        self.assertIsNone(yw.pick_caption({}, ["en"]))


class TemplateTests(unittest.TestCase):
    def build(self, *exercises, **kw):
        return yw.build_template("w", "W", extraction(*exercises, **kw), LIBRARY)

    def test_library_exercise_is_embedded_unchanged(self):
        template, customs, _ = self.build(ex("Bench", [s(8, 60, "kg"), s(8, 60, "kg")], library_id="bench", rest_seconds=120))
        entry = template["entries"][0]
        self.assertEqual(entry["exercise"], LIBRARY["bench"])
        self.assertEqual(entry["plannedSets"], [{"type": "normal", "weightKg": 60.0, "reps": 8}] * 2)
        self.assertEqual(entry["restSeconds"], 120)
        self.assertEqual(customs, [])

    def test_pounds_become_half_kilos_and_bodyweight_ignores_weight(self):
        template, _, _ = self.build(ex("Bench", [s(5, 135, "lb")], library_id="bench"),
                                    ex("Push-up", [s(12, 20, "kg")], library_id="pushup"))
        self.assertEqual(template["entries"][0]["plannedSets"][0]["weightKg"], 61.0)
        self.assertEqual(template["entries"][1]["plannedSets"][0]["weightKg"], 0.0)

    def test_unknown_exercise_becomes_a_custom_exercise(self):
        template, customs, warnings = self.build(
            ex("Kettlebell Swing", [s(15)], muscle="Legs", equipment="Other", tracking="weightReps"),
            ex("Kettlebell Swing", [s(20)], muscle="Legs", equipment="Other", tracking="weightReps"),
            ex("Mystery", [s(10)], library_id="nope"))
        self.assertEqual([c["id"] for c in customs], ["custom-kettlebell-swing", "custom-mystery"])
        self.assertTrue(all(c["isCustom"] for c in customs))
        self.assertEqual(template["entries"][0]["exercise"]["id"], template["entries"][1]["exercise"]["id"])
        self.assertTrue(any("unknown library id" in w for w in warnings))
        self.assertTrue(any("no muscle group" in w for w in warnings))

    def test_limits_and_defaults(self):
        template, _, warnings = self.build(
            ex("Squat", [s(5, 100, "kg")], library_id="squat", rest_seconds=99999),
            ex("Plank", [], library_id="plank"),
            ex("Row", [s(-4, 1e9, "kg")], library_id="brow"))
        self.assertEqual(template["entries"][0]["restSeconds"], yw.MAX_REST_SECONDS)
        plank = template["entries"][1]
        self.assertEqual(len(plank["plannedSets"]), 3)  # the library default for a plank
        self.assertEqual(plank["restSeconds"], LIBRARY["plank"]["defaults"]["restSeconds"])
        self.assertTrue(any("no sets found" in w for w in warnings))
        row = template["entries"][2]["plannedSets"][0]
        self.assertEqual((row["reps"], row["weightKg"]), (0, 1_000_000.0))

    def test_supersets_are_lettered_by_appearance_and_need_two_members(self):
        template, _, warnings = self.build(
            ex("Curl", [s(10)], library_id="curl", superset_group="x"),
            ex("Squat", [s(10)], library_id="squat", superset_group="q"),
            ex("Pushdown", [s(10)], library_id="pushdown", superset_group="X"),
            ex("Lunge", [s(10)], library_id="lunge"))
        groups = [e.get("supersetGroup") for e in template["entries"]]
        self.assertEqual(groups, ["A", None, "A", None])
        self.assertTrue(any("alone in group Q" in w for w in warnings))

    def test_ids_are_stable_and_uppercase_uuids(self):
        a, _, _ = self.build(ex("Squat", [s(5)], library_id="squat"))
        b, _, _ = self.build(ex("Squat", [s(5)], library_id="squat"))
        self.assertEqual(a["id"], b["id"])
        self.assertEqual(a["id"], a["id"].upper())
        self.assertNotEqual(a["entries"][0]["id"], a["id"])

    def test_no_exercises_is_an_error(self):
        with self.assertRaises(yw.WorkoutError):
            self.build()

    def test_the_encoded_template_has_every_key_the_swift_models_require(self):
        template, customs, _ = self.build(ex("Swing", [s(15)], muscle="Legs", equipment="Other", tracking="weightReps"),
                                          ex("Squat", [s(5)], library_id="squat"))
        exercise_keys = {"id", "name", "muscle", "secondary", "equipment", "tracking", "previousBestE1RM",
                         "previousSets", "defaults", "cues", "barKg", "isCustom"}
        self.assertEqual(set(template), {"id", "name", "entries"})
        for entry in template["entries"]:
            self.assertEqual({"id", "exercise", "plannedSets", "restSeconds"}, set(entry) - {"supersetGroup", "note"})
            self.assertTrue(exercise_keys <= set(entry["exercise"]))
            for planned in entry["plannedSets"]:
                self.assertEqual(set(planned) - {"repsMax"}, {"type", "weightKg", "reps"})
        self.assertTrue(exercise_keys <= set(customs[0]))


class RangeAndNoteTests(unittest.TestCase):
    def build(self, *exercises):
        return yw.build_template("w", "W", extraction(*exercises), LIBRARY)[0]

    def test_a_rep_range_keeps_its_top_only_when_it_is_above_the_bottom(self):
        template = self.build(ex("Bench", [s(8, reps_max=10), s(8, reps_max=8), s(8, reps_max=5), s(8), s(0, reps_max=99999)],
                                 library_id="bench"))
        sets = template["entries"][0]["plannedSets"]
        self.assertEqual([x.get("repsMax") for x in sets], [10, None, None, None, yw.MAX_REPS])
        self.assertEqual([x["reps"] for x in sets], [8, 8, 8, 8, 0])

    def test_a_note_is_trimmed_and_blank_notes_are_left_out(self):
        template = self.build(ex("Bench", [s(8)], library_id="bench", note="  Pause on the chest. "),
                              ex("Squat", [s(8)], library_id="squat", note="   "),
                              ex("Row", [s(8)], library_id="brow"))
        entries = template["entries"]
        self.assertEqual(entries[0]["note"], "Pause on the chest.")
        self.assertNotIn("note", entries[1])
        self.assertNotIn("note", entries[2])

    def test_the_summary_shows_ranges(self):
        template = self.build(ex("Bench", [s(8, reps_max=10)] * 2, library_id="bench"))
        self.assertIn("2 x 8-10-8-10", yw.format_summary(template, {}, []).replace("/", "-"))


class BatchFileTests(unittest.TestCase):
    def test_batch_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.txt"
            path.write_text("// comment\nhttps://youtu.be/aaaaaaaaaaa\n\n# Push day\nhttps://youtu.be/bbbbbbbbbbb\n"
                            "cccccccccc-\n# Legs\nhttps://www.youtube.com/playlist?list=PL1\n")
            self.assertEqual(yw.parse_batch(path), [
                yw.Job(None, ["https://youtu.be/aaaaaaaaaaa"]),
                yw.Job("Push day", ["https://youtu.be/bbbbbbbbbbb", "cccccccccc-"]),
                yw.Job("Legs", ["https://www.youtube.com/playlist?list=PL1"]),
            ])
            path.write_text("# X\nnot a url\n")
            with self.assertRaises(SystemExit):
                yw.parse_batch(path)

    def test_plan_directives(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.txt"
            path.write_text("@plan UL/PPL\n@days 5\n# Upper\nhttps://youtu.be/aaaaaaaaaaa\n# Lower\nhttps://youtu.be/bbbbbbbbbbb\n"
                            "@plan -\n# Solo\nhttps://youtu.be/ccccccccccc\n@plan Other\n# One\nhttps://youtu.be/ddddddddddd\n")
            jobs = yw.parse_batch(path)
            self.assertEqual([(j.name, j.plan, j.days) for j in jobs],
                             [("Upper", "UL/PPL", 5), ("Lower", "UL/PPL", 5), ("Solo", None, None), ("One", "Other", None)])
            for bad in ("@plan X\n@days 9\n# A\nhttps://youtu.be/aaaaaaaaaaa\n", "@days x\n"):
                path.write_text(bad)
                with self.assertRaises(SystemExit):
                    yw.parse_batch(path)

    def test_playlist_detection(self):
        self.assertTrue(yw.is_playlist_url("https://www.youtube.com/playlist?list=PL1"))
        self.assertTrue(yw.is_playlist_url("https://www.youtube.com/watch?list=PL1"))
        self.assertFalse(yw.is_playlist_url("https://www.youtube.com/watch?v=abc&list=PL1"))
        self.assertFalse(yw.is_playlist_url("https://youtu.be/abc"))

    def test_playlist_expands_in_order(self):
        reply = json.dumps({"entries": [{"id": "p1"}, {"id": "p2"}, None and {}]})
        with mock.patch.object(yw, "ytdlp", return_value=reply):
            urls = yw.expand_urls(["https://www.youtube.com/playlist?list=PL1", "https://youtu.be/zzz"], [])
        self.assertEqual(urls, ["https://www.youtube.com/watch?v=p1", "https://www.youtube.com/watch?v=p2",
                                "https://youtu.be/zzz"])


class CommittedOutputTests(unittest.TestCase):
    """The checked-in UL/PPL files must be what the tool rebuilds from the checked-in extractions, and the Swift tests'
    fixture must be the very same import file (they decode it with the app's own models)."""
    OUT = Path(__file__).resolve().parent.parent / "out"
    FIXTURE = (Path(__file__).resolve().parents[3] / "Packages/PulseStrengthKit/Tests/PulseStrengthCoreTests/Fixtures"
               / "pulse-import-ulppl.json")

    def test_rebuilding_reproduces_the_committed_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for source in self.OUT.glob("*.extracted.json"):
                (work / source.name).write_text(source.read_text())
            self.assertEqual(yw.rebuild_outputs(work, LIBRARY), 5)
            for name in ("templates.json", "custom-exercises.json", "plans.json", "pulse-import.json"):
                self.assertEqual((work / name).read_text(), (self.OUT / name).read_text(), name)

    def test_the_swift_fixture_is_the_committed_import_file(self):
        self.assertEqual(self.FIXTURE.read_text(), (self.OUT / "pulse-import.json").read_text())


class FakeYtDlp:
    """Stands in for yt-dlp: metadata for two videos, json3 captions written where yt-dlp would write them."""
    INFO = {
        "p1": {"id": "p1", "title": "Push Day Part 1", "duration": 600, "channel": "Coach",
               "description": "Part 1 of 2", "automatic_captions": {"en-orig": [{}]}, "chapters": [{"start_time": 0, "title": "Bench"}]},
        "p2": {"id": "p2", "title": "Push Day Part 2", "duration": 500, "channel": "Coach",
               "description": "Part 2 of 2", "subtitles": {"en": [{}]}},
    }

    def __init__(self):
        self.calls = []

    def __call__(self, args, extra):
        self.calls.append(args)
        url = args[-1]
        vid = url.rsplit("=", 1)[-1]
        if "--dump-single-json" in args:
            return json.dumps(self.INFO[vid])
        out = Path(args[args.index("-o") + 1])
        out.parent.mkdir(parents=True, exist_ok=True)
        (out.parent / f"{vid}.en.json3").write_text(json.dumps(
            {"events": [{"tStartMs": 5000, "segs": [{"utf8": f"transcript of {vid}"}]}]}))
        return ""


def make_args(**kw):
    defaults = dict(lang=["en"], ytdlp_args=None, refresh=False, vision=False, max_frames=40, model="m", effort="medium",
                    fetch_only=False, force=False)
    defaults.update(kw)
    return argparse.Namespace(**defaults)


class PipelineTests(unittest.TestCase):
    URLS = ["https://www.youtube.com/watch?v=p1", "https://www.youtube.com/watch?v=p2"]
    ANSWER = extraction(
        ex("Bench", [s(8, 60, "kg")] * 3, library_id="bench", part=1),
        ex("Cable fly", [s(12)] * 3, library_id="crossover", part=2, superset_group="A"),
        ex("Dip", [s(10)] * 3, library_id="dips", part=2, superset_group="A"),
        ex("Battle rope", [s(30)], muscle="Arms", equipment="Other", tracking="duration", part=2),
    )

    def run_job(self, out, name="Push day", args=None, urls=None, plan=None, days=None):
        ytdlp = FakeYtDlp()
        with mock.patch.object(yw, "ytdlp", ytdlp), \
                mock.patch.object(yw, "call_claude", return_value=self.ANSWER) as claude:
            yw.process(yw.Job(name, urls or self.URLS, plan, days), args or make_args(), LIBRARY, out, set())
        return ytdlp, claude

    def test_two_parts_become_one_workout(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            ytdlp, claude = self.run_job(out)
            # one request carries both parts, in order, with their transcripts
            self.assertEqual(claude.call_count, 1)
            text = yw.describe_content(claude.call_args.args[0])
            self.assertLess(text.index("PART 1 of 2"), text.index("PART 2 of 2"))
            self.assertIn("transcript of p1", text)
            self.assertIn("transcript of p2", text)
            self.assertIn("Chapters:\n[0:00] Bench", text)
            self.assertIn("(uploaded captions)", text)
            self.assertIn("(automatic captions)", text)
            self.assertIn("bench | Barbell bench press | Chest | Barbell | weightReps", text)

            self.assertEqual(yw.rebuild_outputs(out, LIBRARY), 1)
            templates = json.loads((out / "templates.json").read_text())
            self.assertEqual([t["name"] for t in templates], ["Push day"])
            self.assertEqual([e["exercise"]["id"] for e in templates[0]["entries"]],
                             ["bench", "crossover", "dips", "custom-battle-rope"])
            self.assertEqual([e.get("supersetGroup") for e in templates[0]["entries"]], [None, "A", "A", None])
            customs = json.loads((out / "custom-exercises.json").read_text())
            self.assertEqual([c["id"] for c in customs], ["custom-battle-rope"])
            saved = json.loads((out / "push-day.extracted.json").read_text())
            self.assertEqual([x["captions"] for x in saved["sources"]], ["auto", "manual"])

    def test_second_run_uses_the_cache_and_skips_finished_workouts(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            first, _ = self.run_job(out)
            second, claude = self.run_job(out)
            self.assertEqual(second.calls, [])
            claude.assert_not_called()
            self.assertGreater(len(first.calls), 0)
            _, claude = self.run_job(out, args=make_args(force=True))
            claude.assert_called_once()

    def test_fetch_only_writes_the_prompt_input_and_nothing_else(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _, claude = self.run_job(out, args=make_args(fetch_only=True))
            claude.assert_not_called()
            self.assertIn("PART 2 of 2", (out / "push-day.input.txt").read_text())
            self.assertFalse(list(out.glob("*.extracted.json")))

    def test_invalid_extraction_saves_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            with mock.patch.object(yw, "ytdlp", FakeYtDlp()), \
                    mock.patch.object(yw, "call_claude", return_value=extraction()):
                with self.assertRaises(yw.WorkoutError):
                    yw.process(yw.Job("Empty", self.URLS), make_args(), LIBRARY, out, set())
            self.assertFalse(list(out.glob("*.extracted.json")))

    def test_hand_edited_extraction_is_picked_up_by_rebuild(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            self.run_job(out)
            path = out / "push-day.extracted.json"
            saved = json.loads(path.read_text())
            saved["extraction"]["exercises"][0]["sets"] = [s(5, 100, "kg")]
            path.write_text(json.dumps(saved))
            yw.rebuild_outputs(out, LIBRARY)
            first = json.loads((out / "templates.json").read_text())[0]["entries"][0]
            self.assertEqual(first["plannedSets"], [{"type": "normal", "weightKg": 100.0, "reps": 5}])

    def test_no_captions_and_no_description_asks_for_vision(self):
        with tempfile.TemporaryDirectory() as tmp:
            bare = {"p1": {"id": "p1", "title": "Silent", "duration": 100}}
            ytdlp = FakeYtDlp()
            with mock.patch.object(FakeYtDlp, "INFO", bare), mock.patch.object(yw, "ytdlp", ytdlp):
                with self.assertRaisesRegex(yw.WorkoutError, "--vision"):
                    yw.process(yw.Job("Silent", self.URLS[:1]), make_args(), LIBRARY, Path(tmp), set())

    def test_workouts_of_a_plan_form_one_rotation_and_one_import_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            for name in ("Upper", "Lower", "Push"):
                self.run_job(out, name=name, plan="UL/PPL", days=5)
            self.run_job(out, name="Solo")
            self.assertEqual(yw.rebuild_outputs(out, LIBRARY), 4)

            plans = json.loads((out / "plans.json").read_text())
            self.assertEqual(len(plans), 1)
            plan = plans[0]
            templates = {t["name"]: t["id"] for t in json.loads((out / "templates.json").read_text())}
            self.assertEqual(plan["name"], "UL/PPL")
            self.assertEqual(plan["templateIDs"], [templates["Upper"], templates["Lower"], templates["Push"]],
                             "the order the workouts were added, not alphabetical")
            self.assertEqual((plan["nextIndex"], plan["daysPerWeek"], plan["isActive"]), (0, 5, False))
            self.assertEqual(plan["id"], yw.plan_id("UL/PPL"))

            bundle = json.loads((out / "pulse-import.json").read_text())
            self.assertEqual(sorted(bundle), ["customExercises", "plans", "templates", "version"])
            self.assertEqual(bundle["version"], 1)
            self.assertEqual(bundle["plans"], plans)
            self.assertEqual(len(bundle["templates"]), 4)
            self.assertEqual([c["id"] for c in bundle["customExercises"]], ["custom-battle-rope"])

    def test_redoing_a_workout_keeps_its_place_in_the_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            self.run_job(out, name="Upper", plan="P")
            self.run_job(out, name="Lower", plan="P")
            self.run_job(out, name="Upper", plan="P", args=make_args(force=True))
            yw.rebuild_outputs(out, LIBRARY)
            plan = json.loads((out / "plans.json").read_text())[0]
            templates = {t["id"]: t["name"] for t in json.loads((out / "templates.json").read_text())}
            self.assertEqual([templates[i] for i in plan["templateIDs"]], ["Upper", "Lower"])

    def test_without_a_plan_the_import_file_has_workouts_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            self.run_job(out)
            yw.rebuild_outputs(out, LIBRARY)
            self.assertEqual(json.loads((out / "pulse-import.json").read_text())["plans"], [])
            self.assertEqual(json.loads((out / "plans.json").read_text()), [])

    def test_frames_are_sent_as_labelled_images(self):
        video = yw.Video("v", "u", "T", "C", 100, "", [], [], "none", frames=[(30, b"\xff\xd8jpeg")])
        blocks = yw.build_content([video], LIBRARY)
        kinds = [b["type"] for b in blocks]
        self.assertEqual(kinds.count("image"), 1)
        label = blocks[kinds.index("image") - 1]["text"]
        self.assertEqual(label, "Frame from part 1 at [0:30]:")


if __name__ == "__main__":
    unittest.main()
