"""Verify SyncService.SetCustomCertificate actually configures rustls trust over TLS."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading

from engine_smoke import Engine, lib, unpack


def raw_call(engine, method, args=None):
    return unpack(lib.ap_call(engine.handle, method.encode(), json.dumps(args or {}).encode()))


def generate_self_signed_cert(directory: Path):
    cert_path = directory / 'server.crt'
    key_path = directory / 'server.key'
    cnf_path = directory / 'req.cnf'
    cnf_path.write_text(
        '[req]\n'
        'distinguished_name = dn\n'
        'x509_extensions = v3_ext\n'
        'prompt = no\n'
        '[dn]\n'
        'CN = 127.0.0.1\n'
        '[v3_ext]\n'
        'basicConstraints = critical,CA:FALSE\n'
        'keyUsage = critical,digitalSignature,keyEncipherment\n'
        'extendedKeyUsage = serverAuth\n'
        'subjectAltName = IP:127.0.0.1\n',
        encoding='utf-8',
    )
    subprocess.run([
        'openssl', 'req', '-x509',
        '-newkey', 'rsa:2048',
        '-nodes',
        '-keyout', str(key_path),
        '-out', str(cert_path),
        '-days', '1',
        '-config', str(cnf_path),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return cert_path, key_path, cert_path.read_text(encoding='utf-8')


def main():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        cert_path, key_path, valid_pem = generate_self_signed_cert(root)
        requests_received = []

        class SyncProbeHandler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get('Content-Length') or 0)
                if length > 0:
                    self.rfile.read(length)
                requests_received.append(self.path)
                self.send_response(401)
                self.send_header('Content-Length', '0')
                self.end_headers()

            def do_GET(self):
                self.do_POST()

            def log_message(self, format, *args):
                pass

        class QuietTLSHTTPServer(HTTPServer):
            def handle_error(self, request, client_address):
                pass

        server = QuietTLSHTTPServer(('127.0.0.1', 0), SyncProbeHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        port = server.server_address[1]
        endpoint = f'https://127.0.0.1:{port}/'

        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        engine = Engine(root / 'col')
        try:
            valid_res = engine.call('SyncService.SetCustomCertificate', {'val': valid_pem})
            assert valid_res.get('val') is True, valid_res

            invalid_res = engine.call('SyncService.SetCustomCertificate', {'val': 'not-a-pem-cert'})
            assert not invalid_res.get('val', False), invalid_res

            double_res = engine.call('SyncService.SetCustomCertificate', {'val': valid_pem + '\n' + valid_pem})
            assert not double_res.get('val', False), double_res

            reset_res = engine.call('SyncService.SetCustomCertificate', {'val': ''})
            assert reset_res.get('val') is True, reset_res

            untrusted = raw_call(engine, 'SyncService.SyncLogin', {
                'username': 'u',
                'password': 'p',
                'endpoint': endpoint,
            })
            assert 'error' in untrusted, untrusted
            assert len(requests_received) == 0, requests_received

            enable_res = engine.call('SyncService.SetCustomCertificate', {'val': valid_pem})
            assert enable_res.get('val') is True, enable_res

            trusted = raw_call(engine, 'SyncService.SyncLogin', {
                'username': 'u',
                'password': 'p',
                'endpoint': endpoint,
            })
            assert len(requests_received) >= 1, (requests_received, trusted)
            after_trusted = len(requests_received)

            clear_res = engine.call('SyncService.SetCustomCertificate', {'val': ''})
            assert clear_res.get('val') is True, clear_res

            untrusted_again = raw_call(engine, 'SyncService.SyncLogin', {
                'username': 'u',
                'password': 'p',
                'endpoint': endpoint,
            })
            assert 'error' in untrusted_again, untrusted_again
            assert len(requests_received) == after_trusted, (requests_received, after_trusted)

            print('PASS: SyncService.SetCustomCertificate configures rustls TLS trust and reset cleanly')
        finally:
            server.shutdown()
            server.server_close()
            engine.close()


if __name__ == '__main__':
    main()
