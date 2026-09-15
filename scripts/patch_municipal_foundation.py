from pathlib import Path
path=Path('supabase/functions/scout-component-sandbox-mcp/foundation_test.mjs')
text=path.read_text()
old='''assert.ok(server.includes("premiumOpportunitySchema"));\nassert.ok(server.includes("waterTankOpportunitySchema"));\nassert.ok(server.includes("z.discriminatedUnion(\\\'opportunity_type\\\'"));'''
new='''assert.ok(server.includes("fromJsonSchema(sandboxOpportunityTypeInputSchema())"));\nassert.ok(server.includes("fromJsonSchema(sandboxResultSchema())"));\nassert.ok(server.includes("inputSchema: componentInputSchema"));\nassert.ok(server.includes("outputSchema: componentOutputSchema"));\nassert.equal(server.includes("componentResultSchemaByType"), false);'''
if old not in text:
    raise RuntimeError('foundation schema assertion anchor not found')
path.write_text(text.replace(old,new,1))
print('Updated foundation shared-schema invariant.')
