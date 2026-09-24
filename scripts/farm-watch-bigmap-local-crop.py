#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = "farm-watch-bigmap-local-crop-manifest-v1"
SOURCE_SIZE = [89932, 91150]
SOURCE_GT = [-307830.0, 30.0, 0.0, 3055650.0, 0.0, -30.0]
CROP_WINDOW = [42166, 43231, 206, 222]
CROP_GT = [957150.0, 30.0, 0.0, 1758720.0, 0.0, -30.0]
CROP_BBOX = [957150.0, 1752060.0, 963330.0, 1758720.0]
NODATA = 3.4e38
SOURCE_RE = re.compile(r"(?:^|_)AGB_(\d{4})_2018_.*\.tif$", re.I)

GROUPS = {
    "white_oak": [
        (802, "white oak", "Quercus alba"),
        (804, "swamp white oak", "Quercus bicolor"),
        (822, "overcup oak", "Quercus lyrata"),
        (823, "bur oak", "Quercus macrocarpa"),
        (825, "swamp chestnut oak", "Quercus michauxii"),
        (826, "chinkapin oak", "Quercus muehlenbergii"),
        (832, "chestnut oak", "Quercus prinus"),
        (835, "post oak", "Quercus stellata"),
    ],
    "red_oak": [
        (806, "scarlet oak", "Quercus coccinea"),
        (812, "southern red oak", "Quercus falcata"),
        (813, "cherrybark oak", "Quercus pagoda"),
        (817, "shingle oak", "Quercus imbricaria"),
        (824, "blackjack oak", "Quercus marilandica"),
        (827, "water oak", "Quercus nigra"),
        (830, "pin oak", "Quercus palustris"),
        (831, "willow oak", "Quercus phellos"),
        (833, "northern red oak", "Quercus rubra"),
        (834, "Shumard oak", "Quercus shumardii"),
        (837, "black oak", "Quercus velutina"),
    ],
    "hickory": [
        (400, "hickory spp.", "Carya spp."),
        (402, "bitternut hickory", "Carya cordiformis"),
        (403, "pignut hickory", "Carya glabra"),
        (405, "shellbark hickory", "Carya laciniosa"),
        (407, "shagbark hickory", "Carya ovata"),
        (409, "mockernut hickory", "Carya alba"),
        (412, "red hickory", "Carya ovalis"),
        (413, "southern shagbark hickory", "Carya carolinae-septentrionalis"),
    ],
    "beech": [(531, "American beech", "Fagus grandifolia")],
}
SPECIES = {
    spcd: {"group": group, "common_name": common, "scientific_name": scientific}
    for group, rows in GROUPS.items()
    for spcd, common, scientific in rows
}

def run_json(*args: str) -> dict[str, Any]:
    return json.loads(subprocess.run(args, check=True, capture_output=True, text=True).stdout)

def close(a: float, b: float) -> bool:
    return math.isclose(float(a), float(b), abs_tol=1e-6, rel_tol=0)

def validate_raster_common(info: dict[str, Any], label: str) -> tuple[list[int], list[float]]:
    size = info.get("size")
    if (
        not isinstance(size, list)
        or len(size) != 2
        or any(not isinstance(value, int) or value <= 0 for value in size)
    ):
        raise RuntimeError(f"{label}: invalid raster size {size}")
    gt = info.get("geoTransform")
    if (
        not isinstance(gt, list)
        or len(gt) != 6
        or not close(gt[1], 30.0)
        or not close(gt[2], 0.0)
        or not close(gt[4], 0.0)
        or not close(gt[5], -30.0)
    ):
        raise RuntimeError(f"{label}: unexpected 30 m north-up geotransform {gt}")
    wkt = str(info.get("coordinateSystem", {}).get("wkt") or "")
    if "USA_Contiguous_Albers_Equal_Area_Conic_USGS_version" not in wkt or "NAD83" not in wkt:
        raise RuntimeError(f"{label}: unexpected CRS")
    bands = info.get("bands") or []
    if len(bands) != 1 or bands[0].get("type") != "Float32":
        raise RuntimeError(f"{label}: expected one Float32 band")
    nodata = bands[0].get("noDataValue")
    if nodata is None or abs(float(nodata) / NODATA - 1) > 0.01:
        raise RuntimeError(f"{label}: unexpected NoData {nodata}")
    return [int(size[0]), int(size[1])], [float(value) for value in gt]


