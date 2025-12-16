import asyncio
import time
import os
from pathlib import Path
from selenium_driverless import webdriver
from selenium_driverless.types.options import Options
from fake_useragent import UserAgent
from vpn import rotate_vpn_server

DOWNLOAD_DIR = "/home/jkr/work/open-science/open-science/testdata/pdfs"

Path(DOWNLOAD_DIR).mkdir(parents=True, exist_ok=True)
test_pdf_url = "https://journals.sagepub.com/doi/pdf/10.1177/01626434251372933"


def aprint(msg: str) -> None:
  print(f"[{os.getpid()}] {msg}")


async def is_captcha_triggered(browser):
  """
  Check if a CAPTCHA is actively present and visible on the page.

  This function attempts to locate common CAPTCHA elements (e.g. reCAPTCHA widgets or Cloudflare CAPTCHA)
  and then verifies that they are visible by examining their bounding rectangle dimensions.

  Returns:
      bool: True if a CAPTCHA is visibly active, False otherwise.
  """
  # Method 1: Look for a visible reCAPTCHA element.
  try:
    captcha_element = await browser.find_element("css", ".g-recaptcha")
    if captcha_element:
      rect = await browser.execute_script(
        "return arguments[0].getBoundingClientRect();", captcha_element
      )
      if rect and rect.get("width", 0) > 0 and rect.get("height", 0) > 0:
        return True
  except Exception:
    pass

  # Method 2: Look for a visible reCAPTCHA iframe.
  try:
    recaptcha_iframe = await browser.find_element(
      "xpath", "//iframe[contains(@src, 'recaptcha/api2/anchor')]"
    )
    if recaptcha_iframe:
      rect = await browser.execute_script(
        "return arguments[0].getBoundingClientRect();", recaptcha_iframe
      )
      if rect and rect.get("width", 0) > 0 and rect.get("height", 0) > 0:
        return True
  except Exception:
    pass


async def wait_for_download(before_files: set, timeout=30) -> str | None:
  aprint("Starting download monitoring")
  start_time = time.time()

  while time.time() - start_time < timeout:
    current_files = set(
      [
        file
        for file in os.listdir(DOWNLOAD_DIR)
        if file.lower().endswith(".pdf") and not file.endswith(".crdownload")
      ]
    )

    new_files = current_files - before_files

    if new_files:
      return list(new_files)[0]

    await asyncio.sleep(0.5)

  return None


async def run_pdf_download_test(url : str):
  browser = None

  options = Options()

  ua = UserAgent()
  random_user_agent = ua.random
  aprint(f"Using User-Agent: {random_user_agent}")
  options.add_argument(f"--user-agent={random_user_agent}")
  options.add_argument("--window-size=1920,1080")

  prefs = {
    "download.default_directory": DOWNLOAD_DIR,
    "plugins.always_open_pdf_externally": False,
    "download.prompt_for_download": False,
    "download.extensions_to_open": "applications/pdf",

  }
  options.add_experimental_option("prefs", prefs)

  try:
    aprint("Starting asynchronous browser...")
    browser = await webdriver.Chrome(options=options, timeout=20)

    await browser.execute_cdp_cmd(
      "Page.setDownloadBehavior", {"behavior": "allow", "downloadPath": DOWNLOAD_DIR}
    )

    before_files = set(
      [file for file in os.listdir(DOWNLOAD_DIR) if file.lower().endswith(".pdf")]
    )
    aprint(f"Monitoring directory: {DOWNLOAD_DIR}")

    aprint(f"Navigating directly to PDF URL: {test_pdf_url}")
    await browser.get(test_pdf_url)

    #if await is_captcha_triggered(browser):
    #  rotate_vpn_server()

    downloaded_file = await wait_for_download(before_files)

    if downloaded_file:
      aprint(f"\nSUCCESS: Downloaded file found: {downloaded_file}")
    else:
      aprint("\nFAILURE: Download timed out or file not found.")

  except Exception as e:
    aprint(f"\nAn error occurred during the session: {e}")

  finally:
    if browser:
      aprint("Closing browser...")
      try:
        await browser.quit(timeout=10)
      except Exception as e:
        aprint(f"Warning: Browser quit failed gracefully: {e}")
    aprint("Script finished.")


if __name__ == "__main__":
  asyncio.run(run_pdf_download_test(test_pdf_url))
