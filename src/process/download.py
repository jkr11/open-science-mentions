import asyncio
import time
import os
import aiohttp
import aiofiles
from pathlib import Path
from typing import Dict, List, Set, Optional
import hashlib
from selenium_driverless import webdriver
from selenium_driverless.types.options import Options
from fake_useragent import UserAgent
from database import DOWNLOAD_DIR_PDFS

from vpn import rotate_vpn_server


class PDFDownloader:
  def __init__(
    self,
    download_dir: str,
    switch_time: int = 600,
    allow_rotate: bool = True,
    headless: bool = False,
  ):
    self.download_dir = download_dir
    path = Path(self.download_dir)
    path.mkdir(parents=True, exist_ok=True)
    self.headless = headless
    self.time_since_last_init = time.time()
    self.switch_time = switch_time
    self.browser = None
    self.allow_rotate = allow_rotate

  async def __aenter__(self):
    await self._init_browser()
    return self

  async def __aexit__(self, exc_type, exc_value):
    if self.browser:
      try:
        await self.browser.quit()
        self.log("[*] Browser closed successfully.")
      except Exception as e:
        self.log(f"[x] Failed to close browser: {e}")

    if exc_type is not None:
      self.log(f"[x] Exception encountered: {exc_value}")

    return

  def log(self, msg: str) -> None:
    print(f"[{os.getpid()}] {msg}")

  async def _quit_browser(self):
    if self.browser:
      try:
        await self.browser.quit()
      except Exception as e:
        self.log(f"Exception when quitting browser: {e}")

  async def _restart_browser(self):
    if self.browser:
      await self._quit_browser()
    self._init_browser()

  async def _init_browser(self, geodata: Dict | None = None):
    options = Options()
    ua = UserAgent()
    random_user_agent = ua.random
    self.log(f"Initializing the browser with User-Agent: {random_user_agent}")

    options.add_argument(f"--user-agent={random_user_agent}")
    options.add_argument("--window-size=1920,1080")

    if self.headless:
      options.add_argument("--headless=new")

    profile = {
      "download.default_directory": self.download_dir,
      "plugins.always_open_pdf_externally": True,
      "download.prompt_for_download": False,
    }

    options.add_experimental_option("prefs", profile)
    self.browser = await webdriver.Chrome(options=options, timeout=20)

    await self.browser.execute_cdp_cmd(
      "Page.setDownloadBehavior",
      {"behavior": "allow", "downloadPath": self.download_dir},
    )

    if geodata:
      if "lat" in geodata and "lon" in geodata:
        await self.browser.execute_cdp_cmd(
          "Emulation.setGeolocationOverride",
          {"latitude": geodata["lat"], "longitude": geodata["lon"], "accuracy": 100},
        )
      if "timezone" in geodata:
        await self.browser.execute_cdp_cmd(
          "Emulation.setTimezoneOverride", {"timezoneId": geodata["timezone"]}
        )
    self.time_since_last_init = time.time()

  async def _get_current_ip_geo(self) -> Dict:
    try:
      async with aiohttp.ClientSession() as session:
        async with session.get("http://ip-api.com/json/") as resp:
          data = await resp.json()
          self.log(f"New Identity: {data.get('query')} in {data.get('country')}")
          return data
    except Exception as e:
      self.log(f"Failed to fetch IP geo: {e}")
      return {}

  async def rotate(self, reinit=True):
    if not reinit:
      rotate_vpn_server()
      await asyncio.sleep(1)
      self.time_since_last_init = time.time()
      return
    if not self.allow_rotate:
      self.log("Rotate disabled")
      return
    else:
      self.log("Triggering vpn rotation")
      if self.browser:
        try:
          await self.browser.quit()
        except Exception as e:
          self.log(f"Quitting browser failed: {e}")
        self.browser = None

      rotate_vpn_server()
      await asyncio.sleep(1)  # TODO

      geodata = await self._get_current_ip_geo()
      await self._init_browser(geodata)

  async def _wait_for_download(
    self, before_files: Set[str], timeout: int = 30
  ) -> Optional[str]:
    start_time = time.time()

    while time.time() - start_time < timeout:
      current_files = set(
        f
        for f in os.listdir(self.download_dir)
        if f.lower().endswith(".pdf") and not f.endswith(".crdownload")
      )

      new_files = current_files - before_files
      print(new_files)
      if new_files:
        return list(new_files)[0]

      await asyncio.sleep(0.5)

    return None

  def _hash(self, url: str) -> str:
    hashed_url = hashlib.sha256(url.encode()).hexdigest()
    return f"{hashed_url}.pdf"

  async def download_requests(self, url, filename=None) -> str | None:
    filename = os.path.join(self.download_dir, self._hash(url))
    try:
      async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
          response.raise_for_status()
          async with aiofiles.open(filename, "wb") as f:
            await f.write(await response.read())
          self.log(f"[*] SUCEESS: downloaded {url} using request.")
          return filename
    except Exception as e:
      print(f"[x] Error downloading PDF: {e} using requests")
      return None

  async def _wait_for_page_load(self, timeout=10):
    start = time.time()
    while time.time() - start < timeout:
      ready_state = await self.browser.execute_script("return document.readyState")
      if ready_state == "complete":
        return True
      await asyncio.sleep(0.2)
    return False

  async def download_browser(self, url: str) -> str | None:
    if not self.browser:
      self.log("Reiniting browser")
      await self._init_browser()

    before_files = set(
      f for f in os.listdir(self.download_dir) if f.lower().endswith(".pdf")
    )
    try:
      await self.browser.get(url)
      if not await self._wait_for_page_load(timeout=15):
        self.log(f"[x] Page load timeout for {url}")
        return None
      downloaded_file = await self._wait_for_download(before_files)
      if downloaded_file:
        self.log(f"[*] Success: {downloaded_file}")
        return downloaded_file
      else:
        self.log("[x] Failure: Timeout.")
        return None
    except Exception as e:
      self.log(f"Exception in download_browser: {e}")
      return None

  async def download(self, url: str) -> Optional[str]:
    if time.time() - self.time_since_last_init < self.switch_time:
      await self.rotate()

    filename = self._hash(url)
    result = await self.download_requests(url, filename)
    if result:
      return result
    self.log(f"Requests failed for {url}, trying browser fallback")
    return await self.download_browser(url)

  async def run_browser_batch(self, urls: List[str]) -> List[str]:
    downloaded_paths = []
    async with self:
      for url in urls:
        result = await self.download_browser(url)
        if result:
          downloaded_paths.append(result)
    return downloaded_paths

  async def run_batch(self, urls: List[str]) -> List[str]:
    downloaded_paths = []
    async with self:
      for url in urls:
        result = await self.download(url)
        if result:
          downloaded_paths.append(result)
    return downloaded_paths