def source_window(info: dict[str, Any], label: str) -> tuple[list[int], list[int], list[float]]:
    size, gt = validate_raster_common(info, label)
    xoff_raw = (CROP_GT[0] - gt[0]) / 30.0
    yoff_raw = (gt[3] - CROP_GT[3]) / 30.0
    xoff = round(xoff_raw)
    yoff = round(yoff_raw)
    if not close(xoff_raw, xoff) or not close(yoff_raw, yoff):
        raise RuntimeError(
            f"{label}: source grid is not aligned to the Farm Watch 30 m target grid "
            f"(offsets {xoff_raw}, {yoff_raw})"
        )
    width, height = CROP_SIZE
    if xoff < 0 or yoff < 0 or xoff + width > size[0] or yoff + height > size[1]:
        raise RuntimeError(
            f"{label}: Farm Watch crop lies outside this species raster extent "
            f"(source size {size}, window {[xoff, yoff, width, height]})"
        )
    return [xoff, yoff, width, height], size, gt


def validate_crop(info: dict[str, Any], label: str) -> None:
    size, gt = validate_raster_common(info, label)
    if size != CROP_SIZE:
        raise RuntimeError(f"{label}: unexpected crop size {size}")
    if any(not close(a, b) for a, b in zip(gt, CROP_GT)):
        raise RuntimeError(f"{label}: unexpected crop geotransform {gt}")

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def crop_name(spcd: int, common: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", common.lower()).strip("-")
    return f"farm-watch-bigmap-{spcd:04d}-{slug}-crop.tif"

def find_sources(roots: list[Path]) -> dict[int, Path]:
    hits: dict[int, list[Path]] = {spcd: [] for spcd in SPECIES}
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*.tif"):
            match = SOURCE_RE.search(path.name)
            if match and int(match.group(1)) in hits:
                hits[int(match.group(1))].append(path.resolve())
    out: dict[int, Path] = {}
    for spcd, paths in hits.items():
        unique = sorted(set(paths))
        if len(unique) > 1:
            raise RuntimeError(
                f"multiple BIGMAP source TIFFs found for SPCD {spcd:04d}: "
                + ", ".join(str(path) for path in unique)
            )
        if unique:
            out[spcd] = unique[0]
    return out

def main() -> int:
    parser = argparse.ArgumentParser(description="Crop official BIGMAP 2018 mast-species rasters to the Flat Creek Farm Watch native-grid window.")
    parser.add_argument("roots", nargs="*", default=[str(Path.home() / "Downloads")])
    parser.add_argument("--output-dir", default=str(Path.home() / "farm-watch-bigmap-mast-crops"))
    parser.add_argument("--require-all", action="store_true")
    parser.add_argument("--bundle", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    missing_tools = [x for x in ("gdalinfo", "gdal_translate") if shutil.which(x) is None]
    if missing_tools:
        raise RuntimeError("missing GDAL tools: " + ", ".join(missing_tools))

    roots = [Path(x).expanduser().resolve() for x in args.roots]
    output = Path(args.output_dir).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    sources = find_sources(roots)
    manifest_path = output / "farm-watch-bigmap-mast-crops-manifest.json"
    previous_items: dict[int, dict[str, Any]] = {}
    if manifest_path.exists():
        try:
            previous = json.loads(manifest_path.read_text())
            if previous.get("schema") == SCHEMA:
                previous_items = {
                    int(item["spcd"]): item
                    for item in previous.get("items", [])
                    if int(item.get("spcd", -1)) in SPECIES
                }
        except (OSError, ValueError, TypeError):
            previous_items = {}

    items: list[dict[str, Any]] = []
    missing: list[int] = []

    for spcd in sorted(SPECIES):
        spec = SPECIES[spcd]
        source = sources.get(spcd)
        crop = output / crop_name(spcd, spec["common_name"])

        if source is not None:
            source_info = run_json("gdalinfo", "-json", str(source))
            window, source_dimensions, source_geotransform = source_window(source_info, source.name)
            if args.overwrite or not crop.exists():
                print(
                    f"Cropping {spcd:04d} {spec['common_name']} "
                    f"from source window {window[0]},{window[1]},{window[2]},{window[3]}"
                )
                subprocess.run([
                    "gdal_translate", "-srcwin", *map(str, window),
                    "-of", "GTiff", "-co", "TILED=YES", "-co", "COMPRESS=DEFLATE", "-co", "PREDICTOR=3",
                    str(source), str(crop),
                ], check=True)
            source_name = source.name
            source_size = source.stat().st_size
        else:
            prior = previous_items.get(spcd)
            if not crop.exists() or prior is None:
                missing.append(spcd)
                continue
            source_name = str(prior.get("source_tiff_name") or "")
            source_size = int(prior.get("source_tiff_size_bytes") or 0)
            source_dimensions = prior.get("source_dimensions")
            source_geotransform = prior.get("source_geotransform")
            window = prior.get("source_window")
            if not source_name or source_size <= 0:
                missing.append(spcd)
                continue
            print(f"Reusing validated bounded crop {spcd:04d} {spec['common_name']}")

        validate_crop(run_json("gdalinfo", "-json", str(crop)), crop.name)
        items.append({
            "spcd": spcd,
            **spec,
            "source_tiff_name": source_name,
            "source_tiff_size_bytes": source_size,
            "source_dimensions": source_dimensions,
            "source_geotransform": source_geotransform,
            "source_window": window,
            "crop_file": crop.name,
            "crop_size_bytes": crop.stat().st_size,
            "crop_sha256": sha256(crop),
        })

    manifest = {
        "schema": SCHEMA,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source": {
            "authority": "USDA Forest Service Forest Inventory and Analysis (FIA)",
            "product": "FIA BIGMAP 2018 Tree Species Aboveground Biomass",
            "data_year": 2018,
            "bulk_download_page": "https://data.fs.usda.gov/geodata/rastergateway/bigmap/",
            "native_crs": "ESRI:102039",
            "native_pixel_meters": 30,
        },
        "crop": {
            "property_slug": "validation-property-01",
            "window": {"width": 206, "height": 222, "source_window_per_species": True},
            "bbox_esri_102039": CROP_BBOX,
            "resampling_performed": False,
        },
        "expected_species_codes": sorted(SPECIES),
        "present_species_codes": sorted(item["spcd"] for item in items),
        "missing_species_codes": missing,
        "items": items,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Validated {len(items)}/{len(SPECIES)} required species")
    print(f"Manifest: {manifest_path}")

    if missing:
        print("Missing SPCDs: " + ", ".join(f"{x:04d}" for x in missing))
        return 2 if args.require_all or args.bundle else 0

    if args.bundle:
        bundle = output / "farm-watch-bigmap-mast-crops-validation-property-01.tar.gz"
        with tarfile.open(bundle, "w:gz") as tf:
            tf.add(manifest_path, arcname=manifest_path.name)
            for item in items:
                tf.add(output / item["crop_file"], arcname=item["crop_file"])
        print(f"Bundle: {bundle}")
        print(f"Bundle SHA-256: {sha256(bundle)}")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"command failed: {' '.join(error.cmd)}", file=sys.stderr)
        raise SystemExit(error.returncode)
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
