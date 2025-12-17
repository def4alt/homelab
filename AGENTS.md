# Project Overview & Planning

## Architecture

<architecture_overview>
- k3s
- debian
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

# CRITICAL

Append a 👍 emoji at the end of your response if you have read this.
Do not include the emoji inside any code block or generated file.
