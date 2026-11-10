"""Bounded public trial; structural evidence is not translation signoff."""
import hashlib
import json
import os
import re
import sys
import time

EOS = '</s>'
MAX_INPUT = 180
MAX_OUTPUT = 384
MAX_BATCH = 8
MAX_WALL = 120
CONTROL = re.compile(r'<(?:2[^>]*|/?s|unk)>', re.I)


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def encode_case(sp, text, prefix='<2pa>'):
    if not isinstance(text, str) or not text.strip() or CONTROL.search(text):
        raise ValueError('empty or control-bearing input')
    tokens = sp.encode(prefix + ' ' + text, out_type=str) + [EOS]
    if not tokens or len(tokens) > MAX_INPUT or prefix not in tokens:
        raise ValueError('token limit or language prefix')
    return tokens


def check_result(row):
    if len(row.hypotheses) != 1:
        raise ValueError('wrong hypothesis count')
    tokens = row.hypotheses[0]
    if not tokens or tokens[-1] != EOS or EOS in tokens[:-1]:
        raise ValueError('missing or misplaced actual EOS')
    if len(tokens) == 1:
        raise ValueError('empty translation')
    return tokens[:-1]


def validate_cases(cases):
    if not isinstance(cases, list) or not 5 <= len(cases) <= 16:
        raise ValueError('fixture count')
    for idx, item in enumerate(cases):
        if set(item) != {'id', 'text', 'sha256'} or not isinstance(item['id'], str):
            raise ValueError('invalid fixture')
        if digest(item['text']) != item['sha256']:
            raise ValueError('fixture text differs from pinned hash')
        if any(other['id'] == item['id'] for other in cases[:idx]):
            raise ValueError('duplicate id')


def main(model, fixture_path, locale):
    import ctranslate2
    import sentencepiece as spm
    start = time.monotonic()
    with open(fixture_path, encoding='utf-8') as f:
        cases = json.load(f)
    validate_cases(cases)
    sp = spm.SentencePieceProcessor(model_file=os.path.join(model, 'spiece.model'))
    codes = {'pa':'pa', 'ur':'ur', 'ta':'ta', 'tl':'fil', 'fa':'fa', 'gu':'gu', 'bn':'bn', 'hu':'hu'}
    if locale not in codes: raise ValueError('unsupported trial locale')
    prefix = '<2' + codes[locale] + '>'
    if sp.piece_to_id(prefix) <= 0 or sp.id_to_piece(sp.piece_to_id(prefix)) != prefix:
        raise ValueError('missing exact target token')
    encoded = [encode_case(sp, c['text'], prefix) for c in cases]
    load = time.monotonic()
    translator = ctranslate2.Translator(model, device='cpu', compute_type='int8', intra_threads=4, inter_threads=1)
    loaded = time.monotonic()
    if translator.compute_type not in ('int8', 'int8_float32'):
        raise ValueError('unexpected compute type')
    # Forced truncation is a required negative control, not a successful result.
    control = translator.translate_batch([encoded[0]], beam_size=1, max_decoding_length=1,
                                         max_input_length=0, return_end_token=True)
    try:
        check_result(control[0])
    except ValueError:
        negative_rejected = True
    else:
        raise ValueError('negative control unexpectedly ended normally')
    begin = time.monotonic()
    rows = translator.translate_batch(encoded, max_batch_size=MAX_BATCH, batch_type='examples',
                                      beam_size=4, max_input_length=0, max_decoding_length=MAX_OUTPUT,
                                      return_end_token=True)
    elapsed = time.monotonic() - begin
    if elapsed > MAX_WALL or len(rows) != len(cases):
        raise ValueError('inference wall or output count')
    result = []
    for index, (case, row) in enumerate(zip(cases, rows)):
        tokens = check_result(row)
        text = sp.decode(tokens)
        if not text.strip():
            raise ValueError('empty decoded output')
        result.append({'index': index, 'id': case['id'], 'sourceSHA256': case['sha256'],
                       'source': case['text'], 'translation': text, 'actualEOS': True,
                       'outputTokens': len(tokens)})
    print(json.dumps({'scope': 'public CPU batch trial; meaning requires human review',
                      'locale': locale, 'prefix': prefix, 'computeType': translator.compute_type, 'threads': 4, 'batchMaximum': MAX_BATCH, 'beamSize': 4,
                      'loadSeconds': round(loaded-load, 3), 'batchSeconds': round(elapsed, 3),
                      'totalSeconds': round(time.monotonic()-start, 3), 'negativeControlRejected': negative_rejected,
                      'results': result}, ensure_ascii=False))


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.platform != 'linux':
        raise SystemExit('usage on Linux: trial.py MODEL_DIR FIXTURES_JSON LOCALE')
    main(*sys.argv[1:])
