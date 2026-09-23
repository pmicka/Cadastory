# Farm Watch Deer Science Evidence Ledger

Status: current as of 2026-09-22  
Target species: white-tailed deer (`Odocoileus virginianus`)  
Primary transfer geography: central Kentucky / lower Ohio Valley  
Validation property: `validation-property-01`

## Purpose

Implementation sequencing and product contracts are defined in `docs/FARM_WATCH_DEER_SCIENCE_IMPLEMENTATION_PLAN.md`.



This document is the durable scientific-transfer ledger for deer-specific Farm Watch modeling.

Farm Watch should not invent generic deer rules and then ask a single property to rediscover established ecology. The intended sequence is:

1. preserve neutral physical/environmental evidence;
2. identify published white-tailed-deer relationships that are relevant to a named biological state;
3. encode only the relationship form that the literature actually supports;
4. bind that relationship to explicit Farm Watch inputs, provenance, season, sex/age/activity-state gates, and transfer limitations;
5. use local observations for validation, calibration, or rejection of transfer where necessary.

This ledger is not a license to copy coefficients across populations. A relationship may be scientifically transferable while its numeric coefficient is not.

## Required evidence posture

Every future deer-specific model term MUST cite one or more ledger entries or add a new entry first.

Each term MUST preserve:

- species and study population;
- sex/age/reproductive state where known;
- season and diel period where relevant;
- movement state where relevant (home-range use, dispersal, migration, bedding/resting, feeding, rut, etc.);
- response variable actually studied;
- predictor(s) and interaction structure actually studied;
- direction and nonlinearity/thresholds only when reported;
- explicit null findings;
- geographic/ecological transfer limits;
- Farm Watch input mapping;
- whether only the relationship form or an actual coefficient is reusable.

A published association does not become a universal deer preference. A study of dispersing juvenile males does not justify a resident-adult movement rule. A study of winter cover does not justify a summer cover rule. A study showing road selection in one boreal industrial landscape does not justify generic road attraction.

## Transfer vocabulary

- **form-transfer-ready** — the published direction/interaction/conditional structure is appropriate to encode as a candidate deer-model term when the required Farm Watch inputs exist. Numeric coefficients are not automatically transferable.
- **mechanism-support** — supports a biological mechanism or state gate, but the experimental geography/design is too different for direct field-model coefficient transfer.
- **context-conditional** — useful evidence, but the direction or scale depends strongly on landscape, season, sex/age, movement state, or resource configuration. Must not be encoded as a universal rule.
- **negative-constraint** — evidence that blocks or strongly cautions against an unsupported generic rule.
- **extreme-event-only** — relationship is specific to an extreme climatic event and must not be used for ordinary weather.
- **coefficient-transfer-not-supported** — default unless a future review establishes close population/design comparability and the original coefficient/model can be reconstructed faithfully.

## Review scope and source acceptance

This v1 review used fresh external literature discovery rather than attempting to reconstruct the deleted chat's source list. Priority was given to peer-reviewed primary studies with white-tailed-deer telemetry, resource selection, experimental manipulation, direct field observation, or long-term survey designs. Systematic reviews are retained as synthesis anchors but do not supply population-specific coefficients.

Search themes included:

- thermal environment, operative temperature, solar exposure, canopy and microclimate;
- routine weather, extreme weather, diel activity and reproductive timing;
- mast, forage, crops, crop phenology and harvest;
- hunting pressure, hunter activity, roads/trails and anthropogenic risk;
- topography, landscape context, dispersal and movement state;
- vegetation structure, concealment and bedsite selection;
- water, precipitation, drought and hydrologic context;
- sex, age, reproductive state and scale dependence.

Evidence was rejected or downgraded when it was hunting-media advice, anecdote, a different cervid species without a clear transferable mechanism, a mismatched movement state, or a landscape/population context that could reverse the reported direction.

The initial targeted search did not surface a directly transferable central-Kentucky thermal-selection coefficient or an exact Kentucky rut-movement coefficient. A deeper breeding-phenology review did surface authoritative Kentucky population timing: University of Kentucky Extension describes breeding from October through January with peak activity usually in mid-November, and Kentucky Fish and Wildlife independently describes its mid-November modern gun season as designed to coincide with peak fall breeding. Those sources support a statewide qualitative reproductive-timing gate, not an individual reproductive state or a numeric movement coefficient. Exact annual physiographic-region conception dates remain a source-capture priority rather than a hard-coded rule.

## Current Farm Watch implementation substrate

### Machine-readable relationship registry

Batch 9 is implemented as `deer-relationship-registry-v1` in
`supabase/functions/_shared/farm-watch-deer-relationship-registry.ts`.

The registry is the machine transfer contract for this ledger. CI requires every current `FW-Dxx`
entry to have registry coverage and rejects unsupported numeric coefficients, missing required
biological-state gates, blocked universal assumptions, stale/unavailable required inputs, and
input-product scale mismatches. A ledger relationship remains scientifically normative here; the
registry makes that relationship testable rather than replacing the ledger.

The FW-D04 concealment relationships currently require the planned
`low-height-concealment-context` measurement-alignment product. The completed general
`horizontal-visibility-context-v1` remains a neutral physical viewshed and is not silently
promoted to the sub-meter concealment variable used by the cited bedsite study.

Current neutral products that may feed future science-backed deer terms:

- barrier-aware landscape domain: property + local 500 m + landscape 1.5 km + broad 3 km;
- landscape physical context: elevation, slope, canopy, physical rings;
- terrain form / reference permeability: local 10 m terrain-form candidates and 30 m slope-only reference cost;
- spatial edge / patch context: canopy patches/transitions, mapped-field edge geometry, 5 m neutral structural transitions;
- Phase 3 LiDAR physical structure and local 500 m landscape structure;
- leaf-off woody-pattern context;
- resource-edge context: mapped fields, field edges, CDL composition and nearest field;
- Seasonal State v1: precipitation, drought, stream discharge proxy, root-zone soil-moisture proxy, state fieldwork, regional crop progress, state crop stage, mapped crop vintage;
- property-grade NOAA HRRR meteorological forcing v1: current modeled temperature, dew point/RH, true wind, shortwave, longwave, cloud and precipitation-rate forcing with exact grid/model provenance;
- historical environment context: Daymet temperature/precipitation on historical context dates;
- roads/trails/buildings and other access geometry already available elsewhere in Farm Watch/Scout.

