from pathlib import Path

path = Path(__file__).with_name('bootstrap_sandbox_registry_hardening.py')
text = path.read_text()

old_import = r'''rf"import \{{[\s\S]*?\}} from './{module}\.ts'\n"'''
new_import = r'''rf"import \{{[^}}]+\}} from './{module}\.ts'\n"'''
count = text.count(old_import)
if count != 2:
    raise RuntimeError(f'expected two broad import matchers, found {count}')
text = text.replace(old_import, new_import)

old_subn = "updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)"
new_subn = "updated, count = re.subn(pattern, lambda _match: replacement, text, count=1, flags=flags)"
if text.count(old_subn) != 1:
    raise RuntimeError('expected one bootstrap sub_once implementation')
text = text.replace(old_subn, new_subn)

path.write_text(text)
print('Tightened sandbox bootstrap import matching and literal replacements.')
