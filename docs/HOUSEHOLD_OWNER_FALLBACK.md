# Household-owner fallback

Scout treats a person/household parcel owner as authoritative property evidence only. The owner is not promoted into `core.organizations`, buyer hints, generic personal-name web research, or outbound contact.

## Phase 3 production segmentation

The Phase 3 household-owner audit split current opportunities into two classes:

- Residential construction: no business target is inferred from household ownership. These candidates receive a resolver-specific `residential_household_no_business_target` deferral while remaining globally available for later project/company evidence.
- Nonresidential/existing-property sites: Scout may attempt an address-only site-organization lookup without using the household owner's name.

## Exact-address site-organization experiment

The production experiment used `collect-household-site-organization-evidence` with the following acceptance requirements:

1. search query contains the site address and locality, never the household owner's name;
2. organization/location evidence must be structured on the retrieved page;
3. the structured street address must exactly match the Scout site after bounded address normalization;
4. the retrieved page domain must belong to the named organization;
5. third-party directories and publishers are rejected;
6. accepted identity would be `operator` evidence only, with buyer projection suppressed and purchasing/ownership/management authority not implied.

The initial acceptance batch exposed two false positives from third-party publishers (GreatSchools and U.S. News). Both operator findings and temporary organizations were retracted before any buyer projection or contact-research handoff. The worker was hardened with domain ownership checks and a database trigger requiring `first_party_domain_match=true` for this resolution scope.

After hardening, every queued address cluster received at least one bounded first-pass attempt. The strict v2 resolver accepted zero operator identities. The web lane was therefore not scheduled for recurring execution. Remaining jobs were exhausted with `no_documented_site_organization` and 90-day resolver-specific deferrals.

## Current operating posture

- Household owner identity remains evidence-only.
- Residential household-owned construction is not autonomously web-researched for a business target.
- The exact-address site-organization collector remains an internal bounded capability, but there is no active cron for it.
- No operator-contact handoff migration is active; the unapplied draft was removed from the repository after the zero-yield acceptance sweep.
- Global buyer-resolution rows remain available for future authoritative project, permit, management, facility, or other organization evidence.
- No outbound contact occurs in this pipeline.

Future reactivation of the site-organization web lane should require a materially better first-party source strategy or new authoritative data, not merely looser acceptance thresholds.