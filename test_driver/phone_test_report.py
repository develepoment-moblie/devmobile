"""Builds build/phone_test/rapport.html from the phone test results.

Run after the full module test:
    python test_driver/phone_test_report.py
Every step with its result, how it was done and its screenshot (embedded,
so the page can be sent as one file).
"""
import base64
import html
import json
import sys
from datetime import datetime
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'build' / 'phone_test'
data = json.loads((root / 'steps.json').read_text(encoding='utf-8'))
steps = data.get('steps', data)
extra = (root / 'host_checks.json')
host = json.loads(extra.read_text(encoding='utf-8')) if extra.exists() else []

passed = sum(1 for s in steps if s['status'] == 'passed')


def badge_of(ok):
    return ('<span class="ok">Réussi</span>' if ok
            else '<span class="ko">Échec</span>')


rows, cards = [], []
phase = None
for s in steps:
    ok = s['status'] == 'passed'
    badge = badge_of(ok)
    rows.append(
        f"<tr><td>{s['n']}</td><td>{html.escape(s['title'])}</td><td>{badge}</td>"
        f"<td>{s['ms'] / 1000:.1f} s</td></tr>"
    )
    if s['phase'] != phase:
        phase = s['phase']
        cards.append(f'<h2>{html.escape(phase)}</h2>')
    image = root / s['screenshot']
    img = ''
    if image.exists():
        b64 = base64.b64encode(image.read_bytes()).decode()
        img = f'<img src="data:image/png;base64,{b64}" alt="{html.escape(s["title"])}">'
    cards.append(f'''
<section class="step {'pass' if ok else 'fail'}">
  <div class="text">
    <p class="num">Étape {s['n']} · {badge}</p>
    <h3>{html.escape(s['title'])}</h3>
    <p><b>Action :</b> {html.escape(s['how'])}</p>
    <p><b>Résultat :</b> {html.escape(s.get('detail') or '')}</p>
  </div>
  {img}
</section>''')

host_html = ''
if host:
    items = ''.join(
        f"<li>{badge_of(h['ok'])} "
        f"{html.escape(h['title'])} — {html.escape(h['detail'])}</li>"
        for h in host
    )
    host_html = f'<h2>Vérifications depuis l’ordinateur (adb)</h2><ul class="host">{items}</ul>'

page = f'''<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test du module ménage</title>
<style>
:root {{ --green:#183C35; --accent:#C66F55; --bg:#F7F3EA; --ink:#25322F; --muted:#77837F; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font-family:system-ui,sans-serif; }}
main {{ max-width:980px; margin:0 auto; padding:24px 16px 64px; }}
header {{ background:var(--green); color:#fff; border-radius:18px; padding:22px; }}
header h1 {{ margin:0 0 6px; font-size:24px; }}
header p {{ margin:2px 0; opacity:.85; }}
table {{ width:100%; border-collapse:collapse; margin:18px 0; background:#fff; border-radius:12px; overflow:hidden; }}
td,th {{ padding:7px 10px; border-bottom:1px solid #e5e5e0; text-align:left; font-size:14px; }}
h2 {{ color:var(--green); margin-top:34px; }}
.step {{ display:flex; gap:18px; background:#fff; border-radius:16px; padding:16px; margin:12px 0; border-left:6px solid #5E8D75; }}
.step.fail {{ border-left-color:#BA5D51; }}
.step .text {{ flex:1; min-width:0; }}
.step h3 {{ margin:4px 0 8px; }}
.step img {{ width:220px; border-radius:12px; border:1px solid #ddd; align-self:flex-start; }}
.num {{ color:var(--muted); margin:0; font-size:13px; }}
.ok {{ background:#E5EFE8; color:#2f6b4f; padding:2px 8px; border-radius:10px; font-size:12px; font-weight:700; }}
.ko {{ background:#F5E4E0; color:#BA5D51; padding:2px 8px; border-radius:10px; font-size:12px; font-weight:700; }}
.host li {{ margin:6px 0; }}
@media (max-width:640px) {{ .step {{ flex-direction:column; }} .step img {{ width:100%; }} }}
</style></head><body><main>
<header>
  <h1>Test complet du module « Chambres et ménage »</h1>
  <p>Xiaomi 21081111RG · Android 14 · {datetime.now().strftime('%d/%m/%Y %H:%M')}</p>
  <p><b>{passed} / {len(steps)} étapes réussies</b> · base de test séparée (nova_paris_e2e.db), données réelles non touchées</p>
</header>
<table><tr><th>#</th><th>Étape</th><th>Résultat</th><th>Durée</th></tr>{''.join(rows)}</table>
{host_html}
{''.join(cards)}
<h2>Non testable automatiquement</h2>
<ul>
<li>Écrans d’Android : appareil photo, galerie, partage (Drive, e-mail), choix d’un fichier, demandes d’autorisation. Les photos ont été injectées par les règles du module.</li>
<li>Qualité sonore de la note vocale (enregistrée et relue par le test, à écouter).</li>
<li>Alerte après redémarrage du téléphone et effet de l’économiseur de batterie MIUI.</li>
</ul>
</main></body></html>'''
out = root / 'rapport.html'
out.write_text(page, encoding='utf-8')
print(out, f'{passed}/{len(steps)}')
sys.exit(0)
