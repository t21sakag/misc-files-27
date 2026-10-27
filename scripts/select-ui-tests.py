#!/usr/bin/env python3
"""Emit discrete xcodebuild arguments; no user input is evaluated as shell code."""
import sys

suites = {
    'milestone': ['testPreviewCardAPIReadsAndRestoresFlag', 'testReviewVoicePanelClosesWithoutChangingCard', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'changed': ['testSwipeCanRevealAndAnswerThenUndo', 'testZZSharedDeckCanBeDownloadedAndImported', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'profiles': ['testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'shared': ['testZZSharedDeckCanBeDownloadedAndImported'],
    'sync': ['testAnkiWebLoginAndTokenSurviveRelaunch', 'testFullSyncWithLocalDataRequiresTypedUploadConfirmation'],
    'reviewer': ['testPreviewCardAPIReadsAndRestoresFlag', 'testReviewVoicePanelClosesWithoutChangingCard', 'testAnkiDroidCardJavaScriptReadsNativeMetadata', 'testAutoAdvancePausesWhileEditing', 'testCustomSchedulingChangesAnswerInterval', 'testImportedDeckCanBeReviewedAndUndone', 'testJavaScriptDialogsReturnNativeInputAndDecisions', 'testSwipeCanRevealAndAnswerThenUndo'],
    'all': [],
}
suite, mode = sys.argv[1:]
if suite not in suites or mode not in ('compile', 'ui', 'ipa', 'full'):
    raise SystemExit('Unknown CI mode or test suite')
for method in suites['all' if mode == 'full' else suite]:
    print('-only-testing:AnkiPadUITests/StudyFlowTests/' + method)
