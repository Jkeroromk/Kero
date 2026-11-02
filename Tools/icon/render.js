const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await page.goto('file://' + process.argv[2]);
  await page.screenshot({ path: process.argv[3], clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  await browser.close();
})();
