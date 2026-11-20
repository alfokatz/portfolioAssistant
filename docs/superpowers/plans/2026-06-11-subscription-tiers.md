# Subscription Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Free / Premium / Gold subscription tiers with mode gating, monthly AI query quotas (news = 3× weight), position limits, and paywall UI.

**Architecture:** Domain policy classes define tier rules. `PreferencesManager` persists tier (local until billing) and monthly usage counter. `SubscriptionService` coordinates quota checks/resets. Gates in `AssistantProvider`, `ModeChipBar`, `HomeScreen`, and add-position flow. Paywall sheet offers Premium + Gold upgrade (stub until billing).

**Tech Stack:** Flutter, Riverpod, Supabase (RLS + RPC), easy_localization, RevenueCat (next)

**Server source of truth (2026-06-11):** `user_subscriptions` + `ai_usage_monthly` in Supabase. Tier and usage are NOT stored in SharedPreferences. RPCs: `get_subscription_status`, `consume_ai_quota`. RevenueCat webhook stub: `supabase/functions/revenuecat-webhook/`.

---

## Tier Rules (spec)

| Tier | Monthly quota | Modes | Positions | Benchmark | News (3× weight) |
|------|---------------|-------|-----------|-----------|------------------|
| Free | 20 | portfolio, learn | 10 | no | no |
| Premium | 500 | + explore | unlimited | yes | no |
| Gold | 1000 | + invest, plan | unlimited | yes | yes |

- 1 consulta = 1 OpenAI call that succeeds
- News queries consume 3 from quota (Gold only)
- Reset counter on new calendar month

---

### Task 1: Domain — tier models & policy

**Files:**
- Create: `lib/domain/entities/subscription_tier.dart`
- Create: `lib/domain/subscription/ai_usage_limits.dart`
- Create: `lib/domain/subscription/subscription_policy.dart`
- Create: `test/domain/subscription/subscription_policy_test.dart`

Policy methods:
- `monthlyQuota(SubscriptionTier)`
- `isModeAllowed(SubscriptionTier, AssistantMode)`
- `positionLimit(SubscriptionTier)` → 10 or null (unlimited)
- `isBenchmarkAllowed(SubscriptionTier)`
- `isNewsAllowed(SubscriptionTier)`
- `queryWeight({required bool isNewsQuery})` → 3 or 1

---

### Task 2: Persistence — tier & usage in PreferencesManager

**Files:**
- Modify: `lib/domain/managers/preferences_manager.dart`
- Modify: `lib/infraestructure/managers/preferences_manager_impl.dart`
- Create: `lib/domain/subscription/ai_usage_tracker.dart`
- Create: `test/domain/subscription/ai_usage_tracker_test.dart`

Keys: `subscription_tier`, `ai_queries_used`, `ai_usage_month`
Methods: get/set tier, getUsage(), canConsume(weight), recordUsage(weight), resetIfNewMonth()

---

### Task 3: Subscription provider

**Files:**
- Create: `lib/features/subscription/providers/subscription_provider.dart`
- Expose: tier, used, limit, remaining, canAccessMode, checkQueryAllowed

---

### Task 4: Assistant gating

**Files:**
- Modify: `lib/features/assistant/providers/assistant_provider.dart`
- Modify: `lib/features/assistant/states/assistant_state.dart` (paywall trigger)
- Modify: `lib/features/assistant/utils/assistant_snapshot_builder.dart` (skip news enricher if !gold)
- Create: `test/features/assistant/subscription/assistant_subscription_gate_test.dart`

Gate order in sendMessage: mode → news tier → quota → execute → recordUsage on success
Gate selectMode/switchModeAndSend: mode allowed check

---

### Task 5: Paywall UI

**Files:**
- Create: `lib/features/subscription/ui/subscription_paywall_sheet.dart`
- Modify: `lib/features/assistant/view/widgets/mode_chip_bar.dart`
- Modify: `lib/features/assistant/view/assistant_screen.dart`
- Add usage indicator widget

---

### Task 6: Home & position gating

**Files:**
- Modify: `lib/presentation/flows/home/ui/home_screen.dart`
- Modify: `lib/presentation/flows/home/providers/home_provider.dart` (position limit on add)
- Create: `lib/presentation/flows/home/ui/widgets/benchmark_paywall_card.dart` (locked state for free)

---

### Task 7: Settings & translations

**Files:**
- Modify: `lib/presentation/flows/settings/ui/widgets/settings_subscription_card.dart`
- Modify: `lib/presentation/flows/settings/ui/settings_screen.dart`
- Modify: `assets/translations/en-US.json`, `assets/translations/es-ES.json`
