import requests
from database import DB_DIR
from dotenv import load_dotenv
from typing import List, Generator, Any
import os

env = load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS") or "ui@openalex.org"

OPEN_ALEX_API_URL = "https://api.openalex.org/works"

INDEX_DB = os.path.join(DB_DIR, "openalex_jsonl")


def get_journal_by_id(
  journal_ids: List[str], per_page: int, min_year: int
) -> Generator[Any, None, None]:
  cursor = "*"
  if isinstance(journal_ids, str):
    journal_ids = [journal_ids]
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


def extract_pdf_locations(work: dict) -> dict[str, list[Any]]:
  primary = work.get("primary_location", {}).get("pdf_url")
  best = work.get("best_oa_location", {}).get("pdf_url")
  others = work.get("locations", [])
  other_urls = [loc.get("pdf_url") for loc in others if loc.get("pdf_url")]
  pdf_links = [best] + [primary] + other_urls
  return {"pdf_links": list(set(pdf_links))}