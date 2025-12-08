import asyncio
import time
import os
import sys
from pathlib import Path
from selenium_driverless import webdriver
from selenium_driverless.types.options import Options
import aiohttp
import aiofiles
from pypdf import PdfReader
from pypdf.errors import PdfReadError
import re
from fake_useragent import UserAgent
from cdp_socket.exceptions import SocketExcitedError # Added for robustness
# Assuming 'vpn' module and 'rotate_vpn_server' function exist
# If not available, you must remove or mock the 'vpn' import and calls
try:
    from vpn import rotate_vpn_server
except ImportError:
    print("Warning: 'vpn' module not found. VPN rotation features are disabled.")
    def rotate_vpn_server():
        print("Mock VPN rotation executed.")


activate_rotate_vpn = False
last_vpn_rotation = time.time()
browser = None
current_page_url = None

# --- Configuration ---
# Load Download Dir from a text file (as in your original script)
script_dir = Path(__file__).parent
file_path = script_dir / "sel_download_dir.txt"
try:
    with file_path.open("r") as f:
        DOWNLOAD_DIR = f.read().strip()
    if not os.path.isdir(DOWNLOAD_DIR):
        print(f"Error: Download directory not found at {DOWNLOAD_DIR}")
        sys.exit(1)
except FileNotFoundError:
    print(f"Error: sel_download_dir.txt not found in {script_dir}")
    sys.exit(1)

# Selenium Options
options = Options()
# Removed options.add_argument("--headless") for GUI debugging

prefs = {"download.default_directory": DOWNLOAD_DIR, "plugins.always_open_pdf_externally": True}
options.add_experimental_option("prefs", prefs)
# ---------------------

def create_doi_url(doi: str) -> str:
    """Creates a resolver URL for the given DOI."""
    return f"https://doi.org/{doi}"

async def init_browser():
    """Initializes or reinitializes the browser and confirms it's responsive."""
    global browser, last_vpn_rotation, activate_rotate_vpn

    if browser:
        try:
            await browser.quit(timeout=15) # Increased timeout for quit
        except (SocketExcitedError, TimeoutError, Exception) as e:
            print(f"Warning: Previous browser quit failed gracefully: {e}")
        finally:
            browser = None

    if activate_rotate_vpn:
        print("Rotating VPN server...")
        rotate_vpn_server()
    
    try:
        ua = UserAgent()
        options.add_argument(f"--user-agent={ua.random}")
        # Increased cdp_timeout to 30 seconds for stability
        browser = await webdriver.Chrome(options=options, timeout=30) 
        
        
        print("Browser initialized and connection verified.")
        last_vpn_rotation = time.time()
        return True
    
    except Exception as e:
        print(f"Error initializing or verifying browser connection: {e}")
        return False

# --- Core Utility Functions ---

