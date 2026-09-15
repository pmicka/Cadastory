from pathlib import Path

path=Path('supabase/functions/scout-component-sandbox-mcp/water_tank_map_contract_test.mjs')
text=path.read_text()
old='assert.ok(serverSource.includes("opportunity_type: z.enum(SCOUT_SANDBOX_OPPORTUNITY_TYPES).optional()"))'
new='''assert.ok(serverSource.includes("inputSchema: componentInputSchema"))
assert.ok(serverSource.includes("outputSchema: componentOutputSchema"))
assert.ok(serverSource.includes("fromJsonSchema(sandboxResultSchema())"))'''
if old not in text:
    raise RuntimeError('water tank shared-schema assertion anchor not found')
path.write_text(text.replace(old,new,1))
print('Updated legacy schema wiring assertions.')
