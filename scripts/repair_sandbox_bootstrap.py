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

old_dispatch_pattern = r'''r"    if \(opportunityType === 'dealership_group_portfolio'\) \{[\s\S]*?\n    \} else if \(opportunityType === 'swppp_site'\) \{"'''
new_dispatch_pattern = r'''r"  try \{\n    if \(opportunityType === 'dealership_group_portfolio'\) \{[\s\S]*?\n    \} else if \(opportunityType === 'swppp_site'\) \{"'''
if text.count(old_dispatch_pattern) != 1:
    raise RuntimeError('expected one unscoped portfolio View dispatch matcher')
text = text.replace(old_dispatch_pattern, new_dispatch_pattern)

old_dispatch_replacement = r'''"    if (isScoutSandboxPortfolioType(opportunityType)) {\n      const implementation = scoutSandboxPortfolioImplementation(opportunityType)'''
new_dispatch_replacement = r'''"  try {\n    if (isScoutSandboxPortfolioType(opportunityType)) {\n      const implementation = scoutSandboxPortfolioImplementation(opportunityType)'''
if text.count(old_dispatch_replacement) != 1:
    raise RuntimeError('expected one portfolio View dispatch replacement')
text = text.replace(old_dispatch_replacement, new_dispatch_replacement)

path.write_text(text)
print('Tightened sandbox bootstrap import matching, literal replacements, and View dispatch scope.')
