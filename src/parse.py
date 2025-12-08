import requests
from requests.exceptions import (
  Timeout,
  ConnectionError,
  HTTPError,
  RequestException,
)
import json
from dotenv import load_dotenv
import os
from typing import Generator, List, Dict, Any, Optional, Tuple
import hashlib
import datetime
import sqlite3
import subprocess
from database import DB_PATH, DB_DIR, BASE_DIR
import queries

# from processing import (
#  extract_grobid,
#  search,
# )
from grobid_client.grobid_client import GrobidClient

load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS")  # set this in a .env

PDF_CACHE = os.path.join(DB_DIR, "pdf_cache")
os.makedirs(PDF_CACHE, exist_ok=True)

DATA_DIR = os.path.join(BASE_DIR, "data")
PDF_DIR = os.path.join(DATA_DIR, "pdfs")
TEI_DIR = os.path.join(DATA_DIR, "teis")

SPED_JOURNALS = [
  "s26220619",
  "s133489141",
  "s136622136",
  "s38537713",
  "s193250556",
  "s93932044",
  "s2738745139",
  "s27825752",
  "s2764729928",
  "s171182518",
]

PSYCH_QUERY = "https://api.openalex.org/works?page=1&filter=primary_location.source.id:s9692511|s27228949,open_access.is_oa:true,has_content.pdf:true&sort=publication_year:desc&per_page=10&mailto=ui@openalex.org"

PSYCH_JOURNALS = ["s9692511", "s27228949"]


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


def get_top_journals_(per_page: int, max_pages: int = 1) -> Generator[Any, Any, None]:
  for _ in range(max_pages):
    search = f"https://api.openalex.org/works?page=1&filter=primary_location.source.id:s26220619|s133489141|s136622136|s38537713|s193250556|s93932044|s2738745139|s27825752|s2764729928|s171182518,open_access.is_oa:true,has_content.pdf:true&sort=cited_by_count:desc&per_page={per_page}&mailto=ui@openalex.org"
    r = requests.get(search, timeout=100)
    r.raise_for_status()
    data = r.json().get("results", [])
    if not data:
      break
    for w in data:
      yield w


def get_top_journals(
  per_page: int,
  journal_ids: List[str],
  max_pages: int = 10,
) -> Generator[Any, None, None]:
  cursor = "*"

  for _ in range(max_pages):
    url = "https://api.openalex.org/works"
    params = {
      "cursor": cursor,
      "per_page": per_page,
      "filter": (
        "primary_location.source.id:"
        f"{'|'.join(journal_ids)}"
        ",open_access.is_oa:true"
        ",has_content.pdf:true"
      ),
      "sort": "publication_year:desc",
      "mailto": "ui@openalex.org",
    }

    r = requests.get(url, params=params, timeout=100)
    r.raise_for_status()
    payload = r.json()

    results = payload.get("results", [])
    if not results:
      break

    for w in results:
      yield w

    cursor = payload.get("meta", {}).get("next_cursor")
    if not cursor:
      break


def get_by_journal(max: int = 50):
  pass


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

  return list(set(urls))


def extract_pdf_urls(work) -> tuple[str, str, str]:
  primary = work.get("primary_location", {}).get("pdf_url")
  best = work.get("best_oa_location", {}).get("pdf_url")
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
  for work in get_top_journals(per_page=per_page, journal_ids=SPED_JOURNALS):
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
  urls: List[str], timeout: int = 120, tmp_path: Optional[str] = None
) -> Optional[Tuple[str, str, str]]:
  if not urls:
    return None

  tmp_path = tmp_path or os.path.join(PDF_DIR, "tmp_download.pdf")
  os.makedirs(PDF_DIR, exist_ok=True)
  headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
  }
  for url in set(urls):
    if "needAccess=true" in url:
      url = url.replace("needAccess", "download")
    # if "tandf" in url or "sage" in url:
    #  continue
    print(f"Attempting download from {url}")
    try:
      r = requests.get(url, stream=True, timeout=timeout)
      r.raise_for_status()
      with open(tmp_path, "wb") as f:
        for chunk in r.iter_content(8192):
          if chunk:
            f.write(chunk)

      h = sha256_file(tmp_path)
      final_path = os.path.join(PDF_DIR, f"sha256_{h}.pdf")

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


