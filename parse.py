import requests
import json
from dotenv import load_dotenv
import os
from typing import Generator, List, Dict, Any, Optional, Tuple
import hashlib
import datetime
import sqlite3

load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS") # set this in a .env

INDEX_DB = "db/index.db"
PDF_DB = "db/pdfs.db"
conn = sqlite3.connect(INDEX_DB)
cur = conn.cursor()

connpdf = sqlite3.connect(PDF_DB)
pdfcur = connpdf.cursor()


def get_pages(per_page: int = 50, max_pages: int = 10) -> Generator[Dict[str, Any], None, None]:
  page = 1
  for _ in range(max_pages):
    r = requests.get(
      f"https://api.openalex.org/works?page={page}&per-page={per_page}",
      timeout=10,
    )
    r.raise_for_status()
    data = r.json().get("results", [])
    if not data:
      break
    for w in data:
      yield w
    page += 1


def get_pdf_url_list(work) -> List[str]:
  urls = []

  def add(x: str) -> None:
    if x and isinstance(x, str):
      urls.append(x)

  PL = work.get("primary_location", {})
  add(PL.get("pdf_url"))

  BL = work.get("best_oa_location", {})
  add(BL.get("pdf_url"))

  LOC = work.get("locations", [])
  for loc in LOC:
    add(loc.get("pdf_url"))

  return urls


def extract_pdf_urls(work):
  primary = work.get("primary_location", {}).get("pdf_url")
  # best = work.get("best_oa_location", {}).get("pdf_url") !TODO!
  best = "placeholder"
  others = work.get("locations", [])
  other_urls = [loc.get("pdf_url") for loc in others if loc.get("pdf_url")]
  return primary, best, json.dumps(other_urls)


def save_work_metadata(w):
  work_id = w.get("id")
  doi = w.get("doi")
  title = w.get("title")
  year = w.get("publication_year")
  fetched_at = datetime.datetime.now(datetime.timezone.utc)
  return work_id, doi, title, year, fetched_at


def write_metadata_to_index_db(per_page: int = 50, max_pages: int = 10):
  inserted = 0
  for work in get_pages(per_page=per_page, max_pages=max_pages):
    work_id, doi, title, year, fetched_at = save_work_metadata(work)
    primary_url, best_url, other_urls = extract_pdf_urls(work)
    try:
      cur.execute(
        """
        INSERT OR IGNORE INTO works 
        (work_id, doi, title, year, fetched_at, primary_pdf_url, best_pdf_url, other_pdf_urls)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
        (work_id, doi, title, year, fetched_at, primary_url, best_url, other_urls),
      )

      inserted += 1
    except Exception as e:
      print(f"Failed to insert {work_id} : {e}")
  conn.commit()
  print(f"Inserted {inserted} works into index.db")


def sha256_file(path: str) -> str:
  h = hashlib.sha256()
  with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(8192), b""):
      h.update(chunk)
  return h.hexdigest()


def download_first_pdf(
  urls: List[str], tmp_path: str = "pdf_cache/tmp_download.pdf", timeout: int = 10
) -> Optional[Tuple[str, str, str]]:
  if not urls:
    return None

  for url in urls:
    try:
      r = requests.get(url, stream=True, timeout=timeout)
      if r.status_code != 200:
        continue

      with open(tmp_path, "wb") as f:
        for chunk in r.iter_content(8192):
          if chunk:
            f.write(chunk)

      h = sha256_file(tmp_path)
      final_path = f"pdf_cache/sha256_{h}.pdf"

      if not os.path.exists(final_path):
        os.rename(tmp_path, final_path)
      else:
        os.remove(tmp_path)

      return url, h, final_path
    except Exception:
      if os.path.exists(tmp_path):
        os.remove(tmp_path)
      continue

  return None


if __name__ == "__main__":
  write_metadata_to_index_db(10, 2)
