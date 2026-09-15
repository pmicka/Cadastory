
# Scout municipal facilities portfolio map contract

Status: owner-approved sandbox portfolio type, September 15, 2026.

The `municipal_facilities_portfolio` sandbox type proves that the shared portfolio framework can represent a civic account whose mapped members and opportunity signals have different evidence scopes.

## Exemplar

The bounded exemplar is **Louisville Metro Government**. The map contains six civic locations taken from Louisville Metro Government's official `Metro Government Locations` directory and crosswalked by exact street address to point geometry in `fema-usa-structures-current`:

- City Hall — 601 W Jefferson Street
- MetroSafe Building — 410 S 5th Street
- Police Headquarters — 601 W Chestnut Street
- Records Management & Archives — 635 Industry Road
- Health & Wellness — 400 E Gray Street
- Judicial Center — 700 W Jefferson Street

The six-member set is intentionally a bounded proof subset, not a claim that it enumerates all Louisville Metro facilities.

## Evidence semantics

The Louisville Metro directory proves that each member is a listed government location. It does **not** by itself prove ownership, building-envelope maintenance responsibility, site access, or procurement authority. FEMA USA Structures supplies exact-address geometry only; FEMA occupancy labels must not be used as facility identity evidence.

Scout's current exterior-cleaning `cleaning_need_proxy` at 700 W Jefferson is attributed only to the Judicial Center member. The other five locations remain account-expansion targets with no site-specific cleaning need asserted by this contract.

The cleaning proxy is prospecting/inspection evidence. It is not proof of visible staining, an active solicitation, contract availability, an award, or work available.

## Rendering

All members render as flat circular civic-location markers. The Judicial Center marker is visually outlined to indicate that it alone has a linked site-specific Scout signal. The legend must make the attribution boundary explicit.

Raster rendering remains workerless and uses only the manifest-bounded tiles required by the registered 456x210 and 280x210 frames. No map may widen the global tile proxy.