async def is_captcha_triggered():
    """
    Check if a CAPTCHA is actively present and visible on the page.
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

    # Method 3: Check for a Cloudflare CAPTCHA indicator.
    try:
        cloudflare_input = await browser.find_element("css", "input[name='cf_captcha_kind']")
        if cloudflare_input:
            parent = await browser.execute_script("return arguments[0].parentElement;", cloudflare_input)
            if parent:
                rect = await browser.execute_script("return arguments[0].getBoundingClientRect();", parent)
                if rect and rect.get("width", 0) > 0 and rect.get("height", 0) > 0:
                    return True
    except Exception:
        pass

    return False

async def download_pdf_via_requests(pdf_url, doi_filename):
    """Download the PDF file using aiohttp."""
    filename = os.path.join(DOWNLOAD_DIR, f"{doi_filename}.pdf")
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(pdf_url) as response:
                if response.status == 200:
                    async with aiofiles.open(filename, "wb") as f:
                        await f.write(await response.read())
                    print(f"PDF downloaded successfully: {filename}")
                    return filename
                else:
                    print(f"Failed to download PDF: HTTP {response.status}")
    except Exception as e:
        print(f"Error downloading PDF: {e}")
    return None

async def force_pdf_download(doi_filename: str, url: str):
    """
    Attempt to fetch the PDF URL from the page and download it.
    """
    global current_page_url

    if "https://annas-archive.org/search" in current_page_url:
        print("Not found on Anna's Archive (Search Page)")
        return "SKIP_REST"

    try:
        # Find an anchor element that might be a download button.
        xpath_expr = (
            "//a["
            "contains(@href, 'pdf') or "
            "contains(text(), 'Download') or "
            "contains(text(), 'PDF') or "
            "contains(text(), 'Download PDF') or "
            "contains(text(), 'VIEW PDF') or "
            "contains(@title, 'PDF') or "
            "contains(@aria-label, 'PDF')"
            "]"
        )
        download_button = await browser.find_element("xpath", xpath_expr)

        if download_button:
            print(f"Download button found.")
            pdf_url = await download_button.get_attribute("href")
            if pdf_url:
                print(f"Found PDF link: {pdf_url}")

                # If the current URL is a DOI resolver, extract the DOI and rewrite the PDF link.
                if "dx.doi.org" in url:
                    start_index = url.find("dx.doi.org/") + len("dx.doi.org/")
                    end_index = url.find("&", start_index)
                    doi = url[start_index:end_index] if end_index != -1 else url[start_index:]
                    print(f"Extracted DOI from resolver: {doi}")

                    if "onlinelibrary.wiley.com" in current_page_url:
                        parts = current_page_url.split("/doi/")
                        if len(parts) > 1:
                            base = parts[0] + "/doi/"
                            pdf_url = base + "pdfdirect/" + doi
                        else:
                            pdf_url = "https://onlinelibrary.wiley.com/doi/pdfdirect/" + doi
                    elif "journals.sagepub.com" in current_page_url:
                        pdf_url = "https://journals.sagepub.com/doi/pdf/" + doi
                    elif "link.springer.com" in current_page_url:
                        pdf_url = "https://link.springer.com/content/pdf/" + doi
                    elif "science.org" in current_page_url:
                        pdf_url = "https://www.science.org/doi/pdf/" + doi
                    elif "tandfonline.com" in current_page_url:
                        pdf_url = "https://www.tandfonline.com/doi/pdf/" + doi
                    elif "pnas.org" in current_page_url:
                        pdf_url = "https://www.pnas.org/doi/pdf/" + doi
                    elif "dx.doi.org" in current_page_url:
                        print("DOI cannot be resolved.")
                        return "DOI_NOT_RESOLVED"
                    print(f"Rewritten PDF URL: {pdf_url}")
                elif "annas-archive.org/scidb" in url:
                    print("Anna's Archive scidb page detected, attempting direct download.")
                    try:
                        # If aiohttp succeeds, the function returns the filename, not True
                        result = await download_pdf_via_requests(pdf_url, doi_filename)
                        return result if result else False
                    except Exception as req_e:
                        print(f"Download via requests failed: {req_e}. Attempting to navigate.")

                try:
                    await browser.get(pdf_url)
                    return True
                except Exception as nav_e:
                    print(f"Fallback navigation failed: {nav_e}")
        else:
            print("No explicit download buttons found.")
    except Exception as e:
        print(f"Error finding PDF link: {e}")
    return False

async def wait_for_download(before_files, timeout=20):
    """Wait for a new PDF file to appear in the download directory."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        after_files = set(
            [file for file in os.listdir(DOWNLOAD_DIR) if file.lower().endswith(".pdf")]
        )
        new_files = after_files - before_files
        if new_files:
            print("New PDF file found.")
            return list(new_files)[0]
        await asyncio.sleep(0.5)
    return None

async def wait_for_page_load(timeout=10, stabilization_duration=1.0, check_interval=0.5):
    """
    Wait until the page is fully loaded and its DOM becomes stable.
    """
    start_time = time.time()
    stable_start = None
    previous_length = None

    while time.time() - start_time < timeout:
        state = await browser.execute_script("return document.readyState")
        if state == "complete":
            current_length = len(await browser.execute_script("return document.body.innerHTML"))
            if previous_length is not None and current_length == previous_length:
                if stable_start is None:
                    stable_start = time.time()
                elif time.time() - stable_start >= stabilization_duration:
                    print("Page fully loaded and stable.")
                    return True
            else:
                stable_start = None
            previous_length = current_length
        await asyncio.sleep(check_interval)
    return False

