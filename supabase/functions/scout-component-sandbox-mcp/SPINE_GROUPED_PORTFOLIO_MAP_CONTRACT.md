# Scout grouped spine portfolio map contract

`spine_grouped_portfolio_map_v1` is the bounded Stage-2 adapter for multi-member opportunities that already share a resolved organization relationship in `scout.opportunity_search_spine`.

The adapter is point-only. Membership means current spine evidence resolved the member to the same buyer organization under the type-specific relationship semantics. It does **not** create parcels, ownership polygons, rights-of-way, track topology, service radii, access envelopes, project-control areas, guy-wire footprints, inspection perimeters, or operating boundaries.

Members are deduplicated by `operational_target_key`; the selected row is the highest-confidence, newest evidence row. The response fails closed unless there are at least two mapped members, every selected member has Point geometry, and the group resolves to exactly one buyer organization ID.

Bridge-agency membership does not narrow an owner-or-agency role to legal ownership. Railroad crossing points are not connected into inferred track geometry. Permit-named contractor membership does not prove prime-contract authority or field progress. FCC owner/operator records do not establish service radius, inspection need, access, or work availability.

Raster rendering uses the common bounded tile allowlist and the same workerless 2D canvas/image path as the established portfolio maps.
