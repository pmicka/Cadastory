from pathlib import Path
import re

root=Path('supabase/functions/scout-component-sandbox-mcp')
needle="z.discriminatedUnion('opportunity_type'"
changed=[]
for path in root.glob('*test*.mjs'):
    text=path.read_text()
    original=text
    pattern=re.compile(r'''assert\.ok\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\.includes\(["']z\.discriminatedUnion\(['"]opportunity_type['"]["']\)\)''')
    def repl(match):
        var=match.group('var')
        return f'''assert.ok({var}.includes("outputSchema: componentOutputSchema"))\nassert.ok({var}.includes("fromJsonSchema(sandboxResultSchema())"))'''
    text=pattern.sub(repl,text)
    if text!=original:
        path.write_text(text)
        changed.append(str(path))
remaining=[]
for path in root.glob('*test*.mjs'):
    if needle in path.read_text(): remaining.append(str(path))
if remaining:
    raise RuntimeError('stale z.discriminatedUnion assertions remain: '+', '.join(remaining))
print('Migrated discriminated-union assertions in',len(changed),'test files')
