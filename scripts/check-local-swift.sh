#!/usr/bin/env bash
set -euo pipefail
ankipad_swiftc=${1:-swiftc}
mkdir -p build/local-swift
python3 scripts/check-swift-syntax.py --swiftc "$ankipad_swiftc"
"$ankipad_swiftc" -swift-version 5 -parse-as-library ios/AnkiPad/SyncDecision.swift tests/sync_decision_smoke.swift -o build/local-swift/sync-decision-smoke
build/local-swift/sync-decision-smoke
"$ankipad_swiftc" -swift-version 5 -parse-as-library ios/AnkiPad/ProfileRegistry.swift tests/profile_registry_smoke.swift -o build/local-swift/profile-registry-smoke
build/local-swift/profile-registry-smoke
"$ankipad_swiftc" -swift-version 5 -parse-as-library ios/AnkiPad/FieldImageReferences.swift tests/field_image_references_smoke.swift -o build/local-swift/field-image-references-smoke
build/local-swift/field-image-references-smoke
"$ankipad_swiftc" -swift-version 5 -parse-as-library ios/AnkiPad/ReviewGestureConfiguration.swift ios/AnkiPad/ReviewKeyboardConfiguration.swift ios/AnkiPad/ReviewGamepadConfiguration.swift ios/AnkiPad/ReviewTouchConfiguration.swift ios/AnkiPad/ReviewToolbarConfiguration.swift tests/gesture_configuration_smoke.swift -o build/local-swift/gesture-configuration-smoke
build/local-swift/gesture-configuration-smoke
"$ankipad_swiftc" -swift-version 5 -parse-as-library ios/AnkiPad/ReviewReminderConfiguration.swift tests/reminder_configuration_smoke.swift -o build/local-swift/reminder-configuration-smoke
build/local-swift/reminder-configuration-smoke
