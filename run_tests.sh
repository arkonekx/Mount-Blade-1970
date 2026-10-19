#!/usr/bin/env bash
# Testy projektu "Zimna Wojna 1975".
#
# Użycie:
#   GODOT=/ścieżka/do/Godot ./run_tests.sh
#
# Skrypt uruchamia siedem testów (mapa, kampania, bitwa, zapis, pełna rozgrywka,
# tekstury, widoki), a potem obie sceny; szuka też "SCRIPT ERROR" w ich wyjściu.

set -u

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")" || exit 1

if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Nie znaleziono binarki Godot: $GODOT"
	echo "Ustaw zmienną GODOT, np. GODOT=/home/user/tools/godot/Godot_v4.7.2-stable_linux.x86_64 ./run_tests.sh"
	echo "(binarka jest spakowana: gunzip -k /home/user/tools/godot/Godot_v4.7.2-stable_linux.x86_64.gz)"
	exit 1
fi

fails=0

for test_name in test_map test_campaign test_battle test_save test_playthrough test_textures test_views; do
	echo "--- $test_name ---"
	output=$(timeout 180 "$GODOT" --headless --path . -s "res://tests/$test_name.gd" 2>&1)
	code=$?
	echo "$output" | tail -n 40
	if echo "$output" | grep -q "RESULT: PASS"; then
		echo "[OK] $test_name"
	else
		echo "[FAIL] $test_name (kod wyjścia $code)"
		fails=$((fails + 1))
	fi
done

for scene_name in campaign battle; do
	echo "--- scena $scene_name ---"
	output=$(timeout 180 "$GODOT" --headless --path . --quit-after 120 "res://scenes/$scene_name.tscn" 2>&1)
	code=$?
	if echo "$output" | grep -q "SCRIPT ERROR"; then
		echo "$output" | grep -B 1 -A 4 "SCRIPT ERROR" | head -n 30
		echo "[FAIL] scena $scene_name: SCRIPT ERROR (kod wyjścia $code)"
		fails=$((fails + 1))
	else
		echo "[OK] scena $scene_name"
	fi
done

if [ "$fails" -eq 0 ]; then
	echo "RESULT: PASS"
	exit 0
fi

echo "RESULT: FAIL (nieudanych kroków: $fails)"
exit 1
