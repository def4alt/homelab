# Fix home Authentik forward-auth callback routing

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with that file.

## Purpose / Big Picture

After this change, the home cluster on `perun` uses its own Authentik Traefik outpost identity and its login callback returns to the same outpost instance that started the flow. The user-visible outcome is that the first login to `photos.def4alt.com`, `home.def4alt.com`, and `pihole.def4alt.com` completes without bouncing to the Authentik dashboard or failing with `400 Bad Request`.

The root problem is not Traefik itself. It is the callback topology. The first home-cluster implementation reused the central Hetzner outpost identity from `zorya`. That made the callback URL land on `auth.def4alt.com`, where the central outpost handled the callback without the session file created by the home outpost on `perun`. Authentik therefore rejected the callback as an invalid state.

## Progress

- [x] (2026-06-09 15:25Z) Confirm the failure mode from live logs: the callback on `auth.def4alt.com` returns `400` because the central outpost sees `failed to get session`, `invalid state`, and `mismatched session ID`.
- [x] (2026-06-09 15:30Z) Record the corrective architecture in this ExecPlan.
- [x] (2026-06-09 15:38Z) Create a dedicated Authentik provider and outpost identity for the home cluster in GitOps.
- [x] (2026-06-09 15:39Z) Repoint the home outpost browser callback host to an existing home hostname that already resolves to `perun` and is covered by the shared `.def4alt.com` cookie domain.
- [x] (2026-06-09 15:41Z) Update the home outpost secret on `perun` to the generated dedicated outpost token after Authentik reconciles on `zorya`.
- [x] (2026-06-09 15:54Z) Verify that an unauthenticated request to `photos.def4alt.com` produces a callback URL on the home callback host. The live redirect now sends the browser to `https://auth.def4alt.com/application/o/authorize/...` with `redirect_uri=https://photos.def4alt.com/outpost.goauthentik.io/callback?...`.

## Surprises & Discoveries

- Observation: the local home outpost on `perun` is healthy; the failure happens later at callback time.
  Evidence: `https://photos.def4alt.com/outpost.goauthentik.io/ping` returned `204`, and the local outpost served `/outpost.goauthentik.io/auth/traefik` with `302` responses.

- Observation: the `400 Bad Request` is produced by the central managed outpost on `zorya`, not by Authentik server itself.
  Evidence: live outpost logs on `zorya` for `/outpost.goauthentik.io/callback?...code=970a55...` showed `status:400` along with `failed to get session`, `invalid state`, and `mismatched session ID`.

- Observation: the callback state itself is valid, but it names a session created on the home outpost.
  Evidence: decoding the JWT `state` showed `sid=INJR3P4QZ2OPUTHFYA3ZLINBYKU2V44VEITTUWYTUMDVEIE7KYXQ` and `redirect=https://photos.def4alt.com/`. The same session ID appeared in the `zorya` outpost warning logs as missing.

- Observation: adding a brand-new callback hostname would require DNS work that is not currently present in the repo.
  Evidence: `dig +short auth-home.def4alt.com` returned no records, while existing home hosts such as `photos.def4alt.com`, `home.def4alt.com`, and `pihole.def4alt.com` already resolve publicly.

- Observation: the local fix on `perun` was rolled back by Flux because the repo still contained the old secret and outpost definition.
  Evidence: after manually applying the corrected secret, the next live check on `perun` showed `authentik_host_browser=https://auth.def4alt.com`, token prefix `F21P5g1FKVqL`, and outpost logs for the central UUID `d193fabb-da62-4468-90c1-a0a7f361d0b3`.

- Observation: the earlier home config swapped the provider callback host with the browser-facing Authentik host.
  Evidence: with `external_host=https://auth.def4alt.com` and `authentik_host_browser=https://photos.def4alt.com`, the home outpost issued `redirect_uri=https://auth.def4alt.com/outpost.goauthentik.io/callback...`, which reproduces the wrong-cluster callback. The central managed home outpost logs also showed `Loaded application` with host `auth.def4alt.com`, confirming that `external_host` drives the callback base.

- Observation: the Authentik blueprint import did not mutate the already-created home provider and outpost objects fully in place.
  Evidence: after Flux applied the corrected repo state, the live Authentik database still reported `external_host=https://photos.def4alt.com` only after a direct ORM update, and the running outpost needed a restart before its loaded application host and redirect shape converged to the desired values.

## Decision Log

- Decision: keep the callback on an existing home hostname that already resolves to `perun`, instead of introducing a new DNS name.
  Rationale: the bug is caused by the callback landing on the wrong cluster, not by the lack of a special hostname. Reusing an existing home hostname avoids extra DNS changes and still works with Authentik's `.def4alt.com` cookie domain.
  Date/Author: 2026-06-09 / Codex

- Decision: create a separate Authentik provider and outpost identity for the home cluster instead of reusing the central outpost token.
  Rationale: the callback must be handled by the same outpost identity that initiated the flow. Sharing one managed outpost identity across independent clusters creates ambiguous callback ownership and invalidates session recovery.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

The architectural fix is live. The stable shape is: the home provider `external_host` stays on `https://photos.def4alt.com`, the outpost `authentik_host_browser` stays on `https://auth.def4alt.com`, and the home Traefik outpost on `perun` uses its own dedicated Authentik identity. The one remaining nuance is operational: Authentik's blueprint importer did not fully rewrite the existing home objects, so the live objects were corrected once through the ORM and then restarted to converge with the GitOps intent.
