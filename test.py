from selenium_driverless import webdriver
import asyncio

async def main():
    options = webdriver.ChromeOptions()
    async with webdriver.Chrome(options=options) as driver:
        await driver.get('chrome://settings/content/pdfDocuments', wait_load=True)
        await asyncio.sleep(2)
        
        await driver.execute_script("window.focus();")
        
        print("Tabbing...")
        for _ in range(2):
            await driver.base_target.send_keys('\ue004')
            await asyncio.sleep(0.3)

        print("Pressing Arrow Up...")
        await driver.base_target.send_keys('\ue013')
        
        await asyncio.sleep(0.5)
        await driver.base_target.send_keys('\ue006')
        
        print("Done.")
        await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())