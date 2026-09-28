"""
Last.fm -> Snowflake loader (runs in GitHub Actions, replaces the Airflow DAG tasks
`fetch_and_upload_to_azure` and `copy_into_snowflake`).

Steps:
  1. EXTRACT: call the Last.fm API for the global top 50 tracks
  2. Save the JSON as data/lastfm_top_tracks_YYYY-MM-DDTHH-MI.json
  3. PUT the file into the Snowflake internal stage @LASTFM.RAW.LASTFM_STAGE
  4. COPY INTO LASTFM.RAW.TOP_TRACKS (same logic as the old DAG)

Usage:
  python load_to_snowflake.py                 # normal daily run
  python load_to_snowflake.py --backfill data # load old JSON files from a folder (no API call)

Needed environment variables (GitHub Secrets in CI, a .env file locally):
  LASTFM_API_KEY, SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY_PATH
Optional (have defaults): SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE
"""

import argparse
import datetime
import json
import os
from pathlib import Path

import requests
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()  # reads .env when running locally; does nothing in GitHub Actions

STAGE = "@LASTFM.RAW.LASTFM_STAGE"
TABLE = "LASTFM.RAW.TOP_TRACKS"

# Same COPY INTO as the Airflow DAG, only the stage changed (Azure -> internal).
# The timestamp comes from the file name, so old files keep their real date.
# Snowflake remembers which files it already loaded (for 64 days), so running
# this again never loads the same file twice. (No FORCE = TRUE: that caused the
# duplicates last time.)
COPY_SQL = f"""
    COPY INTO {TABLE} (RAW_DATA, LOADED_AT)
    FROM (
        SELECT
            $1,
            TO_TIMESTAMP(
                SUBSTR(SPLIT_PART(METADATA$FILENAME, '/', -1), 19, 16),
                'YYYY-MM-DDTHH-MI'
            )
        FROM {STAGE}
    )
    FILE_FORMAT = (TYPE = 'JSON')
    PATTERN = '.*lastfm_top_tracks_.*[.]json.*'
"""


def fetch_top_tracks() -> Path:
    """Call Last.fm and save the result as a timestamped JSON file."""
    api_key = os.environ["LASTFM_API_KEY"]
    url = "https://ws.audioscrobbler.com/2.0/"
    params = {
        "method": "chart.gettoptracks",
        "api_key": api_key,
        "format": "json",
        "limit": 50,
    }

    response = requests.get(url, params=params, timeout=30)
    response.raise_for_status()  # stop with an error on 4xx/5xx
    data = response.json()

    if "tracks" not in data:  # Last.fm returns {"error": ..., "message": ...} on problems
        raise RuntimeError(f"Unexpected Last.fm response: {data}")

    # Same enrichment as before: add the chart position to every track
    for position, track in enumerate(data["tracks"]["track"], start=1):
        track["chart_position"] = position

    # UTC, because GitHub's servers run on UTC. Keeps every run consistent.
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H-%M")
    path = Path("data") / f"lastfm_top_tracks_{timestamp}.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(data, indent=2))

    print(f"Fetched {len(data['tracks']['track'])} tracks -> {path}")
    return path


def connect():
    """Log in to Snowflake as the service user with the RSA private key (no password)."""
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",  # = key-pair authentication
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ.get("SNOWFLAKE_ROLE", "LASTFM_PIPELINE_ROLE"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "LASTFM_WH"),
        database="LASTFM",
        schema="RAW",
    )


def upload_and_copy(files: list[Path]) -> None:
    """PUT the files into the internal stage, then COPY INTO the raw table."""
    with connect() as conn, conn.cursor() as cur:
        for f in files:
            # PUT uploads a local file to the stage. AUTO_COMPRESS gzips it (smaller,
            # and COPY INTO reads .gz automatically). OVERWRITE=FALSE: a file already
            # in the stage is left alone.
            cur.execute(f"PUT 'file://{f.resolve().as_posix()}' {STAGE} AUTO_COMPRESS=TRUE OVERWRITE=FALSE")
            print(f"PUT {f.name}: {cur.fetchone()[6]}")  # column 6 = status (UPLOADED / SKIPPED)

        cur.execute(COPY_SQL)
        results = cur.fetchall()
        # When nothing is new, Snowflake returns one row saying "Copy executed with 0 files processed."
        loaded = [r for r in results if len(r) > 1 and r[1] == "LOADED"]
        print(f"COPY INTO: {len(loaded)} new file(s) loaded into {TABLE}")
        for r in results:
            print("   ", r[:4])


def main():
    parser = argparse.ArgumentParser(description="Load Last.fm top tracks into Snowflake")
    parser.add_argument("--backfill", metavar="FOLDER",
                        help="Load existing lastfm_top_tracks_*.json files from FOLDER instead of calling the API")
    args = parser.parse_args()

    if args.backfill:
        files = sorted(Path(args.backfill).glob("lastfm_top_tracks_*.json"))
        if not files:
            raise SystemExit(f"No lastfm_top_tracks_*.json files found in {args.backfill}")
        print(f"Backfill: {len(files)} file(s) from {args.backfill}")
    else:
        files = [fetch_top_tracks()]

    upload_and_copy(files)


if __name__ == "__main__":
    main()
