# YouTube workouts → Pulse Strength templates

`yt_workout.py` turns workout videos into workout templates in the app's own file format. A workout that is
split over several videos is read as **one** workout: all parts go to Claude in a single request, so recaps and
"in part 2 we will…" previews are not turned into duplicate exercises.

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
```

Each workout prints a summary to check against the video: exercises, sets × reps, weights, superset groups, and
`!` lines for anything Claude was unsure about. Nothing is imported anywhere; the files go to `out/`:

| File | What |
|---|---|
| `templates.json` | All workouts in `out/`, as the app's `[WorkoutTemplate]` (what `FileStrengthPersistence.saveTemplates` writes) |
| `custom-exercises.json` | Exercises that are not in the built-in library, as `[Exercise]` (`loadCustomExercises`) |
| `<name>.extracted.json` | Claude's raw answer per workout, plus the source videos. This is the source of truth: the two files above are rebuilt from it |

Ids are derived from the workout name, so regenerating a workout replaces it when imported instead of adding a copy.
The app has no import screen yet; this tool only produces the files.

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
* Circuits and supersets become shared superset letters; timed work (planks, intervals) is a duration exercise whose
  "reps" are seconds, as in the app.
* Videos are fetched only for their captions, description and chapters (no video download without `--vision`).
  Check the creator's terms before processing videos in bulk.

## Tests

```sh
python3 -m unittest discover -s tests -b
```

They run offline with a fake yt-dlp and a fake Claude answer.
