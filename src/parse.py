import requests
import json
from dotenv import load_dotenv
import os
from typing import Generator, List, Dict, Any, Optional, Tuple
import hashlib
import datetime
import sqlite3

from database import DB_PATH, DB_DIR

load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS")  # set this in a .env

PDF_CACHE = os.path.join(DB_DIR, "pdf_cache")
os.makedirs(PDF_CACHE, exist_ok=True)


def log(msg):
  print(f"\033[92m {msg}")


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
  # best = work.get("best_oa_location", {}).get("pdf_url")
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


def write_metadata_to_index_db(conn: sqlite3.Connection, per_page: int = 50, max_pages: int = 10):
  cur = conn.cursor()
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
  urls: List[str], timeout: int = 10, tmp_path: Optional[str] = None
) -> Optional[Tuple[str, str, str]]:
  if not urls:
    return None

  tmp_path = tmp_path or os.path.join(PDF_CACHE, "tmp_download.pdf")
  os.makedirs(PDF_CACHE, exist_ok=True)

  for url in urls:
    print(f"Trying {url}")
    try:
      r = requests.get(url, stream=True, timeout=timeout)
      if r.status_code != 200:
        continue
      with open(tmp_path, "wb") as f:
        for chunk in r.iter_content(8192):
          if chunk:
            f.write(chunk)

      h = sha256_file(tmp_path)
      final_path = os.path.join(PDF_CACHE, f"sha256_{h}.pdf")

      if not os.path.exists(final_path):
        os.rename(tmp_path, final_path)
      else:
        os.remove(tmp_path)

      return url, h, final_path
    except Exception as e:
      print(f"Failed to download first pdf : {e}")
      if os.path.exists(tmp_path):
        os.remove(tmp_path)
      continue

  return None


def batch_download_works(conn: sqlite3.Connection, batch_size: int = 20) -> bool:
  cur = conn.cursor()

  # Fetch a batch of works not yet attempted
  cur.execute(
    """
      SELECT work_id, doi, primary_pdf_url, best_pdf_url, other_pdf_urls
      FROM works
      WHERE download_attempted=0
      LIMIT ?
    """,
    (batch_size,),
  )
  rows = cur.fetchall()
  print(f"Batch of size: {len(rows)}")
  is_end = False
  if not rows:
    print("No more rows to process")
    is_end = True
  for work_id, doi, primary, best, other_json in rows:
    urls = [url for url in [primary, best] if url and url != "placeholder"]
    if other_json:
      urls.extend(json.loads(other_json))

    result = download_first_pdf(urls)
    downloaded_at = datetime.datetime.now(datetime.timezone.utc)

    if result:
      url_used, sha, path = result
      cur.execute(
        """
          INSERT OR REPLACE INTO pdfs (work_id, pdf_sha256, pdf_path, pdf_url_used, downloaded_at, processed, deleted)
          VALUES (?, ?, ?, ?, ?, 0, 0)
        """,
        (work_id, sha, path, url_used, downloaded_at),
      )
      print(f"Downloaded {doi} -> {path} from {url_used}")
    else:
      print(f"Failed to download {doi}")

    cur.execute("UPDATE works SET download_attempted=1 WHERE work_id=?", (work_id,))

  conn.commit()
  return is_end


class Batch:
  def __init__(self, conn: sqlite3.Connection, rows):
    self.conn = conn
    self.rows = rows
    self.results = []

  def download_pdfs(self):
    cur = self.conn.cursor()
    for work_id, doi, primary, best, other_json in self.rows:
      urls = [u for u in [primary, best] if u and u != "placeholder"]
      if other_json:
        urls.extend(json.loads(other_json))

      result = download_first_pdf(urls)
      downloaded_at = datetime.datetime.now(datetime.timezone.utc)

      if result:
        url_used, sha, path = result
        cur.execute(
          """
            INSERT OR REPLACE INTO pdfs 
            (work_id, pdf_sha256, pdf_path, pdf_url_used, downloaded_at, processed, deleted)
            VALUES (?, ?, ?, ?, ?, 0, 0)
          """,
          (work_id, sha, path, url_used, downloaded_at),
        )
        self.results.append((work_id, True))
      else:
        self.results.append((work_id, False))

      cur.execute("UPDATE works SET download_attempted=1 WHERE work_id=?", (work_id,))
    self.conn.commit()


def batch_iterator(conn: sqlite3.Connection, batch_size=20) -> Generator[Batch, Any, None]:
  cur = conn.cursor()
  while True:
    cur.execute(
      """
        SELECT work_id, doi, primary_pdf_url, best_pdf_url, other_pdf_urls
        FROM works
        WHERE download_attempted = 0
        LIMIT ?
      """,
      (batch_size,),
    )
    rows = cur.fetchall()
    if not rows:
      break
    yield Batch(conn, rows)


if __name__ == "__main__":
  conn = sqlite3.connect(DB_PATH)
  write_metadata_to_index_db(conn, 50, 10)
  while True:
    if batch_download_works(conn, 20):
      break
