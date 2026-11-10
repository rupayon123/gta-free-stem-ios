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

if __name__ == '__main__': unittest.main()
