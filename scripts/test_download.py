from playwright.sync_api import sync_playwright, TimeoutError
import requests
doi = "10.1177/00222194241263646"
pdf_url = f"https://journals.sagepub.com/doi/pdf/{doi}"




def download_pdf_from_doi(doi: str) -> str | None:
    pdf_url = f"https://journals.sagepub.com/doi/pdf/{doi}"
    output_file = "output.pdf"

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=False,
            args=["--disable-blink-features=AutomationControlled"]
        )
        context = browser.new_context(
            accept_downloads=True,
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) "
                       "Chrome/122.0.0.0 Safari/537.36"
        )
        page = context.new_page()

        print(f"Navigating to PDF URL: {pdf_url}")
        page.goto(pdf_url, wait_until="networkidle")

        try:
            # Wait up to 30 seconds for the PDF response
            pdf_response = page.wait_for_response(
                lambda resp: resp.url == pdf_url and "application/pdf" in resp.headers.get("content-type", ""),
                timeout=30000
            )
            pdf_bytes = pdf_response.body()  # fully loaded PDF
            with open(output_file, "wb") as f:
                f.write(pdf_bytes)
            print(f"PDF successfully downloaded as {output_file}")

        except TimeoutError:
            print("PDF did not load in time or was blocked.")

        browser.close()
        return output_file


download_pdf_from_doi(doi)
