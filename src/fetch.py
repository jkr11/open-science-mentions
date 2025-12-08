import requests
from database import DB_DIR
from dotenv import load_dotenv
from typing import List, Generator, Any
import os
import sqlite3

env = load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS") or "ui@openalex.org"

OPEN_ALEX_API_URL = "https://api.openalex.org/works"

INDEX_DB = os.path.join(DB_DIR, "opealex_jsonl")

PSYCH_JOURNALS = ["s9692511", "s27228949"]


def get_journal_by_id(
  journal_ids: List[str], per_page: int, min_year: int
) -> Generator[Any, None, None]:
  cursor = "*"

  while True:
    params = {
      "cursor": cursor,
      "per_page": per_page,
      "filter": (
        "primary_location.source.id:"
        f"{'|'.join(journal_ids)}"
        ",open_access.is_oa:true"
        ",has_content.pdf:true"
        f",publication_year:>{min_year}"
      ),
      "sort": "publication_year:desc",
      "mailto": f"{EMAIL_ADRESS}",
    }
    try:
      r = requests.get(OPEN_ALEX_API_URL, params=params, timeout=100)
      r.raise_for_status()
      payload = r.json()
    except requests.exceptions.RequestException as e:
      print(f"An API request error occured: {e}")
      break

    results = payload.get("results", [])
    if not results:
      print("INFO: No more results found on this page. Stopping.")
      break

    for w in results:
      yield w

    cursor = payload.get("meta", {}).get("next_cursor")
    if not cursor:
      print("No more works to fetch, stopping fetch.")
      break


DATABASE_NAME = "pipeline_status.db"


def extract_pdf_locations(work: dict) -> dict[str, list[Any]]:
  primary = work.get("primary_location", {}).get("pdf_url")
  best = work.get("best_oa_location", {}).get("pdf_url")
  others = work.get("locations", [])
  other_urls = [loc.get("pdf_url") for loc in others if loc.get("pdf_url")]
  pdf_links = [best] + [primary] + other_urls
  return {"pdf_links": list(set(pdf_links))}

# TODO: write some extractors for openalex statements to remove https etc...

def insert_work_metadata(work: dict[str, Any]) -> None:
  """Inserts a single OpenAlex work's core metadata into the database."""
  pdf_locations = extract_pdf_locations(work)

  journal_name = "placeholderName"
  journal_id = "placeholderId"
  try:
    with sqlite3.connect(DATABASE_NAME) as conn:
      cursor = conn.cursor()

      cursor.execute(
        """
          INSERT OR IGNORE INTO works (
            openalex_id, journal_id, journal_name, doi, publication_year, oa_urls
          ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
          work.get("id", "N/A").split("/")[-1],
          journal_name,
          journal_id,
          work.get("doi", "N/A"),
          work.get("publication_year"),
          # work.get("open_access", {}).get("oa_url"),
          pdf_locations,
        ),
      )
      conn.commit()

  except sqlite3.Error as e:
    print(f"Database error during insert: {e}")


if __name__ == "__main__":
  max = 2
  i = 0
  for work in get_journal_by_id([PSYCH_JOURNALS[0]], 1, 2020):
    if i >= 2:
      break
    print(extract_pdf_locations(work))
    i += 1
