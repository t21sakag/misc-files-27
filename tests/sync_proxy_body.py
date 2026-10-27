"""Read multipart requests emitted with either Content-Length or chunked HTTP."""
def read_body(handler):
    if handler.headers.get('Transfer-Encoding', '').lower() != 'chunked':
        return handler.rfile.read(int(handler.headers.get('Content-Length', '0')))
    chunks = []
    while True:
        size = int(handler.rfile.readline().split(b';', 1)[0].strip(), 16)
        if size == 0:
            while handler.rfile.readline().strip():
                pass
            return b''.join(chunks)
        chunks.append(handler.rfile.read(size))
        assert handler.rfile.read(2) == b'\r\n'
