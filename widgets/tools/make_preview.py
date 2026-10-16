#!/usr/bin/env python3
"""Writes widgets/fixtures/preview.json: the idealised snapshot behind previews, placeholders and snapshot tests.

The numbers follow the design canvas (3 of 4 workouts, bench 85 x 5 with an estimated 1RM of 99 kg, 37 sets this week) so that
every widget has something to show. Run generate.py afterwards.
"""
import json
import os
from datetime import datetime, timedelta, timezone

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "widgets/fixtures/preview.json")

NOW = datetime(2026, 10, 17, 9, 41, 0, tzinfo=timezone.utc)  # Saturday
MONDAY = datetime(2026, 10, 12, 0, 0, 0, tzinfo=timezone.utc)


def iso(value):
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def day(offset, hour=0, minute=0):
    return MONDAY + timedelta(days=offset, hours=hour, minutes=minute)


UA, LA, UB = "00000000-0000-4000-8000-0000000000a1", "00000000-0000-4000-8000-0000000000a2", "00000000-0000-4000-8000-0000000000a3"

week_days = []
letters = ["M", "T", "W", "T", "F", "S", "S"]
labels = {0: "UA", 1: "LA", 2: "UB"}
for i in range(7):
    week_days.append({
        "date": iso(day(i)), "letter": letters[i], "sessions": 1 if i in labels else 0,
        "isToday": i == 5, "isFuture": i > 5, **({"label": labels[i]} if i in labels else {}),
    })

exercises = [
    ("bench", "Bench Press", "Chest", 5, "3 × 85"),
    ("incline", "Incline Dumbbell Press", "Chest", 3, "3 × 28"),
    ("ohp", "Overhead Press", "Shoulders", 3, "3 × 45"),
    ("lateral", "Lateral Raise", "Shoulders", 3, "3 × 8"),
    ("pushdown", "Triceps Pushdown", "Arms", 3, "3 × 30"),
    ("crossover", "Cable Crossover", "Chest", 3, "3 × 15"),
]

timeline = []
for kind, seconds in [("lifting", 160), ("rest", 90), ("lifting", 170), ("rest", 120), ("lifting", 150), ("longRest", 240),
                      ("lifting", 180), ("rest", 90), ("lifting", 160), ("rest", 120), ("lifting", 170), ("rest", 60), ("lifting", 150)]:
    timeline.append({"kind": kind, "seconds": seconds})

hr_bars = [{"bpm": b, "isEffort": e} for b, e in [(96, False), (131, True), (104, False), (146, True), (101, False), (151, True), (108, False), (140, True)]]


def month_days():
    levels = {2: 2, 5: 3, 7: 2, 9: 1, 12: 3, 13: 2, 14: 2}
    result = []
    for d in range(1, 32):
        item = {"day": d, "level": levels.get(d, 0), "sessions": 1 if d in levels else 0, "isToday": d == 17, "isFuture": d > 17}
        result.append(item)
    return result


def lift(exercise_id, name, values, pr_index, sessions):
    start = NOW - timedelta(days=5 * (len(values) - 1))
    points = [{"date": iso(start + timedelta(days=5 * i)), "value": v} for i, v in enumerate(values)]
    return {
        "exerciseID": exercise_id, "name": name, "points": points, "currentE1RM": values[-1], "bestE1RM": max(values),
        **({"prIndex": pr_index} if pr_index is not None else {}), "sessionCount": sessions,
        "deltaKg": round(values[-1] - values[-2], 1) if len(values) > 1 else 0,
    }


