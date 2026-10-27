"""Exercise the actual inert HTML parser shared with the iOS app."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
callback_type = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p)
lib.ap_speech_parse_html.argtypes = [ctypes.c_char_p, callback_type, ctypes.c_void_p]
lib.ap_speech_parse_html.restype = ctypes.c_int

def parse(html):
    result = []
    def receive(text, locale, context):
        result.append((' '.join((text or b'').decode().split()), locale.decode()))
    callback = callback_type(receive)
    assert lib.ap_speech_parse_html(html.encode(), callback, None) == 1
    return result

assert parse('<p>one <b>two</b></p><div>three<br>four</div>') == [('one two three four', '')]
assert parse('a<span>b</span>c &amp; 日本語&nbsp;語') == [('abc & 日本語 語', '')]
assert parse('<script>bad()</script><style>bad{}</style><!--bad-->safe') == [('safe', '')]
assert parse('<tts SERVICE="ANDROID" voice="en_US">Hello <b>world</b></tts><tts service="android" voice="ja_JP">日本語</tts>outside') == [('Hello world', 'en_US'), ('日本語', 'ja_JP')]
assert parse('<tts service=android voice=fr><tts service=android voice=de>inner</tts> outer</tts>') == [('inner outer', 'fr')]
assert parse('<tts service=other>whole</tts>') == [('whole', '')]
assert parse('<tts service=android voice=en><b>unclosed') == [('unclosed', 'en')]
assert parse('') == [('', '')]
assert parse(' \n \t') == [('', '')]
print('PASS: localized legacy TTS segments; nested ownership; malformed HTML; whitespace/entities; inert script/style; UTF-8')
