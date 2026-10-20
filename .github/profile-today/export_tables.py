"""Exports the tables of an xctrace trace worth analysing, gzipped, plus the table of contents.

usage: export_tables.py TRACE OUTDIR
Time Profiler: time-profile (and time-sample). SwiftUI template: every table whose schema mentions swiftui, plus hitches and
hangs. A table that cannot be exported is reported and skipped.
"""
import gzip
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

trace, outdir = sys.argv[1:3]
os.makedirs(outdir, exist_ok=True)
name = os.path.basename(trace).removesuffix(".trace")
toc_path = os.path.join(outdir, f"{name}.toc.xml")
subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc", "--output", toc_path], check=False)
if not os.path.exists(toc_path):
    sys.exit("no toc")
root = ET.parse(toc_path).getroot()
WANT = re.compile(r"^(time-profile|time-sample|cpu-profile|.*swiftui.*|.*hitch.*|.*hang.*|potential-hangs|runloop.*|life-cycle.*)$", re.I)
seen = {}
for run in root.iter("run"):
    number = run.get("number")
    for table in run.iter("table"):
        schema = table.get("schema")
        if not schema:
            continue
        index = seen.get((number, schema), 0) + 1
        seen[(number, schema)] = index
        print(f"toc run {number} table {schema} #{index} attrs {dict(table.attrib)}")
        if not WANT.match(schema):
            continue
        xpath = f'/trace-toc/run[@number="{number}"]/data/table[@schema="{schema}"][{index}]'
        target = os.path.join(outdir, f"{name}.run{number}.{schema}.{index}.xml")
        result = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath, "--output", target],
                                capture_output=True, text=True)
        if not os.path.exists(target) or os.path.getsize(target) == 0:
            print("  export failed:", (result.stderr or result.stdout)[-300:])
            continue
        with open(target, "rb") as src, gzip.open(target + ".gz", "wb", compresslevel=6) as dst:
            shutil.copyfileobj(src, dst)
        print(f"  exported {os.path.getsize(target)/1e6:.1f} MB -> {os.path.getsize(target + '.gz')/1e6:.1f} MB gz")
        os.remove(target)
