# Apostinha

App de palpites com badges de acerto. Sem dinheiro real — só diversão.

---

## Stack

- **Flutter** (web + Android)
- **Supabase** — auth, banco Postgres, RPC functions

---

## Setup

### 1. Supabase

1. Crie um projeto em [supabase.com](https://supabase.com)
2. SQL Editor → rode em ordem:
   - `supabase/schema.sql`
   - `supabase/migration_v2.sql`
   - `supabase/migration_v3.sql`
3. Authentication → Providers → Email → desligar **"Confirm email"**
4. Authentication → URL Configuration:
   - **Site URL:** `http://localhost:3000`
   - **Redirect URLs:** `http://localhost:3000`

### 2. Flutter

```bash
# Preencha suas credenciais
# lib/config.dart
const supabaseUrl = 'https://SEU_ID.supabase.co';
const supabaseAnonKey = 'sb_publishable_...';

# Instale dependências
flutter pub get

# Rode na porta fixa (necessário para recuperação de senha)
flutter run -d chrome --web-port 3000
```

---

## Estrutura do banco

```
tournaments          → agrupador raiz (ex: Tenis Parque 2025)
  └── categories     → subagrupador (ex: 4ª Classe Masculino)
        └── events   → jogo ou aposta (ex: João vs Pedro)
              └── options  → opções de palpite (ex: João, Pedro)

profiles             → usuário + username
bets                 → palpites feitos por cada usuário
badges               → definições de conquistas
user_badges          → conquistas ganhas por cada usuário
```

---

## Como funciona

### Hierarquia
- Qualquer usuário logado pode criar torneios, categorias e eventos
- Cada evento tem 2–8 opções separadas por vírgula na criação

### Palpites
- Uma previsão por evento por usuário
- Porcentagem calculada em tempo real: `opção_count / total_count`
- Não há moeda — só o acerto conta

### Resolver evento
- Criador do evento toca **"🏆 Venceu"** na opção vencedora
- Badges são entregues automaticamente no banco (função `resolve_event`)

### Badges

| Badge | Condição |
|---|---|
| 🎯 Palpiteiro | Primeiro palpite |
| 🍀 Sortudo | Primeiro acerto |
| 🔍 Analista | 5 acertos |
| ⭐ Expert | 10 acertos |
| 🔮 Oráculo | 25 acertos |

---

## Funções SQL (RPC)

| Função | Descrição |
|---|---|
| `make_prediction(user_id, event_id, option_id)` | Registra palpite + badge de primeira previsão |
| `resolve_event(event_id, winning_option_id)` | Resolve evento + entrega badges de acerto |

---

## Arquivos principais

```
lib/
├── config.dart                    ← credenciais Supabase
├── main.dart                      ← roteamento por auth state
├── models/                        ← Tournament, Category, Event, Bet, Badge...
└── screens/
    ├── auth_screen.dart           ← login / cadastro / recuperar senha
    ├── update_password_screen.dart
    ├── home_screen.dart           ← lista de torneios
    ├── tournament_detail_screen.dart
    ├── category_detail_screen.dart
    ├── event_detail_screen.dart   ← palpitar / resolver / editar / deletar
    ├── create_tournament_screen.dart
    ├── create_category_screen.dart
    ├── create_event_screen.dart   ← opções separadas por vírgula
    └── profile_screen.dart        ← badges + histórico

supabase/
├── schema.sql         ← schema inicial
├── migration_v2.sql   ← hierarquia + badges (rode após schema)
└── migration_v3.sql   ← cascade deletes + políticas de DELETE
```
