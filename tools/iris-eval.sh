#!/bin/bash
# Sends the prompts in tools/iris-eval/corpus.json to the real Iris (the provider and model chosen in Settings, or --model) in a
# throwaway world and scores her answers against the gold ones. Nothing is built; it costs tokens. Extra arguments go to
# `hatch iris-eval`: --only id,id  --limit n  --random n --seed s  --model haiku  --min 0.9
# The free version of the same prompts, with scripted answers, runs in `swift test --filter IrisPipelineTests`.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" && swift build -q --product hatch && exec .build/debug/hatch iris-eval tools/iris-eval/corpus.json "$@"
