# usage: repro2.sh <repo> <tag> <bday on|off> <variant only|plus> <rounds> [TEST_RUNNER_ env...]
# Seeds a due repeating text and runs StopRepeatingReproTests N times on a
# simulator, counting crashes. Used on 2026-11-27 to try to reproduce the
# swipe Stop Repeating crash on 755bc21^ (old) vs master. See the commit message.
REPO=$1; TAG=$2; BDAY=$3; VAR=$4; N=$5; shift 5
R=${SIM:?set SIM to a simulator udid}; HERE=$(cd "$(dirname "$0")" && pwd); SAMPLE=${SAMPLE:?set SAMPLE to a saved messages.json}
cd "$REPO"
cp ~/GitHub/scheduled-texts/DemoUITests/StopRepeatingReproTests.swift DemoUITests/
xcodegen >/dev/null
xcrun simctl uninstall $R com.quasarbright.ScheduledTexts 2>/dev/null
xcodebuild -project ScheduledTexts.xcodeproj -scheme ScheduledTexts -destination "id=$R" -derivedDataPath build/sim-repro build-for-testing 2>&1 | grep -E "error:|BUILD" | tail -1
xcrun simctl install $R build/sim-repro/Build/Products/Debug-iphonesimulator/ScheduledTexts.app
xcrun simctl privacy $R grant contacts com.quasarbright.ScheduledTexts
xcrun simctl launch $R com.quasarbright.ScheduledTexts >/dev/null; sleep 3; xcrun simctl terminate $R com.quasarbright.ScheduledTexts
G=$(xcrun simctl get_app_container $R com.quasarbright.ScheduledTexts groups | awk '{print $2}')
DC=$(xcrun simctl get_app_container $R com.quasarbright.ScheduledTexts data)
P="$DC/Library/Preferences/com.quasarbright.ScheduledTexts.plist"
crashes=0; passes=0; other=0
for i in $(seq 1 $N); do
  xcrun simctl terminate $R com.quasarbright.ScheduledTexts 2>/dev/null
  python3 "$HERE/seed.py" "$G/messages.json" $VAR "$SAMPLE"
  if [ "$BDAY" = on ]; then
    HEX=$(printf '%s' '{"enabled":true,"message":"Happy birthday!","hour":9,"minute":0,"addNewBirthdays":true,"excluded":[],"known":[],"customMessages":{},"dismissedPrompts":[]}' | xxd -p | tr -d '\n')
    xcrun simctl spawn $R defaults write "${P%.plist}" birthdaySettings -data $HEX
  fi
  rm -rf build/$TAG-$i.xcresult
  OUT=$(env TEST_RUNNER_REPRO_ROUNDS=1 "$@" xcodebuild -project ScheduledTexts.xcodeproj -scheme ScheduledTexts -destination "id=$R" -derivedDataPath build/sim-repro -resultBundlePath build/$TAG-$i.xcresult -only-testing:DemoUITests/StopRepeatingReproTests test-without-building 2>&1)
  if echo "$OUT" | grep -q "crashed\|Crash"; then crashes=$((crashes+1)); echo "round $i: CRASH"; echo "$OUT" | grep -E "error:" | head -2
  elif echo "$OUT" | grep -q "no Undo\|passed ("; then passes=$((passes+1))
  else other=$((other+1)); echo "round $i: other"; echo "$OUT" | grep -E "error:" | head -2; fi
done
echo "$TAG: crashes=$crashes ok=$passes other=$other of $N"
