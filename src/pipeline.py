from database import DB_PATH, DOWNLOAD_DIR_PDFS, DOWNLOAD_DIR_TEIS
from fetch import extract_pdf_locations, get_journal_by_id
from process.download import PDFDownloader
from process.grobid import GrobidHandler
import vpn
from typing import Any
import sqlite3
import json
import asyncio
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from websockets.exceptions import ConnectionClosedError

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


from tqdm import tqdm


async def download_batch_by_journal_async_(
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
      pbar = tqdm(total=len(rows), desc=f"Journal: {journal_id}", unit="pdf")
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
              break
          pbar.update(1)
      pbar.close()
      return True

  except Exception as e:
    print(f"Exception when downloading batch: {e}")
    pbar.close()
    return False


async def download_batch_by_journal_async(
  journal_id: str, batch_size=20, switch_time=30, allow_rotate=True, which="PENDING"
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
          WHERE pdf_download_status = "{which}" 
            AND journal_id = "{journal_id.upper()}" 
          LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()

    if not rows:
      print("no rows")
      return False

    pbar = tqdm(total=len(rows), desc=f"Journal: {journal_id}", unit="pdf")

    async with downloader:
      for openalex_id, url_json in rows:
        urls = json.loads(url_json).get("pdf_links", [])
        urls = [u for u in urls if u is not None]

        final_path = None
        status_to_write = "FAILED"

        for url in urls:
          try:
            url = handle_url(url)
            final_path = await downloader.download(url)

            if final_path:
              status_to_write = "DONE"
              break

          except ConnectionClosedError as e:
            import os

            print(f"\n[FATAL] Browser connection lost: {e}")
            print("Terminating to cancel downloads. Restart the browser.")
            os._exit(1)
          except Exception as e:
            error_msg = str(e).lower()
            if "timeout" in error_msg:
              status_to_write = "TIMEOUT"
              print(f"\n[!] Timeout detected for {openalex_id}")
            else:
              print(f"\n[x] Error: {e}")

        with sqlite3.connect(DB_PATH) as conn:
          print(f"Writing to database: {status_to_write}")
          cursor = conn.cursor()
          cursor.execute(
            """
              UPDATE works
              SET pdf_local_path = ?, pdf_download_status = ?
              WHERE openalex_id = ?
            """,
            (final_path, status_to_write, openalex_id),
          )

        pbar.update(1)

    pbar.close()
    return True

  except Exception as e:
    print(f"\nCritical Batch Error: {e}")
    if "pbar" in locals():
      pbar.close()
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


def grobid_batch(
  journal_id: str,
  batch_size: int = 20,
  DDIRPDF: str = DOWNLOAD_DIR_PDFS,
  DDIRTEI: str = DOWNLOAD_DIR_TEIS,
) -> bool:
  grobid_handler = GrobidHandler()
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        f"""
          SELECT openalex_id, pdf_local_path FROM works 
          WHERE pdf_download_status = 'DONE' 
            AND tei_process_status = "PENDING"
            AND journal_id = "{journal_id.upper()}"
          LIMIT {batch_size}
        """
      )
      rows = cursor.fetchall()
      if len(rows) == 0:
        print("No rows")
        return False
      else:
        # print(rows)
        print(f"Handling {len(rows)} rows")
      ids, filenames = zip(*rows)
      try:
        output = grobid_handler.process_files(
          filenames, input_path=DDIRPDF, output_path=DDIRTEI
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


def transform_url_by_journal(journal_id: str):
  import re

  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute(
        "SELECT openalex_id, oa_urls FROM works WHERE journal_id = ?",
        (journal_id.upper(),),
      )
      rows = cursor.fetchall()

      if not rows:
        print("No rows found.")
        return False

      print(f"Handling {len(rows)} rows")

      updated_count = 0
      for openalex_id, oa_urls_raw in rows:
        if not oa_urls_raw:
          continue

        data = json.loads(oa_urls_raw)
        links = data.get("pdf_links", [])

        transformed_links = []
        changed = False

        for url in links:
          pattern = r"index\.php\?eID=download&id_artikel=(ART\d+)&uid=(\w+)"
          match = re.search(pattern, url)

          if match:
            art_id, uid = match.groups()
            new_url = (
              f"https://www.waxmann.com/shop/download?"
              f"tx_p2waxmann_download[action]=download&"
              f"tx_p2waxmann_download[controller]=Zeitschrift&"
              f"tx_p2waxmann_download[id_artikel]={art_id}&"
              f"tx_p2waxmann_download[uid]={uid}"
            )
            transformed_links.append(new_url)
            changed = True
          else:
            transformed_links.append(url)

        if changed:
          data["pdf_links"] = transformed_links
          cursor.execute(
            "UPDATE works SET oa_urls = ? WHERE openalex_id = ?",
            (json.dumps(data), openalex_id),
          )
          updated_count += 1

      conn.commit()
      print(f"Successfully updated {updated_count} records.")
      return True

  except Exception as e:
    print(f"An error occurred: {e}")
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

ED_JOURNALS = [
  "S2738008561",  # mdpi
  "S2596526815",  # frontiers
  "S166722454",  # Springer # TODO: fix FAILED ones
  "S40639335",  # Zeitschrift für Erziehungswissenschaften (Springer)
  "S4210217710",  # Deutsche Schule
  "S63113783",  # Zeitschrift für Pädagogik
]


async def main(id: int):
  for journal in ED_JOURNALS[2:]:
    print(journal)
  while True:
    succ = await download_batch_by_journal_async(
      ED_JOURNALS[id], 1000, 100, True, which="TIMEOUT"
    )
    if not succ:
      break


if __name__ == "__main__":
  N = 5
  # vpn.rotate_vpn_server()
  # for work in get_journal_by_id(ED_JOURNALS[N], 20, 2016):
  #  insert_work_metadata_sql(work)

  # transform_url_by_journal(ED_JOURNALS[N])

  while grobid_batch(ED_JOURNALS[N], 40, DOWNLOAD_DIR_PDFS+"/test/", DOWNLOAD_DIR_TEIS+"/ed/"): ...
  # asyncio.run(main(N))