Important current gaps include:

- a validated operative-temperature or animal heat-balance formulation, if later science requires one;
- source-controlled exact Kentucky physiographic-region breeding-date series beyond the statewide qualitative timing gate;
- current field-level crop phenology/harvest state;
- mast abundance/species/vintage;
- measured localized hunting pressure or human-use intensity;
- calibrated concealment/visibility metric from the existing neutral 3-D structure;
- parcel-scale usable water persistence / ephemeral water state.

The generic Scout weather snapshot table remains out of scope for deer thermal work; Farm Watch now has its own property-targeted HRRR forcing contract.

---

# Evidence ledger

## FW-D01 — Summer thermal environment is a time-of-day × vegetation × forage problem

**Citation:** Wiemers, D.W., Fulbright, T.E., Wester, D.B., Ortega-S., J.A., Rasmussen, G.A., Hewitt, D.G., and Hellickson, M.W. 2014. *Role of Thermal Environment in Habitat Selection by Male White-Tailed Deer during Summer in Texas, USA.* Wildlife Biology 20:47–56. DOI: 10.2981/wlb.13029.

**Population/design:** Adult male white-tailed deer, south Texas, GPS collars, June–July 2008–2009; resource-selection models across morning, midday, evening, and night.

**Response:** Within-habitat resource selection.

**Predictors:** Forage index (standing crop, crude protein, ADF), vegetation height, operative temperature, concealment cover, activity period; midday comparison also included woody plant canopy cover.

**Supported relationship:** The best overall model included forage, vegetation height, operative temperature, concealment, and interactions with activity period. Deer selected taller vegetation in morning and midday, shorter vegetation in evening/night, and forage quality mattered in all periods. At midday, operative temperature + vegetation height + woody canopy predicted use better than any of those three alone. Deer behavior was consistent with seeking cooler midday environments while still using higher-quality forage.

**Null/negative finding:** Greater concealment cover was not selected during any activity period in this study.

**Transfer disposition:** **form-transfer-ready; coefficient-transfer-not-supported.**

**Farm Watch mapping:** study-aligned operative-temperature or calibrated thermal input + vegetation height + woody canopy + forage state + study activity-period translation.

**Measurement-fidelity note:** Current `thermal-exposure-context-v1` is related physical context but explicitly does not calculate operative temperature. The production-validated `study-aligned-vegetation-height-context-v2` is accepted as a `derived_equivalent` representation of the study vegetation-height variable, with negative-clamped cells excluded from scientific height use. Current field-phenology/browse products remain non-equivalent to the study forage index; woody-canopy and activity-period fidelity also remain unresolved.

**Boundary:** Do not convert to “shade always attracts deer,” “south slopes are bad in summer,” or “concealment is irrelevant.” This was summer, adult males, subtropical Texas, and within-habitat selection.

---

## FW-D02 — Deer exploit spatial and temporal thermal heterogeneity

**Citation:** Wolff, C.L., Demarais, S., Brooks, C.P., and Barton, B.T. 2020. *Behavioral plasticity mitigates the effect of warming on white-tailed deer.* Ecology and Evolution 10:2579–2587. DOI: 10.1002/ece3.6087.

**Population/design:** Mississippi State University deer unit; wild-captured Mississippi deer and captive-born offspring. Replicated shaded/unshaded feeding experiments, April–September 2017. Group population was approximately 3:1 female:male; individual trials used females.

**Response:** Feeding timing, feeder use, food consumption.

**Supported relationship:** Deer shifted feeding in both space and time. Shaded feeders received disproportionate daytime use; unshaded use shifted toward cooler crepuscular periods. Group consumption was about 23% lower at unshaded feeders and individual consumption about 17% lower. The feeder treatments differed by roughly 1.4°C on average.

**Important nuance:** Hourly solar radiation itself was not a significant standalone explanation of feeder visitation in the reported models; the shade treatment better captured the usable microclimate effect.

**Transfer disposition:** **mechanism-support; coefficient-transfer-not-supported.**

**Farm Watch mapping:** supports modeling realized thermal refuge/exposure rather than raw solar radiation alone; future thermal layer should combine radiation/topography/canopy with meteorological forcing and time of day.

**Boundary:** Enclosure/feeder experiment. Do not copy 17–23% consumption effects to free-ranging Kentucky deer.

---

## FW-D03 — Winter conifer use is driven more by snow shelter than simple cold-air avoidance

**Citation:** DelGiudice, G.D., Fieberg, J., and Sampson, B.A. 2013. *A long-term assessment of the variability in winter use of dense conifer cover by female white-tailed deer.* PLOS ONE 8:e65368. DOI: 10.1371/journal.pone.0065368.

**Population/design:** Female deer in Minnesota over 12 winters; VHF and GPS monitoring across sites with differing dense-conifer availability.

**Response:** Use of dense conifer vs more open vegetation in winter.

**Supported relationship:** Dense-cover use increased with increasing snow depth, most strongly where dense cover was more available. At the lowest minimum temperatures, daytime probability of using open vegetation increased to roughly 55–>80%, consistent with benefits of solar exposure.

**Interpretation from authors:** Dense conifer cover functioned more strongly as snow shelter/energy-conservation cover than as generic “thermal cover.”

**Transfer disposition:** **context-conditional; coefficient-transfer-not-supported.**

**Farm Watch mapping:** snow-depth/winter-severity state + dense-conifer cover availability + solar exposure + time of day.

**Measurement-fidelity note:** Generic canopy density or edge/patch structure must not substitute for the study's dense-conifer cover class.

