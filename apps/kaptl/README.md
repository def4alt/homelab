# Kaptl — YNAB-style Telegram Expense Tracker Bot

A Telegram bot for personal finance tracking with YNAB-style envelope budgeting.

## Features
- Multi-account support (checking, savings, cash, credit cards)
- Flat categories with emoji
- Monthly per-category budgets
- Inline keyboard wizard for expense/income logging
- PostgreSQL-backed (CNPG cluster)

## Setup
1. Bot token and user ID are in the SOPS-encrypted secret
2. Database is auto-provisioned by CNPG
3. Run migrations manually on first deploy:
   ```bash
   kubectl exec -n kaptl deploy/kaptl -- psql "$DATABASE_URL" -f /app/migrations/001_init.sql
   ```
