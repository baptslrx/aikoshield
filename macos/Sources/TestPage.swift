enum TestPage {
    /// Fausses données (numéros d'exemple officiels) pour voir le bouclier en action.
    static let html = """
    <!doctype html>
    <html lang="fr"><head><meta charset="utf-8"><title>AikoShield — page de test</title>
    <style>
    :root { --bg:#fff; --surface:#F2F7FC; --text:#0B0D10; --sub:#5B6470; --accent:#7DC8FF; --accentText:#1F7FC8; --line:rgba(0,0,0,.08) }
    @media (prefers-color-scheme: dark) { :root { --bg:#0A0A0C; --surface:#17171A; --text:#F4F6F8; --sub:#9AA3AD; --accentText:#7DC8FF; --line:rgba(255,255,255,.09) } }
    * { box-sizing:border-box } body { margin:0; background:var(--bg); color:var(--text); font:16px/1.5 -apple-system, system-ui, sans-serif }
    main { max-width:880px; margin:0 auto; padding:48px 24px 80px }
    h1 { font-size:28px; margin:0 0 6px } .lead { color:var(--sub); margin:0 0 32px }
    .grid { display:grid; grid-template-columns:repeat(auto-fit, minmax(260px, 1fr)); gap:16px }
    .card { background:var(--surface); border:1px solid var(--line); border-radius:14px; padding:20px }
    .card h2 { font-size:12px; letter-spacing:.08em; text-transform:uppercase; color:var(--accentText); margin:0 0 12px }
    .row { display:flex; justify-content:space-between; gap:12px; padding:6px 0; border-bottom:1px solid var(--line) }
    .row:last-child { border:0 } .k { color:var(--sub) } code { font:14px ui-monospace, Menlo, monospace }
    .big { font-size:30px; font-weight:600; letter-spacing:.06em }
    .note { margin-top:28px; color:var(--sub); font-size:14px }
    </style></head><body><main>
    <h1>Page de test AikoShield</h1>
    <p class="lead">Active le bouclier (⌃ ⌥ S) : tout ce qui est sensible ci-dessous doit se couvrir. Les données sont fausses.</p>
    <div class="grid">
      <div class="card"><h2>Contacts</h2>
        <div class="row"><span class="k">E-mail</span><span>camille.martin@exemple.fr</span></div>
        <div class="row"><span class="k">Portable</span><span>06 12 34 56 78</span></div>
        <div class="row"><span class="k">Bureau</span><span>+33 1 23 45 67 89</span></div>
        <div class="row"><span class="k">Londres</span><span>+44 20 7946 0958</span></div>
      </div>
      <div class="card"><h2>Mes comptes</h2>
        <div class="row"><span class="k">Compte courant · Solde</span><span>2 450,10 €</span></div>
        <div class="row"><span class="k">Livret A</span><span>8 120,00 €</span></div>
        <div class="row"><span class="k">Virement Netflix</span><span>-13,49 €</span></div>
        <div class="row"><span class="k">IBAN</span><span>FR76 3000 6000 0112 3456 7890 189</span></div>
        <div class="row"><span class="k">Carte</span><span>4970 1012 3456 7890</span></div>
      </div>
      <div class="card"><h2>Codes et accès</h2>
        <div class="row"><span class="k">Votre code de vérification</span></div>
        <div class="row"><span class="big">482 913</span></div>
        <div class="row"><span class="k">Mot de passe : Soleil-Rouge-42</span></div>
      </div>
      <div class="card"><h2>Fichier .env</h2>
        <div class="row"><code>OPENAI_API_KEY=sk-proj-Xa82kd0Qp1LmZ7ve3nRt5Ybh</code></div>
        <div class="row"><code>DB_PASSWORD=Pr0d!Pass2026</code></div>
        <div class="row"><code>GITHUB_TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8</code></div>
      </div>
    </div>
    <p class="note">Ce qui doit rester visible : les titres, la date du 19/10/2026, la page 12 sur 345, et ce texte.</p>
    </main></body></html>
    """
}