# --- Main Execution Function ---

async def execute_download(doi: str):
    """
    Executes the PDF download for a single DOI.
    """
    global last_vpn_rotation, current_page_url, activate_rotate_vpn

    doi_filename = doi.replace("/", "_")
    url = create_doi_url(doi)

    print(f"--- Starting Download for DOI: {doi} ---")
    print(f"Initial URL: {url}")

    # Check and Initialize/Rotate Browser
    if not browser or time.time() - last_vpn_rotation > 600:
        # If browser is None OR 10 minutes have passed, initialize/re-initialize
        if not await init_browser():
            print("Status: Failed - Could not initialize browser.")
            return

    try:
        before_files = set(os.listdir(DOWNLOAD_DIR))
        
        print(f"Navigating to target URL: {url}")
        await browser.get(url) 

        if not await wait_for_page_load():
            print("Status: Failed - Page load timeout")
            return

        current_page_url = await browser.current_url
        print(f"Current Page URL: {current_page_url}")

        if await is_captcha_triggered():
            print("Status: Failed - CAPTCHA detected.")
            if activate_rotate_vpn:
                await init_browser() # init_browser handles the rotation
            return

        force_dl_status = await force_pdf_download(doi_filename, url)
        if force_dl_status == "SKIP_REST":
            print("Status: Failed - Explicit Skip Requested (e.g., not found on archive)")
            return
        elif force_dl_status == "DOI_NOT_RESOLVED":
            print("Status: Failed - DOI Not Resolved")
            return
        elif isinstance(force_dl_status, str) and force_dl_status.endswith(".pdf"):
            # Handle success from download_pdf_via_requests via Anna's Archive
            new_path = os.path.join(DOWNLOAD_DIR, f"{doi_filename}.pdf")
            print(f"Status: Download successful via requests! File saved as {doi_filename}.pdf")
            try:
                PdfReader(new_path)
            except PdfReadError:
                print(f"Failed: Invalid PDF file: {doi_filename}.pdf (Deleting corrupted file)")
                os.remove(new_path)
            return
        elif force_dl_status is True:
            # The browser navigated to a new URL (the PDF link), reset file check
            before_files = set(os.listdir(DOWNLOAD_DIR))
            
        print("Waiting for file download...")
        downloaded_file = await wait_for_download(before_files)

        if not downloaded_file:
            print("Status: Failed - Download timeout or file not found")
            return

        # Rename and Verify
        original_path = os.path.join(DOWNLOAD_DIR, downloaded_file)
        new_path = os.path.join(DOWNLOAD_DIR, f"{doi_filename}.pdf")

        os.rename(original_path, new_path)
        print(f"Renamed downloaded file: {downloaded_file} → {doi_filename}.pdf")

        try:
            PdfReader(new_path)
            print(f"Status: Download successful! File saved as {doi_filename}.pdf")
        except PdfReadError:
            print(f"Status: Failed - Invalid PDF file: {doi_filename}.pdf (Deleting corrupted file)")
            os.remove(new_path)

    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    finally:
        print(f"--- Finished Download for DOI: {doi} ---")


# --- Main Block for Command Line Execution ---
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python your_script_name.py <DOI>")
        print("Example: python your_script_name.py 10.1007/s10902-024-00627-7")
        sys.exit(1)

    doi_to_download = sys.argv[1]
    
    # Initialize and Execute
    try:
        # Run init_browser once before main execution
        if not asyncio.run(init_browser()):
             sys.exit(1)

        # Execute the download process
        asyncio.run(execute_download(doi_to_download))
        
    except Exception as e:
        print(f"Critical execution error: {e}")
    finally:
        # Clean up the browser instance after the process is complete
        if browser:
            try:
                # Use a larger timeout to prevent the SocketExcitedError during shutdown
                asyncio.run(browser.quit(timeout=15)) 
            except (SocketExcitedError, TimeoutError, Exception) as e:
                print(f"Warning: Browser quit failed gracefully: {e}")