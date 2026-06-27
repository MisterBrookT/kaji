#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -parse-as-library -O scripts/hero.swift -o /tmp/kaji-hero
/tmp/kaji-hero docs/hero.png