**Boundary:** Northern severe-winter system. Do not use this to create a generic “dense conifer = winter bedding” rule in central Kentucky. It directly warns against using air temperature without solar exposure and snow state.

---

## FW-D04 — Hot-season bedsites can reflect thermal cover; fawning females can emphasize low concealment cover

**Citation:** Gallina, S., Bello, J., Contreras-Verteramo, C., and Delfín-Alfonso, C. 2010. *Daytime bedsite selection by the Texan white-tailed deer in xerophyllous brushland, north-eastern Mexico.* Journal of Arid Environments 74:373–377. DOI: 10.1016/j.jaridenv.2009.09.032.

**Population/design:** Texan white-tailed deer in hot (>40°C), dry xerophyllous brushland; 50 occupied bedsites vs 50 random sites.

**Response:** Daytime bedsite selection.

**Supported relationship:** Deer bedsites had greater thermal/concealment structure than random sites. Males selected greater total cover, shrub volume, and shrub height. During fawning, females selected greater concealment at 0–50 and 50–100 cm.

**Transfer disposition:** **mechanism-support/context-conditional; coefficient-transfer-not-supported.**

**Farm Watch mapping:** planned study-aligned `low-height-concealment-context` reproducing or calibrated to the 2 m cover-pole protocol at 15 m with four 50 cm strata and directionality; thermal-cover context; sex/reproductive-state gate.

**Measurement-fidelity note:** `horizontal-visibility-context-v1` is a generalized physical viewshed and is not the Gallina concealment measurement.

**Boundary:** Semiarid Mexico and bedsite-specific inference. Do not label all dense low vegetation as bedding or assume female/male effects outside the documented state.

---

## FW-D05 — Routine short-term weather is a weak universal movement predictor; moon phase is a negative constraint

**Citation:** Webb, S.L., Gee, K.L., Strickland, B.K., Demarais, S., and DeYoung, R.W. 2010. *Measuring Fine-Scale White-Tailed Deer Movements and Environmental Influences Using GPS Collars.* International Journal of Ecology 2010:459610. DOI: 10.1155/2010/459610.

**Population/design:** Oklahoma; 17 females + 15 males; GPS fixes attempted every 15 min; seven years and three seasons.

**Response:** Daily, diurnal, nocturnal and fine-scale movement.

**Supported relationship:** Movements were primarily crepuscular. Male daily movement was about 20% greater during rut than post-rut. Female daily movement was greatest post-parturition, then parturition, then pre-parturition.

**Negative findings:** Moon phase had no effect on daily, nocturnal, or diurnal movement. Fine-scale short-term weather effects were inconsistent within seasons; authors concluded hourly/daily weather had minimal movement impact at this southern latitude.

**Transfer disposition:** **negative-constraint + form-transfer-ready for reproductive/diel state; coefficient-transfer-not-supported.**

**Farm Watch mapping:** time of day, photoperiod, rut/reproductive state, weather only as conditional evidence rather than global movement multiplier.

**Blocked rule:** No generic moon-phase movement term. No generic “front/barometer/wind = more movement” term absent stronger state-specific evidence.

---

## FW-D06 — Rut movement depends on age and date; firearm opening weekend need not increase movement

**Citation:** Hunsaker, M.A., Gilbertson, M.L.J., Storm, D.J., and Turner, W.C. 2025. *The Breeding Season and Movement Ecology of Male White-Tailed Deer in Southwest Wisconsin.* Ecology and Evolution 15:e71589. DOI: 10.1002/ece3.71589.

**Population/design:** Southwest Wisconsin; 188 collared males; 15 October–1 December, 2017–2020.

**Response:** Hourly movement rate, daily movement variation, daily range, breeding-season changepoints.

**Supported relationship:** Two-year-old males had higher hourly movement rates and larger daily ranges than younger and older groups. Males ≥3 years showed the greatest variance in daily movement, consistent with alternating high-movement mate searching and low-movement mate tending. Peak breeding-season movement changepoint was 23 October–12 November in this population.

**Null finding:** Firearm opening weekend had no significant effect on movement rates.

**Transfer disposition:** **form-transfer-ready for age × reproductive-state gating; date coefficient/period not directly transferable to Kentucky.**

**Farm Watch mapping:** locally appropriate breeding phenology + explicit male age class with enough resolution to distinguish yearlings, 2-year-olds, and males ≥3 years.

**Measurement-fidelity note:** The current Farm Watch `juvenile | yearling | adult` vocabulary collapses 2-year-old and ≥3-year-old males into `adult`; the age-dependent movement relationship must therefore abstain until age resolution is improved.

**Boundary:** Do not hard-code Wisconsin rut dates for Kentucky.

---

## FW-D07 — Acorn mast can restructure space use and dominate foraging during mast fall

**Citation:** McShea, W.J., and Schwede, G. 1993. *Variable Acorn Crops: Responses of White-Tailed Deer and Other Mast Consumers.* Journal of Mammalogy 74:999–1006. DOI: 10.2307/1382439.

**Population/design:** Front Royal, Virginia; 10 radiomarked female deer; 1986–1989; mature deciduous forest.

**Response:** Home-range adjustment and foraging behavior relative to acorn mast.

**Supported relationship:** Deer enlarged/shifted home ranges to incorporate acorn-producing areas during mast fall. Acorns accounted for about 50% of foraging time during peak mast fall; average consumption was ~0.75 acorns/min while searching. Number consumed tracked mast fall, but deer continued searching after peak fall.

**Transfer disposition:** **form-transfer-ready; coefficient-transfer-not-supported.**

**Farm Watch mapping:** oak/mast-producing species distribution + annual mast state (both currently missing), season, distance/availability.

**Critical gap:** CDL/canopy/leaf-off structure cannot substitute for annual mast availability.

---

## FW-D08 — Corn phenology and harvest can move female home-range centers and change range size

**Citation:** Vercauteren, K.C., and Hygnstrom, S.E. 1998. *Effects of Agricultural Activities and Hunting on Home Ranges of Female White-Tailed Deer.* Journal of Wildlife Management 62:280–285. DOI: 10.2307/3802289.

