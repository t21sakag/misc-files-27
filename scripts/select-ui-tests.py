#!/usr/bin/env python3
"""Emit discrete xcodebuild arguments; no user input is evaluated as shell code."""
import sys
import json
from pathlib import Path

suites = {
    'milestone': ['testPreviewCardAPIReadsAndRestoresFlag', 'testReviewVoicePanelClosesWithoutChangingCard', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'changed': ['testSwipeCanRevealAndAnswerThenUndo', 'testZZSharedDeckCanBeDownloadedAndImported', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'profiles': ['testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'shared': ['testZZSharedDeckCanBeDownloadedAndImported'],
    'backups': ['testStoredBackupCanBeSharedToFiles', 'testStoredBackupRestoresAndPreservesCurrentCollection'],
    'automatic': ['testAutomaticSyncRunsAtStartupAndForeground', 'testAutomaticSyncPushesChangesInBackground', 'testAutomaticSyncCanBeDisabledPersistently', 'testAutomaticFullDownloadRequiresDirectionChoice', 'testAutomaticFullUploadRequiresDirectionChoice', 'testAnkiWebLoginAndTokenSurviveRelaunch', 'testSyncExpirationNotifiesAndRetriesFullDownload'],
    'sync': ['testAnkiWebLoginAndTokenSurviveRelaunch', 'testFullSyncConflictShowsLocalCounts', 'testFullSyncWithLocalDataRequiresTypedUploadConfirmation', 'testSyncExpirationNotifiesAndRetriesFullDownload', 'testSyncFinishesInBackground', 'testSyncInterruptedLaunchWarnsAfterTermination'],
    'repair': ['testAutoAdvancePausesWhileEditing', 'testAutomaticFullDownloadRequiresDirectionChoice', 'testAutomaticFullUploadRequiresDirectionChoice', 'testAutomaticSyncCanBeDisabledPersistently', 'testAutomaticSyncPushesChangesInBackground', 'testAutomaticSyncRunsAtStartupAndForeground', 'testImportedDeckCanBeReviewedAndUndone', 'testNoteCanBeCreatedAndFoundInBrowser', 'testPreviewCardAPIReadsAndRestoresFlag', 'testPreviewFlagPersistsAfterClosing', 'testReviewVoicePanelClosesWithoutChangingCard', 'testSwipeCanRevealAndAnswerThenUndo', 'testAnkiWebLoginAndTokenSurviveRelaunch', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'reviewer': ['testPreviewCardAPIReadsAndRestoresFlag', 'testReviewVoicePanelClosesWithoutChangingCard', 'testAnkiDroidCardJavaScriptReadsNativeMetadata', 'testAutoAdvancePausesWhileEditing', 'testCustomSchedulingChangesAnswerInterval', 'testImportedDeckCanBeReviewedAndUndone', 'testJavaScriptDialogsReturnNativeInputAndDecisions', 'testSwipeCanRevealAndAnswerThenUndo'],
    'collapse': ['testSubdeckCollapsePersistsAndParentReviewsChildren'],
    'reminders': ['testReminderNativeSchedulePersistsReplacesAndCancels'],
    'p1': ['testReminderNativeSchedulePersistsReplacesAndCancels', 'testHierarchicalTagsCollapseRenameMoveAndRemoveWithoutDeletingNote'],
    'images': ['testImageEditsPreserveExpectedPhysicalPixels', 'testImageAnnotationIsCompositedAtCanvasScale', 'testPhotoEditsAndDrawingPersistWhenReeditingNote'],
    'controls': ['testCustomToolbarAndTouchAssignmentPersistAndPerformNativeActions'],
    'p1-next': ['testPhotoEditsAndDrawingPersistWhenReeditingNote', 'testZZZProfilesKeepCollectionsAndAccountsSeparate'],
    'voice': ['testCardAudioQueueCompletesOnceAndCancellationDoesNotReplay', 'testReviewRecordingReferenceComparisonAndTemporaryCleanup'],
    'speech': ['testInstalledVoiceSelectionPersistsAndQuestionAnswerChoicesAreSeparate', 'testAutomaticSpeechChoiceAndNestedReferencePickerCanCancelAndResume', 'testNativeSpeechSynthesisQueueCompletes'],
    'occlusion': ['testZImageOcclusionCanBeCreatedFromPhoto', 'testImageOcclusionMaskCopyPersistsAndDiscardPreservesSavedMasks'],
    'whiteboard': ['testWhiteboardUndoesStrokesAndKeepsPerDeckVisibility', 'testImportedDeckCanBeReviewedAndUndone'],
    'preview': ['testPreviewCardAPIReadsAndRestoresFlag', 'testPreviewNativeToastAndTagDialogPersistToPreviewedNote', 'testPreviewFlagPersistsAfterClosing'],
    'network': ['testNetworkSyncSettingsSurviveRelaunchAndCancelDoesNotSave', 'testRequestedOneWaySyncPresentsSafeDirectionChoice'],
    'timebox': ['testTimeboxReportsRealElapsedMinuteAndCanContinueOrFinish'],
    'appearance': ['testAnswerLayoutPersistsWithTopLargeButtonsAndHiddenMode', 'testCustomToolbarAndTouchAssignmentPersistAndPerformNativeActions'],
    'answer-layout': ['testAnswerLayoutPersistsWithTopLargeButtonsAndHiddenMode'],
    'layout-regression': ['testAnswerLayoutPersistsWithTopLargeButtonsAndHiddenMode', 'testFullscreenCanBeRestoredWithTripleTap'],
    'card-appearance': ['testImageOnlyZoomAndVerticalCenterSurviveRelaunch'],
    'templates': ['testAnkiDroidCardJavaScriptReadsNativeMetadata', 'testPreviewCardAPIReadsAndRestoresFlag'],
    'all': [],
}
suite, mode = sys.argv[1:]
if suite not in suites or mode not in ('compile', 'ui', 'ipa', 'full'):
    raise SystemExit('Unknown CI mode or test suite')
groups = json.loads(Path(__file__).with_name('ui-case-groups.json').read_text())
classes = {method: name for name, methods in groups.items() for method in methods}
for method in suites['all' if mode == 'full' else suite]:
    print('-only-testing:AnkiPadUITests/' + classes[method] + '/' + method)
