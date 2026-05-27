import { test, expect } from "@playwright/test";
import { loadCreds, PASSWORD } from "./_admin";

test("unauthenticated visitor is redirected to login", async ({ page }) => {
  await page.goto("/health");
  await expect(page).toHaveURL(/\/login/);
  await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
});

test("super-admin can log in and reach the dashboard", async ({ page }) => {
  const { superEmail } = loadCreds();
  await page.goto("/login");
  await page.getByLabel("Email").fill(superEmail);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page).toHaveURL(/\/health/);
  await expect(
    page.getByRole("heading", { name: "Platform health" }),
  ).toBeVisible();

  // Core nav is present.
  await page.getByRole("link", { name: "Academies" }).click();
  await expect(page).toHaveURL(/\/academies/);
  await expect(
    page.getByRole("heading", { name: "Academies" }),
  ).toBeVisible();
});

test("super-admin can run a privileged service-role op", async ({ page }) => {
  const { superEmail } = loadCreds();
  await page.goto("/login");
  await page.getByLabel("Email").fill(superEmail);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/health/);

  await page.getByRole("link", { name: "Ops" }).click();
  await expect(page).toHaveURL(/\/ops/);
  await page.getByRole("button", { name: /Refresh now/ }).click();
  await expect(
    page.getByText(/materialized views refreshed/i),
  ).toBeVisible({ timeout: 15000 });
});

test("non-super-admin is rejected at login", async ({ page }) => {
  const { ownerEmail } = loadCreds();
  await page.goto("/login");
  await page.getByLabel("Email").fill(ownerEmail);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(
    page.getByText(/not a platform super-admin/i),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/login/);
});
