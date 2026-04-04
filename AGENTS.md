# Project Overview & Planning

## Architecture

<architecture_overview>
- k3s
- nixos
- fluxcd
</architecture_overview>

## Complex Changes

<complex_changes>
<exec_plans>
Use ExecPlans for all big planned changes, including:
- Multi-concept changes across platforms
- Significant architectural modifications
- New features with unclear requirements (e.g., where the scope, user stories, or technical approach are not yet fully defined)
- Refactoring impacting multiple systems

**Progress Documentation**: Update ExecPlan documentation with implementation progress, decisions made, and any changes to the original plan. ExecPlans should be written in the `.agent/plans/` folder, not in `docs/`.

📖 **Guide**: If complex changes are identified, propose to create an ExecPlan. [.agent/plans/](.agent/plans/)
</exec_plans>
</complex_changes>

# Code Quality & Guidelines

## Code Standards

<code_standards>
<guiding_principles>
- **Clarity**: Modular, reusable components; avoid duplication
- **Consistency**: Unified design system (colors, typography, spacing, components)
- **Simplicity**: Avoid unnecessary complexity in styling or logic
- **Performance**: Optimize for fast loading and efficient state management
</guiding_principles>

<conventions_patterns>
- Prioritize minimal, clear, and functional implementations initially, avoiding premature optimization or over-engineering.
- Prioritize simplicity and clarity in initial implementations.
- Allow for later refactorings and rewrites to improve code quality.
- Avoid over-engineering and common AI-driven verbosity or clutter.
- Emphasize maintainable, minimalistic, and iterative code evolution.
</conventions_patterns>

</code_standards>

## Code Style

<code_style>
<comments>
- Explain *why*, not *what*
- Use sparingly for complex logic, workarounds, or public APIs
- Let code be self-documenting through clear naming. However, comments are still valuable for explaining *why* something is done, especially for complex logic, workarounds, or external API interactions.
</comments>

<control_flow>
- **Always prefer early returns** over nested conditionals
- Guard clauses should fail fast and return early
- Keep happy path clear and unindented
</control_flow>
</code_style>

## Git Commit Messages (Conventional Commits)

Use Conventional Commits for all commits to keep history machine-readable and consistent:

- Format: `<type>[optional scope][!]: <description>`
- Types: `feat` (new feature), `fix` (bug fix), plus common extras like `chore`, `docs`, `refactor`, `perf`, `test`, `ci`, `build`, `style`, `revert`.
- Scope is optional and should be a short noun in parentheses, e.g. `feat(backups): ...`.
- Breaking changes must be indicated either with `!` (e.g. `feat(api)!: ...`) and/or a footer `BREAKING CHANGE: ...`.
- Optional body goes after a blank line; optional footers go after another blank line (git-trailer style, e.g. `Refs: #123`).

Examples:

- `docs: correct spelling of CHANGELOG`
- `fix(backup): scope prune to tag`
- `feat(longhorn): add recurring jobs`
- `chore!: drop support for Node 6` + `BREAKING CHANGE: ...`

## Access & GitOps

- Kubectl/flux/git may require escalated permissions; request escalation when you need to touch the cluster or `.git`.
- Prefer GitOps: commit changes and push for Flux to apply instead of manual `kubectl apply`.

## Executor Deployment Pattern

<executor_deployment>
- For the `executor` service, deploy only the application components in this repo: namespace, Flux `Kustomization`, app `Kustomization`, `Deployment`, `Service`, `Ingress`, `RBAC`, and secrets.
- Do **not** provision a dedicated PostgreSQL cluster for `executor` in `homelab` if the homelab already has a shared/existing PostgreSQL setup available.
- Follow the same pattern already used by existing apps: inject a single application secret containing a database connection URL rather than managing database bootstrap resources here.
- Prefer a secret key named `database-url` for the app-facing JDBC/connection string unless the target app explicitly requires different env var names.
- For `executor`, the Kubernetes `Deployment` should read `SPRING_DATASOURCE_URL` from that secret and should not define separate username/password env vars when a single JDBC URL is sufficient.
- Keep the control plane lightweight for homelab use: conservative CPU/memory requests and limits, no oversized warm capacity by default, and no resource reservations that compete heavily with existing services.
- Keep this deployment GitOps-first: changes belong under `apps/<name>` and `clusters/home/overlays/apps/<name>.yaml`, then Flux reconciles them.
- When asked to add `executor`, create/update the files under `apps/executor-system` and `clusters/home/overlays/apps/executor-system.yaml`, and wire the namespace through `apps/namespaces` if needed.
</executor_deployment>

# CRITICAL

Append a 👍 emoji at the end of your response if you have read this.
Do not include the emoji inside any code block or generated file.