preview = {
    "schemaVersion": 1,
    "generatedAt": iso(NOW),
    "timeZoneID": "UTC",
    "week": {
        "weekStart": iso(MONDAY), "goal": 4, "completed": 3, "streakWeeks": 6,
        "lastWorkoutAt": iso(day(2, 10, 2)), "daysSinceLastWorkout": 3, "days": week_days,
    },
    "nextUp": {
        "templateID": UA, "name": "Upper A · Push", "splitLabel": "Push day", "exerciseCount": 6, "setCount": 20,
        "estimatedMinutes": 55, "lastPerformedAt": iso(day(0, 9, 30)), "daysSince": 5,
        "exercises": [{"exerciseID": e[0], "name": e[1], "muscle": e[2], "setCount": e[3], "summary": e[4]} for e in exercises],
    },
    "templates": [
        {"templateID": UA, "name": "Upper A · Push", "exerciseCount": 6, "estimatedMinutes": 55, "lastPerformedAt": iso(day(0, 9, 30)), "daysSince": 5, "isSuggested": True},
        {"templateID": LA, "name": "Lower A · Quads", "exerciseCount": 5, "estimatedMinutes": 50, "lastPerformedAt": iso(day(1, 17, 40)), "daysSince": 4, "isSuggested": False},
        {"templateID": UB, "name": "Upper B · Pull", "exerciseCount": 6, "estimatedMinutes": 55, "lastPerformedAt": iso(day(2, 10, 2)), "daysSince": 3, "isSuggested": False},
    ],
    "lastSession": {
        "workoutID": "00000000-0000-4000-8000-0000000000b3", "name": "Upper B · Pull", "finishedAt": iso(day(2, 10, 2)),
        "durationMinutes": 51, "loggedSets": 18, "volumeKg": 8400, "averageHeartRate": 118, "peakHeartRate": 151,
        "personalRecordCount": 0, "timeline": timeline, "underTensionPercent": 38, "longBreakCount": 1, "heartRateBars": hr_bars,
    },
    "latestPR": {
        "exerciseID": "bench", "exerciseName": "Bench Press", "weightKg": 85, "reps": 5, "estimated1RM": 99, "deltaKg": 4,
        "achievedAt": iso(day(5, 7, 50)), "isFresh": True,
    },
    "overload": {
        "exerciseID": "bench", "exerciseName": "Bench Press", "lastWeightKg": 80, "lastReps": 6, "lastDaysAgo": 5,
        "targetWeightKg": 82.5, "targetReps": 6, "targetSets": 4, "deltaKg": 2.5,
    },
    "freshness": [
        {"muscle": "Chest", "daysSince": 5, "status": "ready"},
        {"muscle": "Back", "daysSince": 3, "status": "recovering"},
        {"muscle": "Shoulders", "daysSince": 5, "status": "ready"},
        {"muscle": "Arms", "daysSince": 1, "status": "worked"},
        {"muscle": "Legs", "daysSince": 7, "status": "ready"},
        {"muscle": "Core", "status": "ready"},
    ],
    "weeklySets": {
        "muscles": [
            {"muscle": "Chest", "sets": 12, "targetLow": 10, "targetHigh": 14, "status": "onTarget"},
            {"muscle": "Back", "sets": 10, "targetLow": 10, "targetHigh": 14, "status": "onTarget"},
            {"muscle": "Shoulders", "sets": 9, "targetLow": 10, "targetHigh": 14, "status": "under"},
            {"muscle": "Arms", "sets": 6, "targetLow": 6, "targetHigh": 10, "status": "onTarget"},
            {"muscle": "Legs", "sets": 6, "targetLow": 10, "targetHigh": 14, "status": "under"},
            {"muscle": "Core", "sets": 0, "targetLow": 6, "targetHigh": 10, "status": "under"},
        ],
        "totalSets": 37, "totalTarget": 48, "setsToGo": 11, "laggingMuscle": "Legs",
    },
    "lifts": [
        lift("bench", "Bench Press", [93, 99, 96], 1, 3),
        lift("squat", "Back Squat", [118, 121, 124], 2, 3),
        lift("brow", "Barbell Row", [78, 80, 82], 2, 3),
        lift("ohp", "Overhead Press", [58.4, 58.4, 58.4], None, 3),
        lift("deadlift", "Deadlift", [140, 146, 150], 2, 2),
    ],
    "month": {
        "monthStart": iso(datetime(2026, 10, 1, tzinfo=timezone.utc)), "title": "October", "leadingBlankDays": 3,
        "sessionCount": 7, "days": month_days(),
    },
    "plateaus": [
        {"exerciseID": "bench", "name": "Bench Press", "status": "rising", "flatSessions": 0},
        {"exerciseID": "ohp", "name": "Overhead Press", "status": "flat", "flatSessions": 3, "tip": "Try 3 × 8 at about 90% for two weeks."},
        {"exerciseID": "squat", "name": "Back Squat", "status": "rising", "flatSessions": 0},
    ],
    "year": {
        "year": 2026, "tonnes": 186.4, "sessionCount": 74,
        "monthlyTonnes": [14.2, 15.8, 17.1, 16.4, 18.9, 17.6, 15.2, 19.8, 21.3, 19.6, 0, 0],
    },
    "block": {
        "name": "Block 2", "weekIndex": 3, "weekCount": 4,
        "rows": [
            {"label": "Push", "cells": [{"state": "done"}, {"state": "done"}, {"state": "done"}, {"state": "upcoming"}]},
            {"label": "Legs", "cells": [{"state": "done"}, {"state": "done"}, {"state": "planned"}, {"state": "upcoming"}]},
            {"label": "Pull", "cells": [{"state": "done"}, {"state": "missed"}, {"state": "done"}, {"state": "upcoming"}]},
        ],
        "sessionsDone": 10, "sessionsPlanned": 12, "sessionsMissed": 1, "liftName": "Bench Press", "liftDeltaKg": 4,
    },
    "formCue": {"exerciseID": "bench", "exerciseName": "Bench Press", "cue": "Shoulder blades back and down.", "index": 1, "count": 4},
    "loadedBar": {
        "exerciseID": "bench", "exerciseName": "Bench Press", "totalKg": 85, "barKg": 20, "platesPerSide": [20, 10, 2.5],
        "leftoverKg": 0, "summary": "20 + 10 + 2.5",
    },
    "strengthRatio": {
        "exerciseID": "bench", "exerciseName": "Bench Press", "estimated1RM": 99, "bodyweightKg": 80, "ratio": 1.24, "goalRatio": 1.5,
    },
    "restDay": {"title": "10-min mobility", "focus": "Hips and T-spine", "minutes": 10, "reason": "Rest day"},
    "tomorrow": {
        "templateName": "Lower A · Quads", "plannedMinuteOfDay": 420, "weekday": "Sunday", "note": "Gym bag ready?", "isInferred": True,
    },
    "bodyMap": {
        "levels": [
            {"muscle": "Chest", "level": 3}, {"muscle": "Back", "level": 2}, {"muscle": "Shoulders", "level": 2},
            {"muscle": "Arms", "level": 1}, {"muscle": "Legs", "level": 0}, {"muscle": "Core", "level": 0},
        ],
        "untouched": ["Legs", "Core"],
        "message": "Legs untouched. Lower A is next in line.",
    },
    "readiness": {"score": 82, "label": "Ready", "message": "Good sleep, steady HRV. Go for the top set.", "source": "Pulse"},
    "partners": [
        {"name": "Sam", "initials": "S", "completed": 4, "goal": 4, "closedWeek": True},
    ],
}

if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(preview, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("wrote", os.path.relpath(OUT, ROOT))