**Population/design:** DeSoto National Wildlife Refuge, Nebraska/Iowa; 30 radiomarked females, 1991–1993.

**Response:** Home-range center and size before/after corn phenology, harvest, and hunting.

**Supported relationship:** At corn tasseling/silking, home-range centers shifted on average 174 m toward cornfields. After harvest, centers shifted on average 157 m away from crop fields toward permanent cover. Mean home-range size increased 32% after harvest.

**Hunting result:** Intensive hunting displaced many does temporarily, but the mean range before vs after hunt did not differ; most displaced deer returned rapidly.

**Transfer disposition:** **form-transfer-ready for crop-phenology/harvest state; coefficient-transfer-not-supported.**

**Farm Watch mapping:** mapped field identity + actual current crop + field-level crop stage/harvest state + permanent-cover geometry.

**Critical gap:** Current Seasonal State has regional crop-stage proxies and stale 2025 CDL for this property; that is insufficient to assert current tasseling, standing corn, or harvest.

---

## FW-D09 — Winter activity responds to the configuration of agricultural food and woody browse, not one food variable alone

**Citation:** Delisle, Z.J., Sample, R.D., Caudell, J.N., and Swihart, R.K. 2024. *Deer activity levels and patterns vary along gradients of food availability and anthropogenic development.* Scientific Reports 14:10223. DOI: 10.1038/s41598-024-60079-6.

**Population/design:** Midwest USA; camera traps at 1,018 locations across 48 landscapes (10.36 km² each) in three regions; winter focus.

**Response:** Fraction of day active and distribution of activity over the diel cycle.

**Supported relationship:** Overall activity level increased with building density but not with food availability alone. Diel activity pattern responded to an interaction between woody twig density and amount of agriculture. Where agriculture was limited, increasing twig density corresponded to less night/evening activity; where agriculture was plentiful, increasing twig density corresponded to more pronounced night/evening activity.

**Transfer disposition:** **form-transfer-ready/context-conditional; coefficient-transfer-not-supported.**

**Farm Watch mapping:** agriculture availability at landscape scale + future browse/twig resource proxy + buildings/development + diel period.

**Boundary:** Do not create independent “more agriculture = more activity” or “more browse = more activity” weights.

---

## FW-D10 — Hunting risk is localized and time-dependent, not a permanent distance-to-stand penalty

**Citation:** Sullivan, J.D., Ditchkoff, S.S., Collier, B.A., Ruth, C.R., and Raglin, J.B. 2018. *Recognizing the danger zone: response of female white-tailed deer to discrete hunting events.* Wildlife Biology 2018:wlb.00455. DOI: 10.2981/wlb.00455.

**Population/design:** 38 female deer, GPS collars, August–December 2013–2015; localized hunting stands and known hunt events.

**Response:** Use of feeders, food plots, and vulnerability zones around stands by diel period and recent localized risk.

**Supported relationship:** Following a stand being hunted, use around that stand decreased during midday and increased at night. No detectable change occurred during crepuscular periods after the discrete hunt event. Responses were clearer when risk history was localized rather than represented as generic hunting-season exposure.

**Transfer disposition:** **form-transfer-ready if actual pressure events exist; coefficient-transfer-not-supported.**

**Farm Watch mapping:** dated hunt events tied to specific stands + stand-specific visibility/vulnerability geometry + hunter-occupancy-aware diel periods; food/resource features remain separate context.

**Measurement-fidelity note:** Sullivan et al. mapped each stand's vulnerability zone by field visibility/rangefinding rather than using a uniform distance buffer. A future generalized viewshed may help derive this geometry, but it requires calibration before being treated as study-equivalent.

**Blocked rule:** Distance to a road, trail, stand, or property boundary alone is not hunting pressure.

---

## FW-D11 — Adult males can temporally avoid hunter-selected space while retaining nocturnal food use

**Citation:** Henderson, C.B., Demarais, S., Strickland, B.K., McKinley, W.T., and Street, G.M. 2023. *Temporal effects of relative hunter activity on adult male white-tailed deer habitat use.* Wildlife Research 51:WR22145. DOI: 10.1071/WR22145.

**Population/design:** Mississippi; 42 adult males; GPS collars during 2017–2018 and 2018–2019 firearm seasons.

**Response:** Fine-scale habitat selection relative to daily hunter activity.

**Supported relationship:** Landscape characteristics most selected by hunters were least selected by deer during daytime. Some food plots were selected as much as five times more often at night, when hunting risk was absent, than during daytime.

**Transfer disposition:** **form-transfer-ready with measured pressure; coefficient-transfer-not-supported.**

**Farm Watch mapping:** hunter-use intensity/time + food-resource geometry + diel period.

**Boundary:** Do not copy “5×” as a Kentucky multiplier; it demonstrates a strong risk × time × food interaction.

---

## FW-D12 — Sex changes the risk–food tradeoff

**Citation:** Stewart, D.G., Gulsby, W.D., Ditchkoff, S.S., and Collier, B.A. 2022. *Spatiotemporal patterns of male and female white-tailed deer on a hunted landscape.* Ecology and Evolution 12:e9277. DOI: 10.1002/ece3.9277.

**Population/design:** South Carolina; 111 adults (54 males, 57 females), 2009–2018; 30-min GPS; hunters primary adult mortality source.

**Response:** Sex- and time-specific cover/resource selection.

**Supported relationship:** Both sexes generally avoided frequently hunted/risky areas during daytime. Females were more willing than males to use risky daytime areas containing abundant food, consistent with a sex-specific nutritional-risk tradeoff.

**Transfer disposition:** **form-transfer-ready/context-conditional; coefficient-transfer-not-supported.**

**Farm Watch mapping:** sex + food resource state + measured hunting pressure + diel period.

**Boundary:** A model that does not know sex should not silently apply the male or female relationship.

---

## FW-D13 — Low hunting pressure can produce little biologically meaningful displacement

