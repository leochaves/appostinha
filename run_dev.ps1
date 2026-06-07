# Script para rodar em modo DEV com Supabase de desenvolvimento
# Preencha com as credenciais do projeto appostinha-dev no Supabase

$env:SUPABASE_URL_DEV = "https://SEU_PROJETO_DEV.supabase.co"
$env:SUPABASE_KEY_DEV = "sb_publishable_SUA_KEY_DEV"

flutter run -d chrome --web-port 3000 `
  --dart-define=SUPABASE_URL="$env:SUPABASE_URL_DEV" `
  --dart-define=SUPABASE_KEY="$env:SUPABASE_KEY_DEV" `
  --dart-define=APP_URL="http://localhost:3000"
