"""Tiny helpers used by the live playthrough notebook.

Loaded by every Stage script via `from _play_helpers import *`. Keeps
the per-stage scripts short and focused on what the human is doing.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import uuid
import urllib.request
import urllib.error
from typing import Tuple

import boto3

REGION              = "us-east-1"
API_URL             = "https://mcv8cbuldf.execute-api.us-east-1.amazonaws.com/prod/chat"
USER_POOL_ID        = "us-east-1_uOup8A1Pz"
CLIENT_ID           = "7j67jhhj9lcgo3bktk3pphmd79"
KB_ID               = "4OKUXME9AL"
DS_ID_PUBLIC        = "UUYDHGOOFY"
DS_ID_COMMENTS      = "CUJUBL0VB0"
DS_ID_ARCHIVE       = "LJFV6URA5M"
KB_DATA_BUCKET      = "bkp-kb-data-d3826230"
EMPLOYEE_AGENT_ID   = "QZY86NY4Y9"
ADMIN_AGENT_ID      = "NKNAOVW6RV"
SEED_ADMIN_USER     = "security-team@atlas.tech"
SEED_ADMIN_PASS     = "AdminSeed!2026"

cognito = boto3.client("cognito-idp",  region_name=REGION)
s3      = boto3.client("s3",           region_name=REGION)
bedrock = boto3.client("bedrock-agent", region_name=REGION)


def banner(title: str) -> None:
    line = "=" * (len(title) + 4)
    print(line)
    print(f"  {title}")
    print(line)


def load_session(name: str) -> dict:
    """Read the per-stage session JSON written by previous stages."""
    path = os.path.join(os.path.dirname(__file__), f"{name}.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def save_session(name: str, data: dict) -> None:
    path = os.path.join(os.path.dirname(__file__), f"{name}.json")
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def jwt_sub(id_token: str) -> str:
    payload = id_token.split(".")[1]
    payload += "=" * ((-len(payload)) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))["sub"]


def jwt_groups(id_token: str) -> list:
    payload = id_token.split(".")[1]
    payload += "=" * ((-len(payload)) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    g = claims.get("cognito:groups")
    if g is None:
        return []
    if isinstance(g, str):
        return [g]
    return list(g)


def chat(token: str, message: str, session_id: str | None = None) -> Tuple[int, dict]:
    sid = session_id or str(uuid.uuid4())
    body = json.dumps({"message": message, "session_id": sid}).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type":  "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {"error": "non-json"}


def write_evidence(name: str, payload: str | dict) -> str:
    """Write a small evidence file under playthrough_evidence/."""
    here = os.path.dirname(__file__)
    path = os.path.join(here, name)
    if isinstance(payload, (dict, list)):
        text = json.dumps(payload, ensure_ascii=False, indent=2, default=str)
    else:
        text = str(payload)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path