**Citation:** Rosenberger, J.P. et al. 2024. *Female Deer Movements Relative to Firearms Hunting in Northern Georgia, USA.* Animals 14:1212. DOI: 10.3390/ani14081212.

**Population/design:** Northern Georgia; 20 females; seven firearms hunts across two wildlife management areas, 2018–2019 and 2019–2020; 30-min GPS.

**Response:** 90%/50% utilization distributions and step lengths before/during/after hunts.

**Finding:** Under the low hunting pressure of this study, authors found no biologically significant changes in female movement.

**Transfer disposition:** **negative-constraint/context-conditional.**

**Farm Watch implication:** “Hunting season open” is not sufficient evidence of a displacement effect. The null result is conditional on a documented low-pressure hunting context, so pressure intensity/localization must be represented before this negative constraint can fire.

---

## FW-D14 — Terrain preference is movement-state and landscape-context dependent

**Citation:** Stephens, R.B., Millspaugh, J.J., McRoberts, J.T., Heit, D.R., Wiskirchen, K.H., Sumners, J.A., Isabelle, J.L., and Moll, R.J. 2024. *Scale-dependent habitat selection is shaped by landscape context in dispersing white-tailed deer.* Landscape Ecology 39:84. DOI: 10.1007/s10980-024-01879-z.

**Population/design:** Juvenile males in two Missouri regions; step-selection functions at multiple scales before, during, and after dispersal. One region was fragmented/low-forest rolling hills; the other more forested and topographically variable.

**Response:** Habitat/topographic selection during movement.

**Supported relationship:** In the rolling-hills region deer selected valleys and avoided roads, especially during dispersal. In the more topographically variable forested region, deer showed no road response and selected ridgelines during dispersal. Forest-selection scale also differed with forest availability/configuration.

**Transfer disposition:** **context-conditional + negative-constraint.**

**Farm Watch mapping:** terrain form, forest/canopy context, roads, movement state, multiscale landscape context.

**Blocked rule:** No universal “ridges are travel corridors,” “draws are travel corridors,” or fixed ridge/valley bonus. Terrain must interact with landscape context and movement state.

---

## FW-D15 — Agriculture affects whether juvenile males disperse, but dispersal paths can avoid agriculture and follow riparian features

**Citation:** Gilbertson, M.L.J. et al. 2022. *Agricultural land use shapes dispersal in white-tailed deer (Odocoileus virginianus).* Movement Ecology 10:43. DOI: 10.1186/s40462-022-00342-5.

**Population/design:** Wisconsin; GPS data for 590 juvenile/yearling/adult deer.

**Response:** Dispersal probability, distance, and step/path selection.

**Supported relationship:** Dispersal was concentrated in juvenile males; 64.2% dispersed. Spring juvenile-male dispersal probability increased with agriculture in the natal range. Greater agricultural land in potential paths was associated with longer dispersal distances, but during actual dispersal deer tended to avoid agriculture and select areas near rivers/streams.

**Transfer disposition:** **form-transfer-ready for juvenile-male dispersal only; coefficient-transfer-not-supported.**

**Farm Watch mapping:** represent three separate relationships: (1) spring juvenile-male dispersal probability versus natal-range agriculture, (2) dispersal distance versus season and agriculture in potential paths, and (3) dispersal path selection versus agricultural land use and proximity to mapped rivers/streams.

**Measurement-fidelity note:** The path-selection result is about riparian/hydrography geometry, not current water presence or water visitation. Crop phenology is also not the study agriculture variable; agricultural land-use geometry is.

**Boundary:** Do not apply riparian selection from a dispersal study as a generic resident-deer water-use rule.

---

## FW-D16 — Broad cover and fine-scale food can operate at different spatial scales

**Citation:** Nagy-Reis, M.B., Lewis, M.A., Jensen, W.F., and Boyce, M.S. 2019. *Conservation Reserve Program is a key element for managing white-tailed deer populations at multiple spatial scales.* Journal of Environmental Management 248:109299. DOI: 10.1016/j.jenvman.2019.109299.

**Population/design:** North Dakota; 10 years of winter aerial surveys; landscape features and winter severity evaluated at ~1 km², 9 km², and hunting-unit scales.

**Response:** Deer occurrence and abundance.

**Supported relationship:** Forest, wetland, and CRP lands were major predictors across scales. Escape-cover features dominated at broader/home-range scales, while finer-scale selection also reflected food, especially residual winter cropland.

**Transfer disposition:** **form-transfer-ready for multiscale architecture; coefficient-transfer-not-supported.**

**Farm Watch mapping:** preserve the published ~1 km², 9 km², and hunting-unit scale design; represent forest, wetland, and CRP cover separately from fine-scale residual winter cropland.

**Measurement-fidelity note:** Existing 500 m / 1.5 km / 3 km generic structure products are useful context but are not measurement-equivalent to the study's scale design or cover classes.

**Boundary:** Population occurrence/abundance is not identical to within-property movement.

---

## FW-D17 — Human footprint effects are cumulative and seasonal; linear features are not universally avoided

**Citation:** Darlington, S., Ladle, A., Burton, A.C., Volpe, J.P., and Fisher, J.T. 2022. *Cumulative effects of human footprint, natural features and predation risk best predict seasonal resource selection by white-tailed deer.* Scientific Reports 12:1072. DOI: 10.1038/s41598-022-05018-z.

**Population/design:** Range-expanding boreal white-tailed deer in western Canadian oil sands; 38 captured/collared females, 36 retained for analysis; three years of GPS telemetry, camera-derived predator occurrence, seasonal second-order resource-selection models.

**Response:** Seasonal habitat selection.

**Supported relationship:** Models combining polygonal industrial features, linear features, intact deciduous forest, and wolf occurrence performed best across seasons. Deer strongly selected some roads/trails/linear features in this industrial boreal landscape, likely because these features also carried forage opportunity.

**Transfer disposition:** **context-conditional/negative-constraint.**

**Farm Watch mapping:** female biological state + explicit polygonal/linear human-footprint classes + intact deciduous/natural-habitat context + season + predator occurrence/risk context.

