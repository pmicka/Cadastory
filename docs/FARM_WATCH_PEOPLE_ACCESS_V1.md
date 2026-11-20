# WMW Farm — People & access v1

## Product scope

Single-property authorization for the existing WMW Farm site. No property switcher, organizations, password management, invitation email delivery, or identity-provider replacement.

The current Google OAuth sign-in stays unchanged. The owner approves a **Google account email** and grants either **Viewer** or **Admin** access; the person's Google login becomes authorized when it is verified/linked in Supabase Auth. Email approval alone does not create an Auth account or send a message.

## Current source of truth

- `farm_watch.authorized_users`: direct user-ID grants, including the existing owner.
- `farm_watch.authorized_emails`: email grants used by Google OAuth sign-in.
- `public.farm_watch_authorize_user_v1_internal`: current server-side authorization check.
- `public.farm_watch_get_account_role_v1_internal`: current effective role. An **active direct grant takes priority** over an email grant.

The new API deliberately does not replace or independently shadow these existing tables.

## New API

`public.farm_watch_manage_access_v1(p_action text default 'list', p_email text default null, p_role text default null, p_expected_revision integer default null)`

Authenticated owner only, checked on **every call** using `auth.uid()`, Auth user existence, the current allowlist, effective owner role, and the active WMW Farm record. No direct browser table grants.

- `list`: returns `{source:'farm-access-v1',can_manage:true,revision,members,activity}`. A combined directory shows email grants plus unpaired direct grants, roles, effective roles, whether an approved email is associated with a confirmed Google identity, whether that Auth account has signed in, grant status and up to 20 audit events. These flags must **not** be presented as live online presence.
- `set`: email and role (`viewer` or `admin`) plus the latest revision. Creates an email approval, changes a role, or restores previously revoked access. No owner-role assignment through this API.
- `revoke`: email and latest revision. Revokes the email grant **and any corresponding direct nonowner grant** in the same transaction. A user's existing token is not necessarily invalidated immediately by Supabase Auth; current Farm Watch authorization checks deny subsequent privileged requests.
- Concurrent changes are serialized by `farm_watch.access_control_state_v1`. Revision mismatches raise `PT409` and require a fresh directory read; never retry stale writes automatically.
- The current owner and any direct/email owner grants are immutable through this API. Administrative authorization cannot be delegated to an Admin account.

All successful writes append to `farm_watch.access_audit_v1` (actor, normalized target email, action, previous/new grant state, timestamp), which is private and has forced RLS.

## Deployment

1. Review and merge Cadastory backend PR #350 only after isolated PostGIS authorization checks pass.
2. Apply the committed `20261120233000_farm_watch_people_access_v1.sql` migration to the connected Supabase project.
3. Validate that the effective owner can list, that Admin/Viewer cannot, and that **existing production grant counts remain unchanged**. Do not create, revoke, or change a real account as a smoke test.
4. Review and merge notebook frontend PR #353 only after its Node and mobile browser checks pass.
5. Synchronize `pmicka/notebook/main` to the DreamHost site checkout and verify `admin.js?v=20261120-people1` is live. No separate Edge Function deployment is necessary.

Rollback is a code/migration process, not a change to the current grants. Existing direct/email authorization continues to work if the admin UI is rolled back.

## Boundaries

- Owner-only authorization is enforced **in SQL**, not inferred from a client-side label or email address.
- This feature does not send invitation emails, create Auth users, delete Auth accounts or manage passwords.
- Direct nonowner grants without a retrievable email are visible but read-only; email-identifiable direct nonowner grants can be updated through the same email workflow.
- The directory exposes account and audit information only to the authenticated owner. It does not expose tokens, identity-provider secrets or raw account tables.
- Existing-photo management and viewers' dashboard access continue to use their own authorization APIs.
- Viewer is the existing **guided access** role; some existing modules permit self-scoped operations (such as personally created map pins). This unit does not silently change those permissions into a global read-only policy.
