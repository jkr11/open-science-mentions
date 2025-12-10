from database import DB_PATH, DOWNLOAD_DIR_PDFS
from fetch import extract_pdf_locations, get_journal_by_id
from process.download import PDFDownloader
from typing import Any
import sqlite3
import json
import asyncio
from tqdm import tqdm

PSYCH_JOURNALS = ["s9692511", "s27228949"]


def insert_work_metadata_sql(work: dict[str, Any]) -> None:
  """Inserts a single OpenAlex work's core metadata into the database."""
  pdf_locations = extract_pdf_locations(work)

  primary_loc = work.get("primary_location", {})
  source_info = primary_loc.get("source", {})
  journal_id = source_info.get("id")
  journal_name = source_info.get("display_name")
  print(f"Inserting: {work['doi']}")
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()

      cursor.execute(
        """
        INSERT INTO works (
          openalex_id, journal_id, journal_name, doi, publication_year, oa_urls
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(openalex_id) DO UPDATE SET
          journal_id = excluded.journal_id,
          journal_name = excluded.journal_name,
          doi = excluded.doi,
          publication_year = excluded.publication_year,
          oa_urls = excluded.oa_urls;
        """,
        (
          work.get("id", "N/A").split("/")[-1],
          journal_name,
          journal_id.split("/")[-1],
          work.get("doi", "N/A"),
          work.get("publication_year"),
          json.dumps(pdf_locations),
        ),
      )

  except sqlite3.Error as e:
    print(f"Database error during insert: {e}")


def download_batch(batch_size=20, switch_time=600) -> None:
  downloader = PDFDownloader(DOWNLOAD_DIR_PDFS, switch_time=switch_time)
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, oa_urls FROM works WHERE pdf_download_status = "PENDING" LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      print(len(rows))
      for id, url_json in tqdm(rows, desc="Downloading PDFs", unit=False):
        url = json.loads(url_json)["pdf_links"][0]
        path = asyncio.run(downloader.download(url))
        if path is not None:
          cursor.execute(
            """
              UPDATE works
              SET pdf_local_path = ?, pdf_download_status = 'DONE'
              WHERE openalex_id = ?
            """,
            (path, id),
          )
  except Exception as e:
    print(f"Exception when downloading batch: {e}")


N = 100

if __name__ == "__main__":
  # i = 0
  # for work in get_journal_by_id(PSYCH_JOURNALS[0], 200, 2020):
  #  if i >= N:
  #    break
  #  insert_work_metadata_sql(work)
  download_batch(100)
