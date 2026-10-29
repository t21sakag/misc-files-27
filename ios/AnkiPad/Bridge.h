#ifndef ANKIPAD_BRIDGE_H
#define ANKIPAD_BRIDGE_H
#include "SpeechHTML.h"
void *ap_open(char **error_out);
// JSON array of preferred language tags; [] uses the engine's English fallback.
void *ap_open_with_languages(const char *languages_json, char **error_out);
char *ap_call(void *handle, const char *method, const char *request);
void ap_close(void *handle);
void ap_string_free(char *value);
#endif
