from database import DB_PATH, DOWNLOAD_DIR_PDFS, DOWNLOAD_DIR_TEIS
from fetch import extract_pdf_locations, get_journal_by_id
from process.download import PDFDownloader
from process.grobid import GrobidHandler
from typing import Any
import sqlite3
import json
import asyncio
from pypdf import PdfReader
from pypdf.errors import PdfReadError

PSYCH_JOURNALS = ["s9692511", "s27228949"]


def insert_work_metadata_sql(work: dict[str, Any]) -> None:
  """Inserts a single OpenAlex work's core metadata into the database."""
  pdf_locations = extract_pdf_locations(work)

  primary_loc = work.get("primary_location", {})
  source_info = primary_loc.get("source", {})
  journal_id = source_info.get("id")
  journal_name = source_info.get("display_name")
  print(f"Inserting: {work['doi']} with {journal_id.split('/')[-1]}")
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
          journal_id.split("/")[-1],
          journal_name,
          work.get("doi", "N/A"),
          work.get("publication_year"),
          json.dumps(pdf_locations),
        ),
      )

  except sqlite3.Error as e:
    print(f"Database error during insert: {e}")


def handle_url(url: str):
  if "www.tandfonline.com" in url:
    url = url.replace("/epdf/", "/pdf/")
  return url


async def download_batch_by_journal_async(
  journal_id: str, batch_size=20, switch_time=30, allow_rotate=False
) -> bool:
  downloader = PDFDownloader(
    DOWNLOAD_DIR_PDFS + "/test/",
    allow_rotate=allow_rotate,
    switch_time=switch_time,
    headless=False,
  )

  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, oa_urls 
          FROM works 
          WHERE pdf_download_status = "PENDING" 
            AND journal_id = "{journal_id.upper()}" 
          LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      if not rows:
        return False

      async with downloader:
        for openalex_id, url_json in rows:
          urls = json.loads(url_json)["pdf_links"]
          urls = [u for u in urls if u is not None]
          for url in urls:
            path = None
            if url is not None:
              url = handle_url(url)
              path = await downloader.download_browser(url)
            if path:
              with sqlite3.connect(DB_PATH) as conn:
                cursor = conn.cursor()
                cursor.execute(
                  """
                    UPDATE works
                    SET pdf_local_path = ?, pdf_download_status = 'DONE'
                    WHERE openalex_id = ?
                  """,
                  (path, openalex_id),
                )
      return True

  except Exception as e:
    print(f"Exception when downloading batch: {e}")
    return False


def download_batch_by_journal(
  id: str, batch_size=20, switch_time=30, allow_rotate=False
) -> bool:
  downloader = PDFDownloader(
    DOWNLOAD_DIR_PDFS + "/test/",
    allow_rotate=allow_rotate,
    switch_time=switch_time,
    headless=False,
  )
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, oa_urls FROM works WHERE pdf_download_status = "PENDING" AND journal_id = "{id.upper()}" LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      if len(rows) == 0:
        return False
      for id, url_json in rows:
        url = json.loads(url_json)["pdf_links"][0]
        path = asyncio.run(downloader.download_browser(url))
        if path is not None:
          cursor.execute(
            """
              UPDATE works
              SET pdf_local_path = ?, pdf_download_status = 'DONE'
              WHERE openalex_id = ?
            """,
            (path, id),
          )
      return True
  except Exception as e:
    print(f"Exception when downloading batch: {e}")
    return False


def download_batch(batch_size=20, switch_time=30, allow_rotate=True) -> bool:
  downloader = PDFDownloader(
    DOWNLOAD_DIR_PDFS, allow_rotate=allow_rotate, switch_time=switch_time
  )
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, oa_urls FROM works WHERE pdf_download_status = "PENDING" LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      if len(rows) == 0:
        return False
      for id, url_json in rows:
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
      return True
  except Exception as e:
    print(f"Exception when downloading batch: {e}")
    return False


def grobid_batch(batch_size=20) -> bool:
  grobid_handler = GrobidHandler()
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, pdf_local_path FROM works WHERE pdf_download_status = 'DONE' AND tei_process_status = "PENDING" LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      if len(rows) == 0:
        return False
      ids, filenames = zip(*rows)
      try:
        output = grobid_handler.process_files(
          filenames, input_path=DOWNLOAD_DIR_PDFS, output_path=DOWNLOAD_DIR_TEIS
        )
      except Exception as e:
        print(f"Error when processing files with grobid:  {e}")

      for pdf, tei in output.items():
        cursor.execute(
          """
            UPDATE works
            SET tei_local_path = ?,
                tei_process_status = 'DONE'
            WHERE pdf_local_path = ?
          """,
          (tei, pdf),
        )
    return True

  except Exception as e:
    print(f"Exception when batch processing with grobid: {e}")
    return False


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


async def main():
  while True:
    succ = await download_batch_by_journal_async(SPED_JOURNALS[1], 100, 30, False)
    if not succ:
      break


if __name__ == "__main__":
  # for work in get_journal_by_id(SPED_JOURNALS[1], 20, 2010):
  #   insert_work_metadata_sql(work)

  asyncio.run(main())
  # print(handle_url("https://www.tandfonline.com/doi/epdf/10.1080/13603116.2023.2190750?needAccess=true&role=button"))
  # process_dir(DOWNLOAD_DIR_PDFS, DOWNLOAD_DIR_TEIS)
