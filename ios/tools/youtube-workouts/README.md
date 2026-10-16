# YouTube workouts → Pulse Strength plans

`yt_workout.py` turns workout videos into workouts and plans for the app, as a file the app imports (Strength hub, More › Import Plan…).
A workout that is split over several videos is read as **one** workout: all parts go to Claude in a single request, so recaps and
"in part 2 we will…" previews are not turned into duplicate exercises. Workouts can be grouped into a **plan**, a rotation the app
walks through (Upper, Lower, Push … then Upper again) without fixed weekdays.

## Setup

```sh
cd ios/tools/youtube-workouts
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
```

yt-dlp needs a JavaScript runtime for YouTube (Deno, or Node with `--ytdlp-args "--js-runtimes node"`), and ffmpeg is
only needed for `--vision`.

## Use

```sh
# one video
./yt_workout.py https://www.youtube.com/watch?v=XXXXXXXXXXX --name "Push day"

# one workout in three parts (order matters), or a playlist that holds the parts
./yt_workout.py URL_PART1 URL_PART2 URL_PART3 --name "Full body"
./yt_workout.py "https://www.youtube.com/playlist?list=PL..." --name "Full body"

# many workouts at once (see workouts.example.txt for the format)
./yt_workout.py --batch workouts.txt

# workouts that form a plan (a rotation, in the order they are added)
./yt_workout.py URL --name "Upper" --plan "Jeff Nippard UL/PPL" --days-per-week 5
```

In a batch file, `@plan NAME` puts the workouts that follow into a plan (`@days N` sets its weekly target, `@plan -` ends it).

Each workout prints a summary to check against the video: exercises, sets × reps (ranges as 8-10), weights, superset groups, and
`!` lines for anything Claude was unsure about. The tool imports nothing itself; the files go to `out/`:

| File | What |
|---|---|
| `pulse-import.json` | **What to import in the app**: the plan(s), all workouts in `out/` and the exercises that are not in the built-in library, in one file |
| `templates.json`, `custom-exercises.json`, `plans.json` | The same data in the app's own storage files (`FileStrengthPersistence`) |
| `<name>.extracted.json` | Claude's raw answer per workout, plus the source videos and the plan it belongs to. This is the source of truth: the files above are rebuilt from it |

Get `pulse-import.json` onto the phone (AirDrop, Files) and choose **More › Import Plan…** in the Strength hub. Ids are derived from
the names, so importing a regenerated file replaces the earlier copy instead of adding another one, and keeps your place in the rotation.

### Fixing a result

Edit `<name>.extracted.json` (sets, reps, a wrong exercise, a `library_id`), then rebuild the two output files
without calling the API again:

```sh
./yt_workout.py --rebuild
```

### Options worth knowing

* `--vision`: also sends up to `--max-frames` (default 40) frames from each video. Use it when the plan is shown on screen
  and barely spoken, or when there are no captions. It downloads the video (≤ 480p) and costs more tokens.
* `--lang en,de`: caption languages in order of preference. Uploaded captions win over automatic ones.
* `--fetch-only`: fetch and write `<name>.input.txt` (exactly what Claude would read), without calling the API.
* `--force` redoes a workout that already has an `.extracted.json`; `--refresh` ignores the download cache (`out/.cache`).
* `--model`, `--effort`: default `claude-opus-5-5` at `medium`.
* `--ytdlp-args "…"`: anything for yt-dlp. **If YouTube answers "Sign in to confirm you're not a bot"** (common from servers
  and VPNs), pass your browser's login: `--ytdlp-args "--cookies-from-browser chrome"`. Without a login, this often still
  works for the text the tool needs: `--ytdlp-args "--extractor-args youtube:player_client=web_embedded"`.
* A playlist URL (`/playlist?list=…`) is expanded into its videos, which are then read as the **parts of one workout**. If
  every video is its own workout, list them one by one in a `--batch` file instead (one `# Name` each).

## What to expect

* Sets, reps, rest and order come from what is said and from the video description (a written plan there is used and
  checked against the speech). Captions are the weak spot: automatic captions mishear exercise names, which is why the
  summary is worth a look.
* **Weights are only filled in when the video states them** (pounds are converted to kg in 0.5 steps); otherwise they are
  0 and you enter them in the app. An instructor's own weight is not a recommendation.
* Exercises are matched to the built-in library by id (read from `ExerciseLibrary.swift`, so new library entries are
  picked up automatically). Everything else becomes a custom exercise with a stable id (`custom-<name>`), shared between
  workouts.
* Rep ranges stay ranges ("8-10": the workout starts at 8). What the video says about how to do an exercise (cues, substitutions)
  becomes the exercise's note, which the app shows on the workout screen and while the exercise is done.
* Circuits and supersets become shared superset letters; timed work (planks, intervals) is a duration exercise whose
  "reps" are seconds, as in the app.
* Videos are fetched only for their captions, description and chapters (no video download without `--vision`).
  Check the creator's terms before processing videos in bulk.

## Tests

```sh
python3 -m unittest discover -s tests -b
```

They run offline with a fake yt-dlp and a fake Claude answer. `out/` holds the plan made from Jeff Nippard's UL/PPL playlist
(see `out/ul-ppl-schedule.md`); the tests check that it is what the tool rebuilds from its extractions and that the Swift tests'
fixture (`Packages/.../Fixtures/pulse-import-ulppl.json`) is the same file, which the app's own models import unchanged.
