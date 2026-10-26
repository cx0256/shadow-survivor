"""One-shot diagnostics using the installed Maker LSP's stdio implementation.

Use the Maker-managed Python interpreter (lua-lsp-venv/Scripts/python.exe).
The package currently bundles emmylua_ls but no emmylua_check on Windows.
"""
import json
import logging
from pathlib import Path
from maker_lua_lsp.__main__ import LuaLSPServer

logging.getLogger().setLevel(logging.ERROR)
root = Path(__file__).resolve().parent
out = root / '.tmp' / 'lsp'
out.mkdir(parents=True, exist_ok=True)
server = LuaLSPServer(str(root / 'scripts'), str(out / 'diagnostics.log'),
                      str(out / 'errors.log'), mode='watch')
try:
    server.running = True
    server._start_lsp_process()
    server._initialize_lsp()
    for script in (root / 'scripts').rglob('*.lua'):
        server.check_file(str(script))
    server._wait_for_initial_diagnostics(quiet_seconds=2.0, first_message_timeout=15.0)
    errors = {name: [d for d in values if d.get('severity') == 1]
              for name, values in server.diagnostics.items()}
    errors = {name: values for name, values in errors.items() if values}
    (out / 'errors.json').write_text(json.dumps(errors, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, values in errors.items():
        for d in values:
            print(f"{Path(name).name}:{d['range']['start']['line'] + 1}: {d.get('code')}: {d['message']}")
    print(f"LSP: {sum(map(len, errors.values()))} errors in {len(errors)} files")
finally:
    server.stop()
raise SystemExit(1 if errors else 0)