**Measurement-fidelity note:** Omitting the study's camera-derived wolf-occurrence component changes the cumulative-effects model; a human-footprint-only module is not study-aligned.

**Blocked rule:** Roads/trails cannot receive a universal deer avoidance penalty. Their effect can reverse with resource configuration and landscape context.

---

## FW-D18 — Extreme storms can trigger emergency topographic/refuge behavior

**Citation:** Abernathy, H.N., Crawford, D.A., Garrison, E.P., Chandler, R.B., Conner, M.L., Miller, K.V., and Cherry, M.J. 2019. *Deer movement and resource selection during Hurricane Irma: implications for extreme climatic events and wildlife.* Proceedings of the Royal Society B 286:20192230. DOI: 10.1098/rspb.2019.2230.

**Population/design:** Southwestern Florida; 59 deer with functioning GPS collars during the pre-Irma wet season (19 males, 40 females); Hurricane Irma event.

**Response:** Movement, home-range departure, and resource selection during the hurricane.

**Supported relationship:** During the hurricane, deer increased use/selection of higher elevation and forested refuge types and avoided marsh/shrub habitats; most left normal home ranges and movement rates increased on the storm day.

**Transfer disposition:** **extreme-event-only; coefficient-transfer-not-supported.**

**Farm Watch mapping:** explicit extreme-event state + relative elevation + forest/habitat type + flood/wetland context.

**Measurement-fidelity note:** The Irma response combined higher elevation with increased selection of pine/hardwood refuge types and avoidance of marsh/shrub habitat; elevation alone is insufficient.

**Boundary:** Must never become an ordinary rain/wind movement term.

---

## FW-D19 — Water visitation in semiarid Texas tracked recent rainfall more than heat alone

**Citation:** Webb, S.L., Zabransky, C.J., Lyons, R.S., and Hewitt, D.G. 2006. *Water quality and summer use of sources of water in Texas.* Southwestern Naturalist 51:368–375. DOI: 10.1894/0038-4909(2006)51[368:WQASUO]2.0.CO;2.

**Population/design:** South Texas summer; wildlife visitation to stock ponds/troughs plus water quality.

**Response:** Water-source visitation frequency.

**Supported relationship:** Wildlife watering frequency was generally negatively related to recent rainfall; high-temperature terms were not the best predictor for any individual species in the reported comparison.

**Transfer disposition:** **mechanism-support/context-only for central Kentucky.**

**Farm Watch mapping:** recent precipitation + actually available water source state; drought may remain context. Current stream-gauge discharge, mapped hydrography, or persistence classification alone is not enough.

**Measurement-fidelity note:** The study response was visitation to known stock ponds/troughs. A future water relationship must require current usable-source presence rather than accepting a generic `surface-water-state` product solely because it is available.

**Boundary:** Arid/semiarid artificial-water context. Do not infer that central Kentucky deer select nearest water whenever precipitation declines.

---

## FW-D20 — Systematic climate synthesis supports conditional, locally mediated deer responses

**Citation:** Felton, A.M., Wam, H.K., Borowski, Z., Granhus, A., Juvany, L., Matala, J., Melin, M., Wallgren, M., and Mårell, A. 2024. *Climate change and deer in boreal and temperate regions: From physiology to population dynamics and species distributions.* Global Change Biology 30:e17505. DOI: 10.1111/gcb.17505.

**Design:** Systematic review of 218 peer-reviewed papers published 2000–2022 across 10 deer species in boreal and temperate Northern Hemisphere forests, including white-tailed deer.

**Synthesis:** Temperature, rainfall, snow, compound climate measures, and extreme events can affect deer physiology, spatial use, and population dynamics. The review documents behavioral plasticity, including shifts in habitat use and daily activity, and emphasizes that local variables such as population density, predation, and regional climate mediate outcomes. Warmer winters and hotter/drier summers can produce opposing effects.

**Transfer disposition:** **synthesis-anchor / mechanism-support; no coefficient transfer.**

**Farm Watch implication:** Reinforces the modular state-conditioned architecture and the need to separate thermal, precipitation/drought, snow, and extreme-event states rather than create a single weather score.

**Boundary:** Multi-species review. It supports architecture and mechanism prioritization, not a white-tailed-deer coefficient or a Kentucky-specific effect direction.

---

## FW-D21 — Kentucky breeding phenology supports a statewide qualitative timing gate, not an individual rut state

