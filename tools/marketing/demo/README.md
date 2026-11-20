# Cuentas demo para grabar videos

| Cuenta | Para qué | Cómo se arma |
|---|---|---|
| `demo@portyassistant.com` | Toma D (diagnóstico), toma E (chat), revisión de Apple (F8) | Crear el usuario en Supabase y correr `cuenta_demo.sql` |
| `demo.captura@portyassistant.com` | Toma C (importar la captura de ejemplo) | Crear el usuario y **no** correr el script: tiene que arrancar vacía |

Pasos (los hace el fundador; tocan producción):
1. Supabase → Authentication → Users → "Add user" → "Create new user", con email y contraseña y "Auto Confirm User". Los emails tienen que contener "demo".
2. Para `demo@…`: SQL Editor → pegar `cuenta_demo.sql` → Run. Al final dice "Cuenta demo … lista: 12 posiciones, plan Gold".
3. Entrar a la app con esa cuenta (email y contraseña) y verificar que se ve la cartera y el diagnóstico.

La cartera: 12 compras de 9 activos entre 2023 y 2025 (SPY, QQQ, AAPL, MSFT, NVDA, JNJ, JPM, KO, BND), tecnología alrededor del 50–55 % contando ETFs, AAPL directa y dentro de los ETFs, y ganancias o pérdidas por posición entre −8 % y +14 % (regla de compliance para videos). El script se puede volver a correr: reemplaza la cartera de esa cuenta.
