import subprocess
import random
import time
# import asyncio

SERVER_POOL = [("us", "nyc"), ("de", "fra"), ("se", "sto"), ("nl", "ams")]
# only ("de", "dus") works for sage, so reserve it for that.
# Do we need to add more vpns?

# TODO: is browser location/timezone important for this?

def rotate_vpn_server():
  try:
    country, city = random.choice(SERVER_POOL)
    print(f"--- Attempting rotation to new server: {country} {city} ---")
    subprocess.run(["mullvad", "disconnect"], capture_output=True, text=True)

    subprocess.run(
      ["mullvad", "relay", "set", "location", country, city],
      check=True,
      capture_output=True,
      text=True,
    )

    subprocess.run(["mullvad", "connect"], capture_output=True, text=True)

    subprocess.run(
      ["mullvad", "connect"],
      check=True,
      capture_output=True,
      text=True,
    )
    time.sleep(1)  # TODO check, for now it is always enough

    status_check = subprocess.run(
      ["mullvad", "status"], check=True, capture_output=True, text=True
  ).stdout
    print(status_check)
    print("-" * 50)
    return True
  except subprocess.CalledProcessError as e:
    print("\n Subprocess ERROR during rotation")
    print(f"Command failed: {e.cmd}")
    print(f"Return code: {e.returncode}")
    print(f"Error output (stderr):\n{e.stderr.strip()}")
    print("-" * 50)
    pass


#
#
# import os
# import glob
#
#
# async def wait_for_download_complete(download_dir: str, timeout: int = 60) -> bool:
#   start_time = asyncio.get_event_loop().time()
#
#   while asyncio.get_event_loop().time() - start_time < timeout:
#     temp_files = glob.glob(os.path.join(download_dir, "*.crdownload"))
#
#     if not temp_files:
#       final_files = glob.glob(os.path.join(download_dir, "*.pdf"))
#       if final_files:
#         return True
#
#     await asyncio.sleep(0.5)
#
#   raise TimeoutError("PDF download timed out.")
#
#
# import aiohttp
# import os
#
#
# async def download_pdf_requests(url, filename):
#   print(f"[{os.getpid()}] Attempting aiohttp download for: {url}")
#   async with aiohttp.ClientSession() as session:
#     try:
#       async with session.get(url, timeout=30) as response:
#         response.raise_for_status()
#         if "application/pdf" not in response.headers.get("Content-Type", "").lower():
#           print("Error: url does not point to a pdf (Content-Type missmatch).")
#           return False
#         with open(filename, "wb") as f:
#           async for chunk in response.content.iter_chunked(8192):
#             f.write(chunk)
#         print(f"[{os.getpid}] aiohttp Download successfull. Saved to {filename}")
#         return True
#     except aiohttp.ClientError as e:
#       print(f"[{os.getpid}] aiohttp Client Error: {e}")
#       return False
#     except Exception as e:
#       print(f"[{os.getpid}] An unexcpected error occured: {e}")
#       return False
#
# from playwright.async_api import async_playwright, Browser, Download, Page
#
# async def download_pdf_browser(url, filename, browser : Browser) -> str:
#   page : Page = await browser.new_page()
#   try:
#     print(f"[{os.getpid()}] Starting browser navigation to: {url}")
#     async with page.expect_download() as download_info:
#       await page.goto(url, wait_until="load", timeout=60000)
#     download : Download = await download_info.value
#     await download.save_as(filename)
#     file_size_bytes = os.path.getsize(filename)
#     print(f"[{os.getpid()}] Download successful! Saved to {filename} ({file_size_bytes} bytes).")
#     return f"Success: Downloaded {file_size_bytes} bytes."
#   except Exception as e:
#     print(f"[{os.getpid()}] An error occurred during browser navigation or download: {e}")
#     if os.path.exists(filename):
#              os.remove(filename)
#     return f"Error: {e}"
#   finally:
#         await page.close()
#
# async def download_handler(browser, pdf_url, download_dir="test", name="test.pdf") -> bool:
#   print(f"Attempting to download pdf at {pdf_url}")
#   try:
#     await browser.get(pdf_url)
#     await wait_for_download_complete(download_dir)
#     return True
#   except Exception as e:
#     print(f"Download failed: error {e}")
#     return False
#
#
# async def main():
#   rotate_vpn_server()
#   link = "https://journals.sagepub.com/doi/pdf/10.1177/01626434251372933"
#   async with async_playwright() as p:
#     browser : Browser = await p.chromium.launch()
#     final_status = await download_pdf_browser( link, "test.pdf",  browser)
#     print(f"Final Operation Status: {final_status}")
#     await browser.close()
