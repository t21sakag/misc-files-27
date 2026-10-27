#include "SpeechHTML.h"
#include <libxml/HTMLparser.h>
#include <libxml/tree.h>
#include <limits.h>
#include <ctype.h>
#include <string.h>
#include <strings.h>

/* Parse inert HTML locally. Never load external entities or network resources. */
static int named(const xmlNode *node, const char *name) {
    return node->type == XML_ELEMENT_NODE && !strcasecmp((const char *)node->name, name);
}
static int block(const xmlNode *node) {
    const char *names[] = {"br", "hr", "p", "div", "li", "ul", "ol", "table", "tr", "td", "th",
        "pre", "blockquote", "section", "article", "header", "footer", "h1", "h2", "h3", "h4", "h5", "h6"};
    for (unsigned i = 0; i < sizeof(names) / sizeof(*names); ++i) if (named(node, names[i])) return 1;
    return 0;
}
static int text_into(const xmlNode *node, xmlBufferPtr buffer) {
    for (; node; node = node->next) {
        if (node->type == XML_TEXT_NODE || node->type == XML_CDATA_SECTION_NODE) {
            if (node->content && xmlBufferCat(buffer, node->content)) return 0;
        } else if (node->type == XML_ELEMENT_NODE && !named(node, "script") && !named(node, "style")) {
            int spaced = block(node);
            if (spaced && xmlBufferCat(buffer, BAD_CAST " ")) return 0;
            if (!text_into(node->children, buffer)) return 0;
            if (spaced && xmlBufferCat(buffer, BAD_CAST " ")) return 0;
        }
    }
    return 1;
}
static int emit(const xmlNode *element, const char *locale, APSpeechSegmentCallback callback, void *context) {
    xmlBufferPtr text = xmlBufferCreate();
    if (!text) return 0;
    int ok = text_into(element->children, text);
    if (ok) callback((const char *)xmlBufferContent(text), locale, context);
    xmlBufferFree(text);
    return ok;
}
static int collect(const xmlNode *node, APSpeechSegmentCallback callback, void *context, int *count) {
    for (; node; node = node->next) {
        if (node->type != XML_ELEMENT_NODE || named(node, "script") || named(node, "style")) continue;
        xmlChar *service = named(node, "tts") ? xmlGetProp(node, BAD_CAST "service") : NULL;
        int match = service && !strcasecmp((const char *)service, "android");
        if (service) xmlFree(service);
        if (match) {
            xmlChar *voice = xmlGetProp(node, BAD_CAST "voice");
            int ok = emit(node, voice ? (const char *)voice : "", callback, context);
            if (voice) xmlFree(voice);
            if (!ok) return 0;
            ++*count; /* A matching outer element owns its nested text once. */
        } else if (!collect(node->children, callback, context, count)) return 0;
    }
    return 1;
}
int ap_speech_parse_html(const char *html, APSpeechSegmentCallback callback, void *context) {
    if (!html || !callback) return 0;
    size_t length = strlen(html);
    if (length > INT_MAX) return 0;
    int whitespace = 1;
    for (size_t i = 0; i < length; ++i) if (!isspace((unsigned char)html[i])) { whitespace = 0; break; }
    if (!length || whitespace) { callback("", "", context); return 1; }
    htmlDocPtr document = htmlReadMemory(html, (int)length, NULL, "UTF-8",
        HTML_PARSE_NONET | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING | HTML_PARSE_RECOVER);
    if (!document) return 0;
    xmlNode *root = xmlDocGetRootElement(document);
    const xmlNode *body = root;
    if (root) for (const xmlNode *child = root->children; child; child = child->next) if (named(child, "body")) { body = child; break; }
    int count = 0;
    int ok = body && collect(body, callback, context, &count);
    if (ok && !count) ok = emit(body, "", callback, context);
    xmlFreeDoc(document);
    return ok;
}
