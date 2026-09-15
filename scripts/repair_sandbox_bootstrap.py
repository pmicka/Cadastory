from pathlib import Path

path = Path(__file__).with_name('bootstrap_sandbox_registry_hardening.py')
text = path.read_text()
old = r'''rf"import \{{[\s\S]*?\}} from './{module}\.ts'\n"'''
new = r'''rf"import \{{[^}}]+\}} from './{module}\.ts'\n"'''
count = text.count(old)
if count != 2:
    raise RuntimeError(f'expected two broad import matchers, found {count}')
path.write_text(text.replace(old, new))
print('Tightened sandbox bootstrap import matching.')