def download_wget(url: str, timeout: int = 10):
  tmp_path = os.path.join(PDF_CACHE, "tmp_download.pdf")
  cmd = [
    "wget",
    "-O",
    tmp_path,
    "--timeout",
    str(timeout),
    "--tries==3",
    "--max-redirect=5",
    "--quiet",
    url,
  ]
  result = subprocess.run(cmd)
  if result.returncode != 0:
    os.remove(tmp_path)
    return None
  return tmp_path


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
      print("================")
      print(f"Successfully downloaded {doi}")
      print("================")
    else:
      print("================")
      print(f"Failed to download {doi}")
      print("================")

    cur.execute("UPDATE works SET download_attempted=1 WHERE work_id=?", (work_id,))

  conn.commit()
  return is_end


class Batch:
  def __init__(self, conn: sqlite3.Connection, rows):
    self.conn = conn
    self.rows = rows
    self.results = []
    self.work_ids = [r[0] for r in rows]

  def download_pdfs(self):
    cur = self.conn.cursor()
    for work_id, _, primary, best, other_json in self.rows:
      urls = [u for u in [primary, best] if u and u != "placeholder"]  # TODO
      if other_json:
        urls.extend(json.loads(other_json))  # TODO outsource to function

      result = download_first_pdf(urls)
      downloaded_at = datetime.datetime.now(datetime.timezone.utc)  # TODO needs to be replaced?

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

  def process_pdfs(self, keywords):
    cur = self.conn.cursor()

    placeholders = ",".join("?" for _ in self.work_ids)
    sql = queries.SELECT_PDFS_BY_WORK_ID.format(placeholders)

    cur.execute(sql, self.work_ids)
    pdf_rows = cur.fetchall()

    for work_id, pdf_path in pdf_rows:
      print(f"Processing PDF for work_id={work_id}")

      # Extract text
      tei = extract_grobid(pdf_path)
      if not tei:
        print(f"GROBID extraction failed for {pdf_path}")
        continue

      matched_keywords, _ = search(str(tei))

      processed_at = datetime.datetime.now(datetime.timezone.utc)

      cur.execute(
        queries.INSERT_TEXT_HITS,
        (work_id, json.dumps(matched_keywords), "", processed_at),
      )

      cur.execute(queries.MARK_PDF_PROCESSED, (work_id,))

      # try:
      #  os.remove(pdf_path)
      # except FileNotFoundError:
      #  pass

    self.conn.commit()


def batch_iterator(conn: sqlite3.Connection, batch_size=20) -> Generator[Batch, Any, None]:
  cur = conn.cursor()
  while True:
    cur.execute(
      """
        SELECT work_id, doi, primary_pdf_url, best_pdf_url, other_pdf_urls
        FROM works
        WHERE download_attempted = 0
        ORDER BY work_id
        LIMIT ?
      """,
      (batch_size,),
    )
    rows = cur.fetchall()
    if not rows:
      break
    yield Batch(conn, rows)


def process():
  client = GrobidClient(timeout=10)
  client.process(
    service="processFulltextDocument", input_path="./data/pdfs", output="./data/teis", n=1
  )


def reset():
  conn = sqlite3.connect(DB_PATH)
  cur = conn.cursor()
  cur.execute("UPDATE works SET download_attempted=0")
  cur.execute("UPDATE pdfs SET processed=0")
  cur.execute("DROP TABLE works")
  conn.commit()
  conn.close()


def test():
  conn = sqlite3.connect(DB_PATH)
  write_metadata_to_index_db(conn, 50, 10)
  for _ in range(3):
    if batch_download_works(conn, 20):
      break


if __name__ == "__main__":
  #reset()
  test()
  # process()
