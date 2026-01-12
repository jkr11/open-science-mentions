from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
import os
from time import sleep
current_folder = os.getcwd()
chrome_options = Options()
chrome_options.add_experimental_option("prefs", {
    "download.default_directory": current_folder,
    "download.prompt_for_download": False,
    "download.directory_upgrade": True,
    "plugins.always_open_pdf_externally": True,
    "plugins.plugins_list": [{"enabled": False, "name": "Chrome PDF Viewer"}]
})
driver = webdriver.Chrome(options=chrome_options)
url = "https://www.tandfonline.com/doi/pdf/10.1080/13603116.2022.2132425"
try:
    driver.get(url)
except:
    print("dead link")
driver.get("chrome://downloads")
sleep(10)
driver.quit()