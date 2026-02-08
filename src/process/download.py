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
import uuid
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from vpn import rotate_vpn_server

G = "\033[92m"
RESET = "\033[0m"
R = "\033[91m"
Y = "\033[93m"


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
    self.tmpdir = os.path.join(self.download_dir, ".tmp")
    Path(self.tmpdir).mkdir(parents=True, exist_ok=True)
    self.headless = headless
    self.time_since_last_init = time.time()
    self.switch_time = switch_time
    self.browser = None
    self.allow_rotate = allow_rotate

  async def __aenter__(self):
    await self._init_browser()
    return self

  async def __aexit__(self, exc_type, exc_value, _):
    if self.browser:
      try:
        await self.browser.quit()
        self.log("Browser closed successfully.")
      except Exception as e:
        self.log(f"Failed to close browser: {e}")

    if exc_type is not None:
      self.log(f"Exception encountered: {exc_value}")

    return

  def log(self, msg: str, COL=RESET) -> None:
    print(f"[{os.getpid()}] {COL}{msg}{RESET}")

  async def _quit_browser(self):
    if self.browser:
      try:
        await self.browser.quit()
      except Exception as e:
        self.log(f"Exception when quitting browser: {e}")

  async def _restart_browser(self):
    if self.browser:
      await self._quit_browser()
    await self._init_browser()

  async def _init_browser(self, geodata: Dict | None = None):
    options = Options()
    ua = UserAgent()
    random_user_agent = ua.random
    self.log(f"Initializing the browser with User-Agent: {random_user_agent}")

    options.add_argument(f"--user-agent={random_user_agent}")
    options.add_argument("--window-size=1920,1080")

    if self.headless:
      options.add_argument("--headless=new")

    print(f"INIT download_dir temporary is: {self.tmpdir}")
    # fix autodownload: chrome://settings/content/pdfDocuments
    profile = {
      "download.default_directory": self.tmpdir,
      "plugins.always_open_pdf_externally": True,
      "download.prompt_for_download": False,
    }

    options.add_experimental_option("prefs", profile)
    self.browser = await webdriver.Chrome(options=options, timeout=20)

    await self.browser.execute_cdp_cmd(
      "Page.setDownloadBehavior",
      {"behavior": "allow", "downloadPath": self.tmpdir},
    )

    await self.browser.switch_to.new_window(
      "tab",
      url="chrome://settings/content/pdfDocuments",
      activate=True,
      background=True,
    )
    await asyncio.sleep(10)

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
    # self.rotate(reinit=False)
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
      self.log("Rotating without reinit")
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
    self, before_files: Set[str], timeout: int = 5
  ) -> Optional[str]:
    start_time = time.time()

    while time.time() - start_time < timeout:
      try:
        current_files = set(
          f
          for f in os.listdir(self.tmpdir)
          if f.lower().endswith(".pdf") and not f.endswith(".crdownload")
        )

        new_files = current_files - before_files
        # print(new_files)
        if new_files:
          return list(new_files)[0]

        await asyncio.sleep(0.5)
      except Exception as e:
        self.log(f"Exception when waiting for file: {e}")
        return list()
    return None

  def _finalize_download(self, tmppath: str, url: str) -> str | None:
    final_name = self._hash(url)
    final_path = os.path.join(self.download_dir, final_name)
    # try:
    #  PdfReader(tmppath)
    # except PdfReadError:
    #  print("Invalid pdf, deleting")
    #  os.remove(tmppath)
    #  return None
    os.replace(tmppath, final_path)
    self.log(f"Finalized download -> {final_name}")
    return final_path

  def _hash(self, url: str) -> str:
    hashed_url = hashlib.sha256(url.encode()).hexdigest()
    return f"{hashed_url}.pdf"

  async def download_requests(self, url, filename=None) -> str | None:
    tmp_path = os.path.join(self.tmpdir, f"{uuid.uuid4().hex}.pdf")
    try:
      async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
          response.raise_for_status()
          async with aiofiles.open(tmp_path, "wb") as f:
            await f.write(await response.read())
          self.log(f"[*] SUCCESS: downloaded {url} using request.")
          return self._finalize_download(tmppath=tmp_path, url=url)

    except Exception as e:
      print(f"[x] Error downloading PDF: {e} using requests")
      if os.path.exists(tmp_path):
        os.remove(tmp_path)
      return None

  async def _wait_for_page_load(self, timeout=10):
    start = time.time()
    while (time.time() - start) < timeout:
      ready_state = await self.browser.execute_script("return document.readyState")
      if ready_state == "complete":
        return True
      await asyncio.sleep(0.2)
    return False

  async def is_institution_login_available(self) -> bool:
    # Springer only for now
    try:
        await self.browser.find_element("css selector", "[data-test='access-via-institution']")
        return True
    except Exception as _:
        return False


  async def download_browser(self, url: str) -> str | None:
    ctime = time.time() - self.time_since_last_init
    print(f"Time: {ctime}/{self.switch_time}")
    if ctime > self.switch_time:
      await self.rotate(reinit=False)
    print(f"Handling URL: {url}")
    if not self.browser:
      self.log("Reiniting browser")
      await self._init_browser()
    assert self.browser is not None
    tab = await self.browser.new_window(type_hint="tab", activate=False)

    try:
      before_files = set()
      if self.tmpdir:
        before_files = set(
          f for f in os.listdir(self.tmpdir) if f.lower().endswith(".pdf")
        )
      # await tab.get(url, wait_load=True)
      await self.browser.get(url)


      # if await self.browser.current_url != url:
      #   # Redirect
      #   print(f"Redirect to: {await self.browser.current_url}")
      #   if await self.is_institution_login_available():
      #     raise Exception("Institutional login")
      if not await self._wait_for_page_load(timeout=5):
        self.log(f"[x] Page load timeout for {url}", R)
        return None
        raise Exception("Timeoout when loading page")
        
      downloaded_file = await self._wait_for_download(before_files, timeout=10)

      if downloaded_file:
        self.log(f"[*] Success: {downloaded_file}", G)
        tmppath = os.path.join(self.tmpdir, downloaded_file)
        return self._finalize_download(tmppath, url)
      else:
        self.log("[x] Failure: Timeout.", Y)
        raise Exception("[x] Failure: Timeout.")
    except Exception as e:
      self.log(f"Exception in download_browser: {e}", R)
      raise Exception(e)
    finally:
      try:
        await tab.close()
      except:
        pass

  async def download(self, url: str) -> Optional[str]:
    print(f"CTIME: {time.time() - self.time_since_last_init}\n{self.switch_time}")
    if time.time() - self.time_since_last_init > self.switch_time:
      await self.rotate(reinit=False)

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


if __name__ == "__main__":
  down = PDFDownloader("dir")
  print(asyncio.run(down._get_current_ip_geo()))
