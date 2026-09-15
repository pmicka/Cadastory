from pathlib import Path

path = Path('supabase/functions/scout-component-sandbox-mcp/sandbox_portfolio_test_fixtures.mjs')
text = path.read_text()
start_token = r"\n  if (type === 'municipal_facilities_portfolio') {"
end_token = "\n  const hotel = type === 'hotel_management_portfolio'"
start = text.find(start_token)
end = text.find(end_token, start)
if start < 0 or end < 0:
    raise RuntimeError('municipal fixture escaped block not found')
block = text[start:end]
block = block.replace(r'\n', '\n')
path.write_text(text[:start] + block + text[end:])
print('Converted municipal fixture escaped line endings to real newlines.')
