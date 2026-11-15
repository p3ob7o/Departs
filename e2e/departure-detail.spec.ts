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

  test("requests the selected direction at a stop with multiple lines", async ({ page }) => {
    await page.route("**/api/stops/nearby*", (route) => route.fulfill({ json: [{
      id: "station/1?A&B", name: "Central Station", type: "subway",
      location: { lat: 52.52, lon: 13.405 }, distance: 50,
      lines: [
        { name: "U2", direction: "Pankow", type: "subway" },
        { name: "U2", direction: "Ruhleben", type: "subway" },
      ],
    }] }));
    const request = page.waitForRequest((req) => req.url().includes("/api/departures?"));
    await page.goto("/");
    await page.getByRole("button", { name: /U2 to Ruhleben/ }).click();
    const params = new URL((await request).url()).searchParams;
    expect(params.get("stopId")).toBe("station/1?A&B");
    expect(params.get("lineName")).toBe("U2");
    expect(params.get("direction")).toBe("Ruhleben");
    await expect(page.getByText("Subway U2 to Ruhleben")).toBeVisible();
  });

  test("shows walking route on map", async ({ page }) => {
    await page.goto("/");
    await page.getByText("Central Station").click();

    // Map should still be visible with route
    await expect(page.getByRole("region", { name: "Map", exact: true })).toBeVisible();
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
