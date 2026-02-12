import { test, expect } from "@playwright/test";
import { mockAPIs, mockGeolocation } from "./fixtures/mock-api";

test.describe("Departure Detail (Screen 2)", () => {
  test.beforeEach(async ({ page }) => {
    await mockGeolocation(page);
    await mockAPIs(page);
  });

  test("shows departures after tapping a stop", async ({ page }) => {
    await page.goto("/");

    // Wait for stops to load and tap one
    await page.getByText("Central Station").click();

    // Should show departure times
    await expect(page.getByText(/10:05/)).toBeVisible();
    await expect(page.getByText(/10:12/)).toBeVisible();
  });

  test("shows walking route on map", async ({ page }) => {
    await page.goto("/");
    await page.getByText("Central Station").click();

    // Map should still be visible with route
    await expect(page.locator("[data-testid=map]")).toBeVisible();
  });

  test("can navigate back to stop list", async ({ page }) => {
    await page.goto("/");
    await page.getByText("Central Station").click();

    // Wait for departures
    await expect(page.getByText(/10:05/)).toBeVisible();

    // Tap back
    await page.getByRole("button", { name: /back/i }).click();

    // Should see stop list again
    await expect(page.getByText("Central Station")).toBeVisible();
    await expect(page.getByText("Market Square")).toBeVisible();
  });
});