**Sources:** University of Kentucky Cooperative Extension / Forestry and Natural Resources, *White-tailed Deer* (Kentucky biology reference; https://forestry.mgcafe.uky.edu/deer). Kentucky Department of Fish and Wildlife Resources, *Kentucky’s Modern Gun Deer Season Opens Nov. 13* (2021; https://fw.ky.gov/News/Pages/Kentucky%E2%80%99s-Modern-Gun-Deer-Season-Opens-Nov.-13.aspx).

**Geography/evidence type:** Kentucky statewide extension and state wildlife-agency biological guidance.

**Supported relationship:** University of Kentucky states that white-tailed deer in Kentucky breed from October through January and that peak breeding activity usually occurs in mid-November. Kentucky Fish and Wildlife independently describes the season beginning in mid-November as designed to coincide with peak fall breeding.

**What this does not establish:** These are population-level timing summaries. They do not establish estrus, conception, mating, pregnancy, mate-searching intensity, or movement rate for an individual deer on a given date. They also do not supply a physiographic-region-specific numeric coefficient.

**Transfer disposition:** **form-transfer-ready for Kentucky regional reproductive-state gating; coefficient-transfer-not-supported.**

**Farm Watch mapping:** property state code + calendar date + explicit individual sex/age/reproductive/movement scenario. The v1 machine contract may represent October–January as the documented breeding season and November as a qualitative peak-month context while retaining individual reproductive state as explicit/unknown.

**Boundary:** Do not turn “mid-November peak” into a universal peak day, an individual estrus flag, a movement multiplier, or an assumption that every Kentucky physiographic region peaks simultaneously.

---

## FW-D22 — Female conception timing varies materially with maternal age in a Midwestern population

**Citation:** Green, M.L., Kelly, A.C., Satterthwaite-Phillips, D., Manjerovic, M.B., Shelton, P., Novakofski, J., and Mateus-Pinilla, N. 2017. *Reproductive characteristics of female white-tailed deer (Odocoileus virginianus) in the Midwestern USA.* Theriogenology 94:71–78. DOI: 10.1016/j.theriogenology.2017.02.010.

**Population/design:** Illinois; 3,884 tested females with fetal/reproductive measurements. The study estimated conception timing from fetal development and evaluated maternal-age effects on reproductive characteristics.

**Supported relationship:** Breeding peaked in November overall, but estimated mean conception date varied with maternal age. Fawns were later (December 2) than yearlings (November 11) and adults (November 8). Maternal age, year, and geography contributed to reproductive variation.

**Transfer disposition:** **form-transfer-ready for age-aware female reproductive timing; coefficient/date-transfer-not-supported to Kentucky.**

**Farm Watch mapping:** if female age class is explicitly known, preserve age as a biological-state dimension and allow a relationship module to distinguish juvenile/fawn timing from yearling/adult timing. The Illinois dates are provenance for the relationship form, not Kentucky calendar parameters.

**Boundary:** Do not assign the Illinois November 8/11 or December 2 means to Kentucky deer, and do not infer an individual doe’s conception/estrus state from age plus calendar date.

---

## FW-D23 — Ohio evidence corroborates early-November onset in mature does but does not define Kentucky timing

**Citation:** Harder, J.D., and Moorhead, D.L. 1980. *Development of Corpora Lutea and Plasma Progesterone Levels Associated with the Onset of the Breeding Season in White-tailed Deer (Odocoileus virginianus).* Biology of Reproduction 22:185–191. DOI: 10.1095/biolreprod22.2.185.

**Population/design:** Mature female white-tailed deer at Plum Brook Station, Ohio; ovaries collected monthly August–October and weekly in November 1976.

**Supported relationship:** The study documented physiological onset of the breeding season; active corpora lutea were first observed in does collected on November 6.

**Transfer disposition:** **regional mechanism/context support; not an applicable Kentucky date coefficient.**

**Farm Watch mapping:** retained as lower-Ohio-region corroboration that reproductive physiology changes in early November in a nearby population. It does not itself fire a Kentucky relationship module.

**Boundary:** Do not use November 6 as a Kentucky onset date or peak date, and do not treat physiological onset in mature does as equivalent to peak male movement.

---

# Cross-study synthesis for model architecture

## 1. Thermal state should be modeled physically, then behaviorally gated

The literature supports a real thermal mechanism, but not a universal “shade score.”

The strongest reusable form is:

- physical thermal exposure/refuge varies across space and time;
- vegetation structure and canopy alter that exposure;
- forage/resource value remains part of the tradeoff;
- response changes by diel period and season;
- cold-winter behavior may favor solar exposure even when dense cover is otherwise valuable for snow shelter.

### Required neutral derivative before deer interpretation

A future Farm Watch `thermal-exposure-context` should remain physical and could combine:

- solar geometry by date/time;
- DEM slope/aspect;
- terrain horizon/self-shading;
- canopy attenuation / canopy openness;
- available current air temperature;
- wind where defensible;
- humidity/dew point if used by the chosen biophysical formulation;
- cloud/radiation forcing if available;
- optional longwave/operative-temperature approximation with explicit assumptions.

The deer layer should consume that product; it should not bake deer semantics into the physical thermal raster.

**Current readiness:** terrain + canopy + property-targeted HRRR forcing are ready; neutral Solar/Thermal v1 implementation is awaiting production deployment/materialization.

---

## 2. “Weather movement” should not become a generic scalar

FW-D05 is a direct negative constraint against generic moon-phase and ordinary short-term weather rules. FW-D18 shows that extreme events are different and deserve their own event state. Thermal studies show that weather matters more plausibly through realized energetic/thermal conditions than through folklore variables in isolation.

Therefore:

- moon phase: **blocked absent contradictory high-quality evidence**;
- barometric pressure: **not currently supported as a general term**;
- wind speed: may matter through thermal/sensory/risk mechanisms, but no generic positive/negative movement coefficient is authorized by this ledger;
- temperature: usable only in a season/diel/thermal-context formulation;
- extreme storm/flood event: separate state, not ordinary weather.

---

## 3. Terrain must be conditional, not a ridge/draw/saddle score

FW-D14 directly demonstrates direction reversal between valleys and ridges across landscapes/movement states.

Farm Watch's neutral terrain-form labels are therefore appropriate primitives, but a deer model must combine terrain with:

- surrounding forest/cover availability;
- movement state;
- scale;
- access/risk;
- energetic cost;
- resource distribution.

A universal scalar bonus for `ridge_like_candidate`, `draw_like_candidate`, `saddle_like_candidate`, or `bench_like_candidate` is prohibited by current evidence.

---

## 4. Agriculture/resource state must be dynamic

FW-D07, FW-D08, and FW-D09 show that a static land-cover class is inadequate.

Relevant state includes:

- mast abundance and timing;
- crop species;
- crop phenology;
- harvest/removal;
- residual grain/crop availability;
- alternative woody browse;
- time of day and risk.

A stale CDL class cannot legitimately become a current food score.

---

## 5. Risk requires actual exposure history

FW-D10 through FW-D13 show that hunting response depends on localized activity, recent history, time of day, sex, and intensity.

Current roads/trails/stands/buildings may define exposure geometry, but they do not define pressure.

A future pressure model needs dated evidence such as:

- hunter presence/stand-use events;
- access intensity;
- hunting days/hours;
- camera or operator observations;
- other defensible human-use signals.

“Season open” and “distance to road” are insufficient by themselves.

---

## 6. Sex, age, reproductive state, and movement state are real model dimensions

The current science repeatedly conditions effects on:

- sex;
- age;
- rut/breeding phase;
- fawning/parturition;
- dispersal vs resident movement;
- feeding vs bedding/resting;
- daytime/crepuscular/night.

Where these states are unknown, the model should expose that uncertainty rather than collapse across them.

---

# Explicit blocked assumptions

Until new evidence is added to this ledger, Farm Watch deer modeling MUST NOT encode the following as universal rules:

- full/new moon increases or suppresses deer movement;
- falling/rising barometric pressure generically increases deer movement;
- stronger wind generically increases or suppresses movement;
- colder weather generically increases movement;
- south-facing slopes are generically preferred;
- north-facing slopes are generically preferred;
- ridges are generic travel corridors;
- draws are generic travel corridors;
- saddles are generic funnels;
- roads/trails are generically avoided;
- roads/trails are generically selected;
- dense vegetation is automatically bedding/security cover;
- field edge proximity automatically increases deer use;
- corn/soybean CDL identity means current food availability;
- nearest water or higher stream discharge means deer will use that location;
- open hunting season means deer are currently pressured.

---

# Implementation readiness matrix

| Scientific term family | Evidence status | Farm Watch input readiness | Next neutral work |
| --- | --- | --- | --- |
| Thermal exposure / refuge | strong mechanism + conditional field evidence | production neutral substrate | deer interpretation still requires explicit state/resource gates |
| Diel state | strong | implementation candidate | deterministic solar/photoperiod contract in Batch 3 |
| Rut / reproductive timing | strong, region-dependent | statewide Kentucky qualitative gate ready; exact regional dates incomplete | use FW-D21 statewide gate; capture authoritative annual physiographic-region dates before finer regionalization |
| Terrain/topography | strong evidence of context dependence | neutral inputs ready | no new physical data required before conditional model; movement-state gate required |
| Fine vegetation structure | moderate-to-strong mechanism evidence; state-specific | strong neutral structure inputs | derive/validate neutral visibility/concealment metric before biological labeling |
| Mast | strong direct evidence | not ready | oak/mast-species inventory + annual mast state |
| Crop resource state | strong | partial/stale | field-level current crop + phenology + harvest/residue state |
| Woody browse | meaningful winter evidence | not ready | defensible browse availability proxy or field observation |
| Hunting pressure | strong conditional evidence | not ready | dated/local pressure observations or measured use intensity |
| Roads/trails/human footprint | context dependent | geometry ready | combine with actual resource/risk state; never standalone sign |
| Water | limited/context-specific | neutral surface-water state implemented, pending production deployment | preserve mapped persistence vs current observed presence; retain drought/precip/gauge/soil proxies and do not infer generic deer water preference |
| Snow/winter severity | strong northern evidence | not ready/currently low priority for KY | snow depth/severity only when relevant |
| Extreme storm/flood | direct event evidence | partial | event-specific hazard/flood state |
| Moon phase | negative evidence | computable but should not be used | none; keep blocked |
| Barometric pressure | insufficient general evidence | current forcing absent | do not prioritize until relationship evidence improves |

---

# Priority research extensions

This v1 ledger is sufficient to prevent unsupported first-model terms, but it is not the end of the literature review. The next evidence additions should preferentially resolve uncertainties that would change implementation:

1. **Central/eastern US thermal ecology** — studies closer to Kentucky that quantify solar exposure, operative temperature, slope/aspect, canopy and bed/use selection.
2. **LiDAR-derived white-tailed deer visibility/concealment** — prioritize white-tailed-deer studies over extrapolation from other cervids.
3. **Oak mast spatial prediction** — studies connecting oak species/acorn production to deer space use at usable spatial/temporal scales.
4. **Corn/soy phenology and harvest** — modern GPS studies to complement FW-D08 and determine whether crop-state interactions generalize beyond one refuge/agricultural system.
5. **Hydrology/water in humid eastern landscapes** — distinguish water need from riparian movement structure.
6. **Kentucky physiographic-region breeding phenology** — capture the authoritative annual KDFWR regional conception-date product in structured form; statewide qualitative timing is now covered by FW-D21, with Illinois age effects (FW-D22) and Ohio onset evidence (FW-D23) retained at their actual transfer scope.
7. **Hunter-pressure measurement** — identify studies using explicit hunter GPS/effort data suitable for translating pressure into a dynamic risk surface.
8. **Fawning/female state** — quantify concealment/structure selection and movement changes during parturition/lactation in eastern forests.
9. **Browse availability/phenology** — identify measurable remote or field proxies that can complement agriculture and mast.
10. **Coefficient-transfer review** — only after candidate model forms are selected; recover exact standardized coefficients, scales, uncertainty, and availability definitions from the most transferable studies.

---

# Model-design consequence

The first science-backed deer model should not be a weighted overlay.

A more defensible structure is a collection of conditional relationship modules, for example:

- `thermal_resource_tradeoff(season, diel_period, thermal_exposure, vegetation_structure, forage_state)`;
- `agriculture_resource_response(crop_type, crop_stage, harvest_state, alternative_browse, diel_period)`;
- `localized_hunting_risk(recent_pressure, diel_period, sex, food_value)`;
- `terrain_movement_context(movement_state, terrain_form, forest_context, slope_cost, access)`;
- `mast_response(mast_species, mast_abundance, mast_fall_state)`;
- `reproductive_movement(sex, age, regional_breeding_state)`.

Each module should preserve its source studies and transfer status in output provenance.

Local cameras/sign/sightings should then be used to evaluate whether these transferred relationships perform acceptably on the property, not to rediscover from scratch whether acorns, crop harvest, thermal refuge, rut, or localized hunting pressure matter.

---

# Source-quality note

This ledger prioritizes peer-reviewed primary studies and authoritative publication records. Several relationships are intentionally represented by older studies because they directly measured the state of interest (for example mast fall and corn phenology) and remain more mechanistically relevant than generic recent summaries.

No hunting-media, outfitter, forum, social-media, or anecdotal source is accepted as evidence for a model term.

The deleted prior chat's exact citation set was not recoverable. This ledger is a fresh reconstruction from external literature and should now serve as the durable source of truth.
