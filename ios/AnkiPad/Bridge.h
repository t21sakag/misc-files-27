#ifndef ANKIPAD_BRIDGE_H
#define ANKIPAD_BRIDGE_H
void *ap_open(char **error_out);
char *ap_call(void *handle, const char *method, const char *request);
void ap_close(void *handle);
void ap_string_free(char *value);
#endif
