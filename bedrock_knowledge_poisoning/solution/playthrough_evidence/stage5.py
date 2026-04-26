"""Stage 5 -- archive/qna/ persisted with audience=public, ingested."""
import re
from _play_helpers import *

banner("Stage 5 / Archive sidecar verification")

FLAG_RE = re.compile(r"FLAG\{atlas[^}\.]+\}")

print("[stage5] poll archive/qna/ for the archived admin answer ...")
deadline = time.time() + 60
matching_key = None
matching_body = None

while time.time() < deadline:
    resp = s3.list_objects_v2(Bucket=KB_DATA_BUCKET, Prefix="archive/qna/")
    contents = sorted(
        (c for c in resp.get("Contents", []) if not c["Key"].endswith(".metadata.json")),
        key=lambda x: x["LastModified"],
        reverse=True,
    )
    print(f"[stage5]   {len(contents)} body keys under archive/qna/  (top 3 shown)")
    for obj in contents[:3]:
        print(f"   - {obj['Key']}  lastmod={obj['LastModified']}")
    for obj in contents[:5]:
        body = s3.get_object(Bucket=KB_DATA_BUCKET, Key=obj["Key"])["Body"].read().decode("utf-8", "replace")
        if FLAG_RE.search(body):
            matching_key = obj["Key"]
            matching_body = body
            break
    if matching_key:
        break
    time.sleep(4)

if not matching_key:
    print("[stage5] FAIL: no archive object containing the flag yet")
    save_session("stage5", {"status": "FAIL"})
    raise SystemExit(1)

print(f"\n[stage5] match key = {matching_key}")
print(f"[stage5] body[:400]:\n{matching_body[:400]}")

sidecar_key = matching_key + ".metadata.json"
sidecar_raw = s3.get_object(Bucket=KB_DATA_BUCKET, Key=sidecar_key)["Body"].read().decode()
sidecar     = json.loads(sidecar_raw)
audience    = sidecar.get("metadataAttributes", {}).get("audience")
print(f"\n[stage5] sidecar key      = {sidecar_key}")
print(f"[stage5] sidecar raw      = {sidecar_raw}")
print(f"[stage5] sidecar audience = {audience!r}  (expected: 'public')")

write_evidence("stage5_archive_body.md",     matching_body)
write_evidence("stage5_archive_sidecar.json", {"key": sidecar_key, "metadata": sidecar})

print("\n[stage5] starting ingestion job for archive DS ...")
job = bedrock.start_ingestion_job(knowledgeBaseId=KB_ID, dataSourceId=DS_ID_ARCHIVE)
job_id = job["ingestionJob"]["ingestionJobId"]
print(f"[stage5]   ingestion job {job_id} STARTING")
while True:
    desc = bedrock.get_ingestion_job(
        knowledgeBaseId=KB_ID, dataSourceId=DS_ID_ARCHIVE, ingestionJobId=job_id,
    )
    status = desc["ingestionJob"]["status"]
    print(f"[stage5]   status = {status}")
    if status in ("COMPLETE", "FAILED"):
        write_evidence("stage5_ingestion_job.json", {
            "ingestionJobId": job_id, "status": status,
            "statistics":     desc["ingestionJob"].get("statistics", {}),
        })
        break
    time.sleep(6)

save_session("stage5", {
    "archive_key":      matching_key,
    "sidecar_audience": audience,
    "ingestion":        status,
})
print("\n[stage5] PASS" if audience == "public" and status == "COMPLETE" else "\n[stage5] FAIL")
