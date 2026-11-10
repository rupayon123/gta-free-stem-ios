import struct
import unittest
from madlad_linux_smoke import frame, rss_bytes, sanitized_stderr


class LinuxSmokeTests(unittest.TestCase):
    def test_rss_kib_is_converted_to_bytes(self):
        self.assertEqual(rss_bytes('Name:\tworker\nVmRSS:\t1234 kB\n'), 1234 * 1024)
        with self.assertRaises(ValueError):
            rss_bytes('VmRSS: 1234 MB')

    def test_utf8_frame_contains_exact_byte_length(self):
        raw = 'ਪੰਜਾਬੀ'.encode()
        self.assertEqual(frame('ਪੰਜਾਬੀ'), struct.pack('>I', len(raw)) + raw)

    def test_failure_diagnostics_are_tail_bounded_and_paths_redacted(self):
        raw = b'x' * 9000 + b' /tmp/worker /tmp/model /tmp/libggml-cpu-x64.so'
        result = sanitized_stderr(raw, '/tmp/worker', '/tmp/model', '/tmp/libggml-cpu-x64.so')
        self.assertLessEqual(len(result.encode('utf-8')), 8192 + 32)
        self.assertNotIn('/tmp/worker', result)
        self.assertNotIn('/tmp/model', result)
        self.assertNotIn('/tmp/libggml-cpu-x64.so', result)
        self.assertIn('<cpu-backend>', result)


if __name__ == '__main__':
    unittest.main()
