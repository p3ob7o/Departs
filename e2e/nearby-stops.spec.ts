import { test, expect } from "@playwright/test";
import { mockAPIs, mockGeolocation } from "./fixtures/mock-api";

test.describe("Nearby Stops (Screen 1)", () => {
  test.beforeEach(async ({ page }) => {
    await mockGeolocation(page);
    await mockAPIs(page);
  });

  test("shows loading state then stop list", async ({ page }) => {
    await page.goto("/");

    // Should eventually show stops
    await expect(page.getByText("Central Station")).toBeVisible();
    await expect(page.getByText("Market Square")).toBeVisible();
  });

  test("shows map centered on user location", async ({ page }) => {
    await page.goto("/");

    // Map container should be visible
    await expect(page.locator("[data-testid=map]")).toBeVisible();
  });

  test("stop rows are tappable", async ({ page }) => {
    await page.goto("/");

    const stopRow = page.getByText("Central Station");
    await expect(stopRow).toBeVisible();

    // Should be clickable
    await stopRow.click();
  });
});
