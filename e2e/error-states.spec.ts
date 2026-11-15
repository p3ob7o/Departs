import { test, expect } from "@playwright/test";
import {
  mockAPIs,
  mockGeolocation,
  mockGeolocationDenied,
  mockNetworkError,
  mockEmptyStops,
} from "./fixtures/mock-api";

test.describe("Error States", () => {
  test("shows permission error when geolocation is denied", async ({
    page,
  }) => {
    await mockGeolocationDenied(page);
    await mockAPIs(page);
    await page.goto("/");

    await expect(page.getByText(/location permission/i)).toBeVisible();
  });

  for (const code of [2, 3]) {
    test(`recovers from location error ${code} without crashing`, async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.addInitScript((errorCode) => {
        navigator.geolocation.getCurrentPosition = (_success, error) => error?.({ code: errorCode } as GeolocationPositionError);
      }, code);
      await page.goto("/");
      await expect(page.getByRole("button", { name: "Retry" })).toBeVisible();
      expect(errors).toEqual([]);
    });
  }

  test("shows network error when API fails", async ({ page }) => {
    await mockGeolocation(page);
    await mockNetworkError(page);
    await page.goto("/");

    await expect(page.getByText(/couldn't load/i)).toBeVisible();
  });

  test("shows empty state when no stops nearby", async ({ page }) => {
    await mockGeolocation(page);
    await mockEmptyStops(page);
    await page.goto("/");

    await expect(page.getByText(/no public transit/i)).toBeVisible();
  });

  test("retry button refetches data", async ({ page }) => {
    await mockGeolocation(page);
    await mockNetworkError(page);
    await page.goto("/");

    await expect(page.getByText(/couldn't load/i)).toBeVisible();

    // Fix the API before retry
    await mockAPIs(page);

    // Tap retry
    await page.getByRole("button", { name: /retry/i }).click();

    // Should eventually show stops
    await expect(page.getByText("Central Station")).toBeVisible();
  });
});
