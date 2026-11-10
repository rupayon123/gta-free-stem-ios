import struct
import unittest
from madlad_linux_smoke import frame, rss_bytes


class LinuxSmokeTests(unittest.TestCase):
    def test_rss_kib_is_converted_to_bytes(self):
        self.assertEqual(rss_bytes('Name:\tworker\nVmRSS:\t1234 kB\n'), 1234 * 1024)
        with self.assertRaises(ValueError):
            rss_bytes('VmRSS: 1234 MB')

    def test_utf8_frame_contains_exact_byte_length(self):
        raw = 'ਪੰਜਾਬੀ'.encode()
        self.assertEqual(frame('ਪੰਜਾਬੀ'), struct.pack('>I', len(raw)) + raw)


if __name__ == '__main__':
    unittest.main()
