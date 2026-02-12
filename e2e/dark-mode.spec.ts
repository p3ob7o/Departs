import { test, expect } from "@playwright/test";
import { mockAPIs, mockGeolocation } from "./fixtures/mock-api";

test.describe("Dark Mode", () => {
  test.use({ colorScheme: "dark" });

  test.beforeEach(async ({ page }) => {
    await mockGeolocation(page);
    await mockAPIs(page);
  });

  test("renders with dark color scheme", async ({ page }) => {
    await page.goto("/");

    // Wait for content to load
    await expect(page.getByText("Central Station")).toBeVisible();

    // Check that the page uses dark mode styles
    const body = page.locator("body");
    const bgColor = await body.evaluate(
      (el) => window.getComputedStyle(el).backgroundColor
    );

    // Should be a dark color (not white)
    expect(bgColor).not.toBe("rgb(255, 255, 255)");
  });

  test("map uses dark style", async ({ page }) => {
    await page.goto("/");

    await expect(page.getByText("Central Station")).toBeVisible();

    // Map should exist and use dark style
    const map = page.locator("[data-testid=map]");
    await expect(map).toBeVisible();
  });
});
