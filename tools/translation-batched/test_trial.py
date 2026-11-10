import unittest
from types import SimpleNamespace
from trial import check_result, encode_case, validate_cases, digest

class Tokenizer:
    def encode(self, text, out_type):
        return ['<2pa>'] + text.split()[1:]

class TrialTests(unittest.TestCase):
    def test_actual_eos_required(self):
        self.assertEqual(check_result(SimpleNamespace(hypotheses=[['text', '</s>']])), ['text'])
        for tokens in ([], ['text'], ['</s>'], ['</s>', 'text']):
            with self.assertRaises(ValueError): check_result(SimpleNamespace(hypotheses=[tokens]))
    def test_control_and_limit(self):
        self.assertEqual(encode_case(Tokenizer(), 'Hello')[-1], '</s>')
        for value in ('<2fr> injected', 'word ' * 180, ''):
            with self.assertRaises(ValueError): encode_case(Tokenizer(), value)
    def test_identity_binding(self):
        cases = [{'id': str(n), 'text': 'hello', 'sha256': digest('hello')} for n in range(5)]
        validate_cases(cases)
        cases[2]['text'] = 'changed'
        with self.assertRaises(ValueError): validate_cases(cases)

class GuardExitRaceTests(unittest.TestCase):
    def run_guard(self, process):
        import contextlib, io, runpy, sys
        from pathlib import Path
        from unittest.mock import patch, mock_open
        output = io.StringIO()
        with patch.object(sys, 'platform', 'linux'), patch.object(sys, 'argv', ['guard.py', 'fake-worker']), patch('subprocess.Popen', return_value=process), patch('builtins.open', mock_open(read_data='State: Z (zombie)')), patch('time.sleep'), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            runpy.run_path(str(Path(__file__).with_name('guard.py')), run_name='__main__')
        return output.getvalue()

    def test_normal_exit_without_last_rss_is_not_failure(self):
        from unittest.mock import Mock
        p = Mock(pid=123, returncode=0)
        p.poll.side_effect = [None, None, 0]
        p.communicate.return_value = (b'{"actualEOS":true}', b'')
        output = self.run_guard(p)
        self.assertIn('"guardStop": null', output)
        self.assertIn('"actualEOS":true', output)
        p.kill.assert_not_called()

    def test_unobservable_live_process_still_fails_closed(self):
        from unittest.mock import Mock
        p = Mock(pid=123, returncode=-9)
        p.poll.return_value = None
        p.communicate.return_value = (b'', b'')
        with self.assertRaises(SystemExit):
            self.run_guard(p)
        p.kill.assert_called_once()

if __name__ == '__main__': unittest.main()
