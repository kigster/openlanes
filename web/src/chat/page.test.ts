import { beforeEach, expect, it, vi } from "vitest";

const KEY = "openlanes-page";

beforeEach(() => {
  sessionStorage.clear();
  vi.resetModules();
});

const load = async () => (await import("./page")).pageId;

it("keeps one id for the life of the page, out of storage while it lives", async () => {
  const pageId = await load();
  const id = pageId();
  expect(pageId()).toBe(id);
  expect(sessionStorage.getItem(KEY)).toBeNull();
});

it("is the same page after a reload", async () => {
  const id = (await load())();
  window.dispatchEvent(new Event("pagehide"));
  expect((await load())()).toBe(id);
});

it("is a new page in a tab that copied this one's storage while it was open", async () => {
  sessionStorage.setItem(KEY, "01JPAGEOFTHEORIGINALTAB0");
  const original = (await load())();
  vi.resetModules(); // the duplicate: a fresh module over the storage copied from the original, as it is now
  const copy = (await load())();
  expect(original).toBe("01JPAGEOFTHEORIGINALTAB0");
  expect(copy).not.toBe(original);
});
