from pathlib import Path
import re

root=Path('supabase/functions/scout-component-sandbox-mcp')
old='opportunity_type: z.enum(SCOUT_SANDBOX_OPPORTUNITY_TYPES).optional()'
changed=[]
for path in root.glob('*test*.mjs'):
    text=path.read_text()
    original=text
    pattern=re.compile(r'assert\.ok\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\.includes\(["\']opportunity_type: z\.enum\(SCOUT_SANDBOX_OPPORTUNITY_TYPES\)\.optional\(\)["\']\)\)')
    def repl(match):
        var=match.group('var')
        return f'''assert.ok({var}.includes("inputSchema: componentInputSchema"))\nassert.ok({var}.includes("outputSchema: componentOutputSchema"))\nassert.ok({var}.includes("fromJsonSchema(sandboxResultSchema())"))'''
    text=pattern.sub(repl,text)
    if text!=original:
        path.write_text(text)
        changed.append(str(path))

remaining=[]
for path in root.glob('*test*.mjs'):
    if old in path.read_text(): remaining.append(str(path))
if remaining:
    raise RuntimeError('stale inline Zod selector assertions remain: '+', '.join(remaining))
print('Migrated shared-schema assertions in', len(changed), 'test files')
