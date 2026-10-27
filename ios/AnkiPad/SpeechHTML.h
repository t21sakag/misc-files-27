#ifndef STUDY_SPEECH_HTML_H
#define STUDY_SPEECH_HTML_H
/* Callback pointers are valid only during the synchronous callback. */
typedef void (*APSpeechSegmentCallback)(const char *text, const char *locale, void *context);
int ap_speech_parse_html(const char *html, APSpeechSegmentCallback callback, void *context);
#endif
