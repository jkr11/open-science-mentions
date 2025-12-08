# db/queries.py !TODO!

SELECT_WORK_BATCH = """
    SELECT work_id, doi, primary_pdf_url, best_pdf_url, other_pdf_urls
    FROM works
    WHERE download_attempted = 0
    ORDER BY work_id
    LIMIT ?
"""

MARK_DOWNLOAD_ATTEMPTED = """
    UPDATE works SET download_attempted = 1 WHERE work_id = ?
"""

INSERT_PDF_RECORD = """
    INSERT OR REPLACE INTO pdfs
    (work_id, pdf_sha256, pdf_path, pdf_url_used, downloaded_at, processed, deleted)
    VALUES (?, ?, ?, ?, ?, 0, 0)
"""

SELECT_UNPROCESSED_PDFS = """
    SELECT work_id, pdf_path
    FROM pdfs
    WHERE processed = 0 AND deleted = 0
"""

MARK_PDF_PROCESSED = """
    UPDATE pdfs SET processed = 1 WHERE work_id = ?
"""

SELECT_PDFS_BY_WORK_ID = """
    SELECT work_id, pdf_path
    FROM pdfs
    WHERE work_id IN ({})
"""

INSERT_TEXT_HITS = """
    INSERT OR REPLACE INTO pdf_text_hits
    (work_id, matched_keywords, matched_text, processed_at)
    VALUES (?, ?, ?, ?)
"""

MARK_PDF_PROCESSED = """
    UPDATE pdfs SET processed = 1, deleted = 1 WHERE work_id = ?
"""
